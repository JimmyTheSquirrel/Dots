{...}: {
  # Home Assistant — home automation (smart plugs, sensors, etc).
  # Asgard only. Web UI on :8123, tailnet-only like the rest of the stack.
  #
  # NOT in Modules/server.nix deliberately: Asgard's copy of server.nix carries
  # large uncommitted local work and diverges from the Sisyphus copy, so it must
  # not be edited from here. A standalone module sidesteps that entirely.
  flake.nixosModules.home-assistant = {lib, pkgs, ...}: let
    # ── Glance → HA bridge ───────────────────────────────────────────────────
    # Glance renders every widget server-side and injects the markup with
    # innerHTML, so the dashboard cannot talk to HA by itself: a <script> in a
    # widget template never executes, embedding the token would publish it in
    # page source, and HA refuses cross-origin calls anyway. This holds the
    # token server-side and exposes exactly two verbs.
    #
    # ⚠ ALLOWED is the safety boundary, not the UI. The dashboard renders
    # Asgard's and Eclipse's relays as locked, but a locked button is only a
    # suggestion — anything reachable on the tailnet could POST here. Keeping
    # those two entity IDs out of this set is what actually stops a stray
    # request hard-cutting a running machine mid-write.
    haBridge = pkgs.writeText "ha-bridge.py" ''
      import json, os, time, urllib.request
      from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

      HA = "http://localhost:8123"
      TOKEN_PATH = "/run/secrets/ha-token"
      PORT = int(os.environ.get("HA_BRIDGE_PORT", "9556"))

      ALLOWED = {
          "switch.colour_lamp_switch",
          "switch.lounge_room_lamp_switch",
          "switch.christmas_lights_switch",
          "switch.living_room_lights",
      }

      def ha(path, payload=None):
          with open(TOKEN_PATH) as f:
              token = f.read().strip()
          req = urllib.request.Request(
              HA + path,
              data=json.dumps(payload).encode() if payload is not None else None,
              headers={"Authorization": "Bearer " + token,
                       "Content-Type": "application/json"},
              method="POST" if payload is not None else "GET")
          with urllib.request.urlopen(req, timeout=10) as r:
              raw = r.read()
              return json.loads(raw) if raw else None

      class Handler(BaseHTTPRequestHandler):
          def reply(self, code, obj):
              body = json.dumps(obj).encode()
              self.send_response(code)
              self.send_header("Content-Type", "application/json")
              self.send_header("Access-Control-Allow-Origin", "*")
              self.send_header("Access-Control-Allow-Headers", "content-type")
              self.send_header("Content-Length", str(len(body)))
              self.end_headers()
              self.wfile.write(body)

          def do_OPTIONS(self):
              self.reply(200, {})

          def do_GET(self):
              if self.path != "/states":
                  return self.reply(404, {"error": "not found"})
              try:
                  rows = ha("/api/states") or []
                  self.reply(200, {s["entity_id"]: s["state"] for s in rows
                                   if s["entity_id"].split(".")[0] in ("switch", "light")})
              except Exception as exc:
                  self.reply(502, {"error": str(exc)})

          def do_POST(self):
              if not self.path.startswith("/toggle/"):
                  return self.reply(404, {"error": "not found"})
              entity = self.path[len("/toggle/"):]
              if entity not in ALLOWED:
                  return self.reply(403, {"error": "not toggleable", "entity": entity})
              try:
                  ha("/api/services/" + entity.split(".")[0] + "/toggle",
                     {"entity_id": entity})
                  # HA applies service calls asynchronously and a group switch
                  # only settles once its members report back, so an immediate
                  # read returns the OLD state and the button appears to do
                  # nothing. Give it a beat before reading back.
                  time.sleep(0.6)
                  state = (ha("/api/states/" + entity) or {}).get("state")
                  self.reply(200, {"entity": entity, "state": state})
              except Exception as exc:
                  self.reply(502, {"error": str(exc)})

          def log_message(self, *args):
              pass

      ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
    '';
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
        # Members are the three lamp plugs. Asgard's and Eclipse's relays are
        # deliberately NOT here — a group toggle that also cuts the server would
        # be a spectacular way to lose an array.
        switch = [
          {
            platform = "group";
            name = "Living Room Lights";
            entities = [
              "switch.colour_lamp_switch"
              "switch.lounge_room_lamp_switch"
              "switch.christmas_lights_switch"
            ];
          }
        ];
      };
    };

    # Bridge that lets the Glance dashboard toggle switches — see haBridge above.
    # Port 9556 is deliberately absent from allowedTCPPorts: reachable over the
    # trusted tailscale0 only, exactly like network-panel on 9555.
    systemd.services.ha-bridge = {
      description = "Home Assistant toggle bridge for the Glance dashboard";
      after = ["home-assistant.service"];
      wants = ["home-assistant.service"];
      wantedBy = ["multi-user.target"];
      environment.HA_BRIDGE_PORT = "9556";
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${haBridge}";
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        # ha-token is mode 0444 precisely so a DynamicUser can read it.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    # Long-lived access token for the Glance power-monitoring widgets
    # (Modules/server.nix) to authenticate to HA's REST API. Value is set by
    # hand via `sops Secrets/secrets.yaml` — HA tokens can't be minted
    # declaratively, they require an existing logged-in session.
    #
    # mode = "0444": Glance runs as a systemd DynamicUser (random UID per
    # start), so there's no static user to `owner =` this to. Readable by any
    # local user, which is acceptable here — Asgard is single-user and the
    # token only grants read access Glance already needs, over localhost.
    sops.secrets."ha-token" = {
      mode = "0444";
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
