{...}: {
  # Home Assistant — home automation (smart plugs, sensors, etc).
  # Asgard only. Web UI on :8123, tailnet-only like the rest of the stack.
  #
  # Its own nixosModule rather than part of nixosModules.server, so the
  # automation side can be dropped from (or added to) a host on its own.
  flake.nixosModules.home-assistant = {config, lib, pkgs, ...}: let
    # The one plug inventory (entity ids, labels, which are lamps). The bridge's
    # allowlist, its watch list and the Living Room Lights group are all derived
    # from it below — see Modules/Server/_plugs.nix.
    inventory = import ./_plugs.nix;

    # ── Glance → HA bridge ───────────────────────────────────────────────────
    # Glance renders every widget server-side and injects the markup with
    # innerHTML, so the dashboards cannot talk to HA by themselves: a <script>
    # in a widget template never executes, embedding the token would publish it
    # in page source, and HA refuses cross-origin calls anyway. This holds the
    # token server-side, keeps a live snapshot of the plugs over HA's websocket
    # and pushes every change to the dashboards as Server-Sent Events. See
    # Resources/HA-Bridge/ha-bridge.py.
    #
    # ⚠ `allowed` is the safety boundary, not the UI. The dashboards render
    # Asgard's and Eclipse's relays as locked, but a locked button is only a
    # suggestion — anything reachable on the tailnet could POST here. Those two
    # are `light = false` in the inventory, which keeps them out of this list,
    # and that is what actually stops a stray request hard-cutting a running
    # machine mid-write.
    haBridgeConfig = pkgs.writeText "ha-bridge.json" (builtins.toJSON {
      allowed = inventory.toggleable;
      watched = inventory.watched;
      # The pages allowed to call it cross-origin (and so to pass the
      # preflight its X-Dash header forces) — see Modules/Server/_origins.nix.
      # config.asgard is declared by nixosModules.server (default.nix), which
      # every host running this module imports alongside it.
      origins = import ./_origins.nix config.asgard;
    });

    # aiohttp: the stdlib has no websocket client, and it brings an async HTTP
    # server too, which is what holding one open stream per dashboard wants.
    haBridgePython = pkgs.python3.withPackages (ps: [ps.aiohttp]);
  in {
    services.home-assistant = {
      enable = true;
      openFirewall = false; # tailscale0 is already trusted; no LAN exposure

      # NixOS builds Home Assistant with ONLY the Python dependencies of the
      # components listed here. An integration missing from this list will not
      # appear in the UI's "Add integration" flow at all — adding hardware later
      # usually means adding its component here and rebuilding.
      extraComponents = [
        "default_config" # recorder, history, logbook, automation, scripts, ...
        "met" # weather — onboarding expects it
        "radio_browser" # onboarding expects it
        "backup"

        # Device discovery on the LAN. Without these, plugs are not auto-found
        # and every device has to be added by IP by hand.
        "zeroconf" # mDNS — TP-Link/Tapo, Shelly, ESPHome, HomeKit
        "ssdp" # UPnP
        "dhcp" # DHCP-sniffing discovery

        # Smart plug / switch integrations. Broad on purpose — harmless if
        # unused, and avoids a rebuild round-trip once we know the brand.
        "tplink" # TP-Link Kasa (HS100/KP105/KP115...)
        "tplink_tapo" # TP-Link Tapo (P100/P110...) — separate integration
        "shelly" # Shelly Plug / Plug S
        "tasmota" # Tasmota-flashed plugs (needs MQTT)
        "esphome" # ESPHome-flashed plugs
        "tuya" # Tuya cloud — most white-label plugs, incl. SmartLife-branded
        "mqtt" # broker-based devices
        "switchbot"
        "wiz" # WiZ / Philips-adjacent
      ];

      config = {
        homeassistant = {
          name = "Asgard";
          unit_system = "metric";
          temperature_unit = "C";
          time_zone = "Australia/Sydney";
          country = "AU";
          currency = "AUD";
        };

        default_config = {};

        http = {
          server_port = 8123;
          # Reachable over the tailnet; the firewall is what restricts access.
          server_host = ["0.0.0.0"];
        };

        # ── Living Room Lights ────────────────────────────────────────────
        # A `group` platform switch rather than the legacy `group:` integration,
        # so it lands as a real `switch.living_room_lights` entity: one thing to
        # toggle from the dashboard, the HA app and automations alike, with its
        # state derived from the members (on if any member is on).
        #
        # Members are every `light = true` plug in the inventory. Asgard's and
        # Eclipse's relays can never end up here — a group toggle that also
        # cuts the server would be a spectacular way to lose an array.
        switch = [
          {
            platform = "group";
            inherit (inventory.group) name;
            entities = inventory.group.members;
          }
        ];
      };
    };

    # Bridge that lets the dashboards see and toggle switches — see
    # haBridgeConfig above and Resources/HA-Bridge/ha-bridge.py.
    # Port 9556 is deliberately absent from allowedTCPPorts: reachable over the
    # trusted tailscale0 only, exactly like network-panel on 9555. (It binds
    # 0.0.0.0 because the admin Glance calls it directly over the tailnet;
    # MarsBar reaches it through its own serve proxy at /ha.)
    systemd.services.ha-bridge = {
      description = "Home Assistant live-state bridge for the Glance dashboards";
      after = ["home-assistant.service"];
      wants = ["home-assistant.service"];
      wantedBy = ["multi-user.target"];
      environment = {
        HA_BRIDGE_PORT = "9556";
        HA_BRIDGE_CONFIG = "${haBridgeConfig}";
      };
      serviceConfig = {
        ExecStart = "${haBridgePython}/bin/python3 ${../../Resources/HA-Bridge/ha-bridge.py}";
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        # The token arrives as a systemd credential: systemd (as root) copies
        # the root-only sops file into a private, per-service directory
        # ($CREDENTIALS_DIRECTORY) that only this unit's DynamicUser can read.
        # This is what lets the secret itself stop being world-readable — see
        # sops.secrets."ha-token" below.
        LoadCredential = "ha-token:${config.sops.secrets."ha-token".path}";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        LockPersonality = true;
      };
    };

    # Long-lived access token for HA's API, used by ha-bridge (above) and by the
    # Glance power-monitoring widgets (Modules/Server/glance.nix). Value is set by hand
    # via `sops Secrets/secrets.yaml` — HA tokens can't be minted declaratively,
    # they require an existing logged-in session.
    #
    # ⚠ This is an ADMIN token: anything holding it can call any HA service,
    # including switch.toggle on switch.server_power_switch — Asgard's own mains
    # feed. It used to be mode 0444 ("read access Glance already needs"), which
    # let every local uid read it and cut the power, bypassing ha-bridge's
    # allowlist entirely.
    #
    # Now: owned by root, readable only by the `ha-token` group.
    #   • ha-bridge does not need the group — it gets a credential copy (above).
    #   • Glance does, for now: its HA widgets read this file with Glance's
    #     ${secret:ha-token} syntax, and as a DynamicUser it has no static uid
    #     to `owner =` this to. A supplementary group works with DynamicUser.
    # TODO: give glance.service its own LoadCredential + Glance's
    # ${readFileFromEnv:…} (or a sops.templates env file) and drop the group
    # and the SupplementaryGroups line below, leaving this root-only 0400.
    sops.secrets."ha-token" = {
      mode = "0440";
      group = "ha-token";
      # A credential is copied at unit start, so a rotated token only reaches
      # the bridge on restart.
      restartUnits = ["ha-bridge.service"];
    };
    users.groups.ha-token = {};
    systemd.services.glance.serviceConfig.SupplementaryGroups = ["ha-token"];

    # Discovery protocols are multicast and arrive unsolicited, so the firewall
    # drops them unless explicitly allowed. Scoped to the LAN interface — the
    # plugs live on 192.168.0.0/24, not on the tailnet.
    networking.firewall.interfaces."enp3s0".allowedUDPPorts = [
      5353 # mDNS / zeroconf
      1900 # SSDP / UPnP
    ];

    # State (device pairings, credentials, entity registry, recorder DB) lives in
    # /var/lib/hass and is NOT declarative — see Claude/home-assistant.md.
    systemd.services.home-assistant.serviceConfig.Restart = lib.mkDefault "on-failure";
  };
}
