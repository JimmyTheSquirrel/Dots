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

    # ══════════════════════════════════════════════════════════════════════
    # BEDSIDE BULBS — a remembered colour, and getting it back after a cut
    # ══════════════════════════════════════════════════════════════════════
    # The bedroom lamps are TOUCH LAMPS: the base cuts mains, so the bulb
    # reboots every time it is switched off and on. Two separate things were
    # broken by that, and they need different fixes:
    #
    #  1. It came back DARK. Each bulb's `select.<slug>_power_on_state` ships
    #     as "Always Off", so the firmware deliberately boots the light off.
    #     holdPowerOn, below, parks every one of them on
    #     "Restore Power Off State" and keeps it there — that alone makes the
    #     bulb come back on, by itself, as it was, with no HA involved.
    #
    #  2. HA could not put the colour back even if it wanted to, because an
    #     unavailable light has no attributes to read. So the choice lives in
    #     HA instead of in the bulb: one input_select + one input_number per
    #     bulb (the inventory's `preset` and `bright`), which is what survives
    #     the power cut. restoreAutomation re-applies them when the bulb
    #     reappears, as a backstop to the firmware restore, and both dashboards
    #     read the same two entities back to light the right swatch and place
    #     the slider.
    #
    # Everything below is generated from inventory.presets, so a colour cannot
    # exist in the automation and not on the dashboards, or the other way.
    bulbs = inventory.bulbs;
    # The fixed presets, plus "Custom" — which is a real option on the
    # input_select but has no fixed colour: it means "whatever the five sliders
    # currently say". Everything that validates a preset name has to accept it.
    presetNames = (map (p: p.name) inventory.presets) ++ [ inventory.customName ];
    customChannels = inventory.customChannels;
    powerOnEntities = map (b: b.powerOn) bulbs;

    # Jinja literals built from the preset table.
    jStrList = xs: "[${lib.concatMapStringsSep ", " (x: "'${x}'") xs}]";

    # Every preset is now one service key — rgbww_color — because the reflashed
    # firmware gives the bulb a single combined colour mode. That is worth more
    # than it looks: the old table mixed `hs_color` with `color_temp_kelvin`,
    # and since a Jinja template can choose a VALUE but never a KEY, the restore
    # automation needed a two-branch `choose` to pick between them. One key
    # removes the branch entirely.
    rgbwwMap = "{${lib.concatMapStringsSep ", " (p:
      "'${p.name}': [${lib.concatMapStringsSep ", " toString p.rgbww}]")
      inventory.presets}}";
    rgbwwFallback = "[${lib.concatMapStringsSep ", " toString
      (builtins.head (builtins.filter (p: p.name == inventory.defaultPreset) inventory.presets)).rgbww}]";

    # "Custom" reads the five sliders instead of the table. Order matters and is
    # the rgbww order: red, green, blue, cold white, warm white.
    customList = "[${lib.concatMapStringsSep ", " (c:
      "states('${c.entity}') | float(${toString c.defaultValue}) | round | int")
      customChannels}]";

    # One expression for every case: the sliders when Custom is picked, the
    # table otherwise, and the default preset's own channels if the remembered
    # name has since been removed from the table.
    colourOf = "{{ ${customList} if pick == '${inventory.customName}'"
      + " else ${rgbwwMap}.get(pick, ${rgbwwFallback}) }}";

    # Never 0 % (which reads as "broken bulb", not "dim"), and never the
    # cold-start 1 % an untouched input_number holds — see the note on
    # input_number below for why neither carries an `initial`.
    brightOf = b:
      "{{ [5, (states('${b.bright}') | float(${toString inventory.defaultBrightness}) | round | int)] | max }}";

    # One automation per bulb: it needs that bulb's own two helper entities.
    # `pick` normalises the remembered preset once per run, so a helper left at
    # `unknown` on a fresh install still produces a sane colour rather than
    # falling through to whatever the choose's default happens to be.
    restoreAutomation = b: {
      alias = "Bedroom · ${b.name} — restore colour after power-on";
      id = "bedroom_restore_${b.slug}";
      # restart: the bulb can flap while its wifi settles, and the last
      # power-on is the only one whose colour anybody is waiting for.
      mode = "restart";
      variables.pick =
        "{{ states('${b.preset}') if states('${b.preset}') in ${jStrList presetNames}"
        + " else '${inventory.defaultPreset}' }}";
      triggers = [
        # Coming back from `unavailable` IS the touch lamp being switched on:
        # mains returning is the only thing that makes the bulb reappear. A
        # dashboard turn-off leaves it available ("off"), so this never fights
        # someone deliberately switching a lamp off.
        { trigger = "state"; entity_id = b.entity; from = "unavailable"; }
      ];
      actions = [
        # The bulb answers HA before it will accept a colour; without this the
        # turn_on lands on a half-booted light and is silently dropped.
        { delay.seconds = 4; }
        {
          condition = "template";
          value_template = "{{ states('${b.entity}') not in ['unavailable', 'unknown'] }}";
        }
        {
          # One key for every preset, so no branch. `.get` with the default
          # preset's own channels as the fallback means a preset name that has
          # been removed from the table since the helper was last written still
          # restores something sane rather than failing the template.
          action = "light.turn_on";
          target.entity_id = b.entity;
          data = {
            rgbww_color = colourOf;
            brightness_pct = brightOf b;
          };
        }
      ];
    };

    # Hold every bulb's power-on behaviour at "Restore Power Off State".
    # This is the declarative answer to a setting that lives in the bulb's own
    # flash and so cannot be declared: HA re-asserts it instead, on every start
    # and any time one drifts — including after a factory reset.
    holdPowerOn = {
      alias = ''Bedroom bulbs — hold "${inventory.restoreState}"'';
      id = "bedroom_bulbs_power_on_state";
      mode = "single";
      triggers = [
        { trigger = "homeassistant"; event = "start"; }
        { trigger = "state"; entity_id = powerOnEntities; }
      ];
      conditions = [{
        condition = "template";
        # Only when a bulb that is actually REACHABLE has the wrong value. A
        # bulb whose lamp is switched off at the base is `unavailable`, and
        # trying to write to it would just log an error on every HA start.
        value_template =
          "{{ expand(${jStrList powerOnEntities})"
          + " | rejectattr('state', 'in', ['unavailable', 'unknown', '${inventory.restoreState}'])"
          + " | list | count > 0 }}";
      }];
      actions = [
        # A bulb that just booted is reachable before it is settled.
        { delay.seconds = 10; }
        {
          action = "select.select_option";
          continue_on_error = true;
          # Target only the wrong ones, recomputed after the delay.
          target.entity_id =
            "{{ expand(${jStrList powerOnEntities})"
            + " | rejectattr('state', 'in', ['unavailable', 'unknown', '${inventory.restoreState}'])"
            + " | map(attribute='entity_id') | list }}";
          data.option = inventory.restoreState;
        }
      ];
    };

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
      # Charted on the Power page from HA's history API (GET /history).
      history = map (p: p.power) inventory.plugs;
      # The pages allowed to call it cross-origin (and so to pass the
      # preflight its X-Dash header forces) — see Modules/Server/_origins.nix.
      # config.asgard is declared by nixosModules.server (default.nix), which
      # every host running this module imports alongside it.
      # ── What POST /light may recolour ─────────────────────────────────
      # The same kind of boundary as `allowed`, for colour rather than power:
      # only these light entities accept a colour, and only one of `presets`.
      # Each names the two helper entities the bridge writes the choice into —
      # which is also the only reason the bridge may touch an input_select or
      # an input_number at all. Nothing else in HA is reachable through it.
      lights = builtins.listToAttrs (map (c: {
        name = c.entity;
        value = { inherit (c) preset bright; };
      }) inventory.colourable);
      # The preset table as the bridge needs it: a name, and either hs or
      # kelvin. Generated from the same list the swatches and the restore
      # automation come from, so a swatch can never ask for a colour the
      # bridge would reject.
      presets = builtins.listToAttrs (map (p: {
        name = p.name;
        value = { inherit (p) rgbww; };
      }) inventory.presets);

      # The "mix your own" swatch: the option name that means "use the
      # sliders", and the five input_numbers behind it in rgbww order. The
      # bridge writes these and nothing else when a caller sends `channels`.
      customName = inventory.customName;
      customChannels = map (c: { inherit (c) key entity label; }) inventory.customChannels;
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

        # ── The bedside bulbs' memory ─────────────────────────────────────
        # One pair per bulb, generated from the inventory: the remembered
        # colour and brightness that a touch lamp's power cut cannot erase,
        # because they live here and not in the bulb. Both dashboards write
        # them through ha-bridge and read them straight back off its state
        # stream — an input_select's state is a plain string like any relay's,
        # which is what lets a swatch light up and a slider find its place
        # without the bridge ever streaming light attributes.
        #
        # ⚠ Deliberately NO `initial:` on either. `initial` is re-applied on
        # every Home Assistant start, which would throw her choice away on
        # every rebuild of this module; without it HA restores the last value
        # from .storage instead. The cost is that a FRESH install starts at the
        # first option and at min, not at defaultPreset/defaultBrightness —
        # cosmetic, self-correcting on the first tap, and the restore
        # automation substitutes the proper defaults for `unknown` anyway.
        # See Claude/home-assistant.md → the declarative limit.
        input_select = builtins.listToAttrs (map (b: {
          name = "${b.slug}_preset";
          value = {
            name = "${b.name} colour";
            options = presetNames;
            icon = "mdi:palette";
          };
        }) bulbs);

        # Per-bulb brightness, plus the five shared custom-colour channels.
        # ⚠ The custom five are 0-255 RAW CHANNEL VALUES, not percentages, and
        # they are NOT perceptually linear — the firmware's gamma_correct: 2.8
        # means the interesting part of the range is bunched low. step = 1 so a
        # mix can actually be dialled in; see the tuning note in _plugs.nix.
        input_number = builtins.listToAttrs (map (c: {
          name = "bedroom_custom_${c.key}";
          value = {
            name = "Bedroom custom ${c.label}";
            min = 0;
            max = 255;
            step = 1;
            mode = "slider";
            inherit (c) icon;
          };
        }) customChannels) // builtins.listToAttrs (map (b: {
          name = "${b.slug}_brightness";
          value = {
            name = "${b.name} brightness";
            min = 1;
            max = 100;
            step = 5;
            unit_of_measurement = "%";
            mode = "slider";
            icon = "mdi:brightness-6";
          };
        }) bulbs);

        # The two touch-lamp fixes — see the long note in the `let` above.
        # These are YAML automations, so they are read-only in HA's UI by
        # design: this file is where they are changed.
        automation = [ holdPowerOn ] ++ map restoreAutomation bulbs;
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
    # Now sops' default: root-only 0400. Neither consumer reads this file
    # itself — each gets a private copy as a systemd credential (LoadCredential:
    # systemd, as root, copies it into a per-unit directory only that unit's
    # DynamicUser can read):
    #   • ha-bridge, above, reads $CREDENTIALS_DIRECTORY/ha-token
    #   • glance.service (glance.nix) reads it through Glance's
    #     ''${readFileFromEnv:HA_TOKEN_FILE}, the same way it gets the SABnzbd key
    sops.secrets."ha-token" = {
      # A credential is copied at unit start (and Glance reads its config only
      # then), so a rotated token reaches both only on restart.
      restartUnits = ["ha-bridge.service" "glance.service"];
    };

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
