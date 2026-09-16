{...}: {
  # Home Assistant — home automation (smart plugs, sensors, etc).
  # Asgard only. Web UI on :8123, tailnet-only like the rest of the stack.
  #
  # NOT in Modules/server.nix deliberately: Asgard's copy of server.nix carries
  # large uncommitted local work and diverges from the Sisyphus copy, so it must
  # not be edited from here. A standalone module sidesteps that entirely.
  flake.nixosModules.home-assistant = {lib, ...}: {
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
      };
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
