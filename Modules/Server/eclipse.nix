{ ... }: {
  # Asgard — the Eclipse control endpoint: the JSON API + live event stream
  # behind Glance's Eclipse page and MarsBar's TV card, driving the LibreELEC TV
  # box over SSH. See Claude/eclipse.md.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    inherit (config.asgard) lanInterface;
  in
  {

    # Eclipse control endpoint — status JSON, /events (SSE) and the /act/ verbs.
    # The admin Glance draws its Eclipse page natively from /events
    # (Resources/Glance/eclipse.js); it used to iframe a page this served.
    # Drives the LibreELEC TV box (100.80.62.3) over SSH.
    #
    # SSH not Kodi JSON-RPC on purpose: the headline action is "restart Kodi when
    # it has wedged", and a wedged Kodi cannot answer its own API. Kodi's HTTP
    # server is disabled on Eclipse anyway. See Claude/eclipse.md.
    # LAN data sink for the Eclipse speed test, scoped to the LAN interface.
    #
    # The panel itself (9554) stays OFF the LAN deliberately — it carries every
    # /act/ verb including `reboot`, and tailscale0 being a trustedInterface is
    # what keeps it reachable to us and nobody else. 9557 serves a zero-filled
    # payload and nothing else (SpeedtestHandler in eclipse-control.py), so the
    # worst anything on the wifi can do with it is waste bandwidth.
    #
    # Needed because a LAN speed test has to talk to a LAN-reachable port: the
    # test used to always run over Tailscale and reported ~19 Mbps of WireGuard
    # overhead even with Jellyfin in LAN mode.
    networking.firewall.interfaces.${lanInterface}.allowedTCPPorts = [ 9557 ];

    systemd.services.eclipse-control = {
      description = "Eclipse (LibreELEC) control endpoint for Glance";
      # `after` network-online.target alone orders against a target nothing
      # has pulled in — NixOS warns about exactly that — so want it as well.
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.openssh ];
      environment = {
        ECLIPSE_HOST = "100.80.62.3";
        ECLIPSE_KEY = config.sops.secrets."eclipse-ssh-key".path;
        ECLIPSE_PORT = "9554";
        # The dashboards allowed to call /act/* cross-origin (comma-separated).
        # Generated from the same list ha-bridge uses, so the backends cannot
        # drift apart — see Modules/Server/_origins.nix.
        DASH_ORIGINS = lib.concatStringsSep "," (import ./_origins.nix config.asgard);
        # wolf-bridge on Sisyphus (Modules/Gaming/wolf.nix): the Eclipse page's
        # "Streams" card lists Wolf's sessions and can end a stuck one. The
        # bridge answers only Asgard's tailnet IP, so this proxies it.
        WOLF_BRIDGE_URL = "http://sisyphus:9560";
        # "On the TV": Jellyfin's session list, filtered to the Kodi addon.
        JELLYFIN_URL = "http://127.0.0.1:8096";
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../../Resources/Eclipse-Control/eclipse-control.py}";
        Restart = "always";
        RestartSec = 5;
        # Home for the SSH ControlMaster socket (the script reads
        # $RUNTIME_DIRECTORY): systemd creates /run/eclipse-control at start and
        # removes it at stop, so a socket can never outlive the unit or be
        # pre-created by anyone else. Without it the script falls back to a
        # mkdtemp() under /tmp. 0700 because whoever can reach that socket can
        # run commands on the Pi without the key.
        RuntimeDirectory = "eclipse-control";
        RuntimeDirectoryMode = "0700";
        # For "On the TV" — read from $CREDENTIALS_DIRECTORY, never a shared path.
        LoadCredential = [ "jellyfin-api-key:${config.sops.secrets."jellyfin-api-key".path}" ];
      };
    };

    # Private half of the dedicated Asgard→Eclipse key. Public half lives in
    # Eclipse's /storage/.ssh/authorized_keys (imperative — see Claude/eclipse.md).
    sops.secrets."eclipse-ssh-key"          = { mode = "0400"; };

  };
}
