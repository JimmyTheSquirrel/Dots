{ inputs, ... }: {
  # Asgard — the media server, as one NixOS module (`flake.nixosModules.server`)
  # split by area. Every file below defines that same module; flake-parts
  # merges them, so Hosts/Asgard/system.nix imports just `self.nixosModules.server`.
  #
  #   default.nix    nixflix import, options.asgard (shared facts), podman,
  #                  firewall, media group, shared secrets, sysctls
  #   storage.nix    mergerfs pool, bind mounts, RequiresMountsFor, tmpfiles
  #   arr.nix        Sonarr/Radarr/Lidarr/Prowlarr, missing-search, arr-policy
  #   recyclarr.nix  quality profiles (TRaSH) + the Seerr-after-sync ordering
  #   jellyfin.nix   Jellyfin + Jellyseerr, provider order, QSV graphics
  #   downloads.nix  SABnzbd in the Mullvad namespace, Decluttarr
  #   books.nix      Audiobookshelf + Shelfarr + books-setup
  #   manga.nix      Suwayomi + FlareSolverr
  #   photos.nix     Immich
  #   files.nix      FileBrowser
  #   network.nix    Tailscale, status proxy, speed test, network panel,
  #                  Cloudflare tunnel, WAN egress shaping
  #   eclipse.nix    Eclipse TV-box control endpoint
  #   glance.nix     the Glance dashboard and its whole config
  #   ttyd.nix       web terminal
  #   _lib.nix       shell helpers (waitForHttp), imported by path
  #
  # This is the ONLY file that imports nixflix. The rest of the module used to
  # be one 5,000-line server.nix; it was split as a pure move (the system
  # derivation was identical before and after).

  flake.nixosModules.server = { config, pkgs, lib, activeUser, ... }:
  {

    imports = [
      inputs.nixflix.nixosModules.default

      # ── Asgard facts that more than one unit needs ──
      # Read-only options rather than a `let`, so that every unit — and
      # Hosts/Asgard/system.nix — reads the one definition. Each of these was
      # previously typed out in several places, and SABnzbd's host_whitelist
      # still carried the tailnet IP from before the node was re-keyed.
      ({ lib, ... }: {
        options.asgard = {
          tailnetIp = lib.mkOption {
            type = lib.types.str;
            default = "100.126.205.100";
            readOnly = true;
            description = ''
              Asgard's Tailscale IPv4. Stable for the life of the node key, but NOT
              forever — it was 100.119.193.77 before a re-key.
            '';
          };
          tailnetFqdn = lib.mkOption {
            type = lib.types.str;
            default = "asgard.tailb54b82.ts.net";
            readOnly = true;
            description = "Asgard's MagicDNS name on the tailnet.";
          };
          lanInterface = lib.mkOption {
            type = lib.types.str;
            default = "enp3s0";
            readOnly = true;
            description = ''
              The wired LAN NIC — the one WAN egress is shaped on, the network panel
              samples, and the few LAN-scoped firewall holes are opened on.
            '';
          };
          vethHostIp = lib.mkOption {
            type = lib.types.str;
            default = "10.200.1.1";
            readOnly = true;
            description = ''
              Host end (veth-vpn-br) of the veth pair into the Mullvad namespace — the
              one address reachable from BOTH the podman containers and SABnzbd.
            '';
          };
          vethNamespaceIp = lib.mkOption {
            type = lib.types.str;
            default = "10.200.1.2";
            readOnly = true;
            description = "Namespace end (veth-vpn) of that pair, where SABnzbd listens.";
          };
        };
      })
    ];

# ══════════════════════════════════════════════════════════════════════════════
# NIXFLIX — Arr Stack + Jellyfin + SABnzbd
# Auto-wires: Prowlarr ↔ Sonarr/Radarr/Lidarr, Seerr ↔ Jellyfin/Sonarr/Radarr
# All API keys pre-generated and stored in sops — fully reproducible on deploy.
#
# Port reference (Tailscale-only unless noted):
#   Sonarr     8989  |  Radarr    7878  |  Lidarr   8686
#   Prowlarr   9696  |  SABnzbd  8080
#   Jellyfin   8096  (+ Cloudflare tunnel at jellyfin.bifrost-vault.com)
#   Jellyseerr 5055  (+ Cloudflare tunnel at requests.bifrost-vault.com)
# ══════════════════════════════════════════════════════════════════════════════

    nixflix = {
      enable = true;
      mediaDir    = "/data/media";
      downloadsDir = "/downloads";
      stateDir    = "/data/.state/services";
    };

# ══════════════════════════════════════════════════════════════════════════════
# INFRASTRUCTURE — Podman, firewall, media group, shared secrets, sysctls
# ══════════════════════════════════════════════════════════════════════════════

    # --- Podman (OCI backend for the containers: Audiobookshelf, Shelfarr,
    # FlareSolverr, FileBrowser, Decluttarr). Glance is NOT one of them — it runs
    # as a native unit so server-stats can read the host's /proc and /sys. ---
    #
    # No dockerSocket: its only consumer was cAdvisor, removed along with the
    # rest of the metrics stack, and the socket is root-equivalent for anyone in
    # the podman group.
    virtualisation.oci-containers.backend = "podman";
    virtualisation.podman = {
      enable = true;
    };
    # Allow containers to reach host-bound services (arr, immich, etc.).
    # `podman0` is netavark's default bridge — the backend this podman uses.
    # (`cni-podman0`, the CNI-era name, was listed too and matched nothing.)
    # tailscale0 trusted so all services are reachable from any tailnet device by hostname
    # `veth-vpn-br` is the HOST side of the veth pair into the Mullvad namespace.
    # Without it trusted, the namespace can ping the host but every TCP connection
    # is dropped — which silently breaks any download client in the namespace that
    # has to fetch from a host service.
    #
    # Concretely: SABnzbd lives in that namespace, and Shelfarr's SAB adapter only
    # speaks `mode=addurl` — it hands SAB a Prowlarr URL and expects SAB to fetch
    # the NZB itself. SAB could not reach Prowlarr, so every book sat in the queue
    # at 0% showing "Fetch NZB from URL" with an exponentially growing WAIT and
    # never failed outright. Sonarr/Radarr are unaffected because they push the
    # NZB contents themselves rather than passing a URL.
    #
    # Safe: the only peer on this link is the VPN namespace, which contains just
    # SABnzbd and is not reachable from outside the host.
    networking.firewall.trustedInterfaces = [ "podman0" "tailscale0" "veth-vpn-br" ];
    networking.firewall.allowedTCPPorts = [
      8096 # Jellyfin — open to LAN so home devices connect directly (no CF tunnel / upload round-trip)
    ]; # everything else accessed via Tailscale (trustedInterfaces)

    # --- Claude Code auth ---
    # OAuth credentials live in ~/.claude/.credentials.json (set up via `claude login`).
    # managed-settings intentionally left empty so OAuth takes precedence.

    # --- Shared media group ---
    # All service users and containers use this group for /data/media access.
    #
    # The group itself is nixflix's, and so is its gid: 169, set with mkForce
    # in nixflix's jellyfin module. This file used to declare `gid = 1001`,
    # which lost to that mkForce without a word — and the containers' PGID was
    # copied from the dead value. Anything that needs the number reads
    # config.users.groups.media.gid instead of restating it.
    users.users.${activeUser}.extraGroups = [ "media" ];
    users.users.jellyfin.extraGroups = [ "media" "render" "video" ];

    # One definition, on purpose. mergerfs provides mount.fuse.mergerfs, needed to
    # mount the /data/media pool (storage.nix); tmux backs ttyd's persistent
    # sessions (ttyd.nix). Splitting this list across those files would reorder
    # system-path: definitions from several files concatenate in the order the
    # files are merged (reverse-alphabetical here), not the order you read them.
    environment.systemPackages = [ pkgs.kitty.terminfo pkgs.mergerfs pkgs.tmux ];

    # --- Sops secrets ---
    # All secrets live in Secrets/secrets.yaml. Each `sops.secrets.*` declaration
    # sits in the file of the service that owns it (arr.nix, jellyfin.nix,
    # downloads.nix, network.nix, eclipse.nix); only the credentials shared by
    # several services are declared here.
    # Before first build, populate them with:
    #
    #   sops ~/Dots/Secrets/secrets.yaml
    #
    # Add each key as a plain string (generate with: od -An -tx1 -N16 /dev/urandom | tr -d ' \n'):
    #   sonarr-api-key: "<32 hex chars>"
    #   radarr-api-key: "<32 hex chars>"
    #   lidarr-api-key: "<32 hex chars>"
    #   prowlarr-api-key: "<32 hex chars>"
    #   jellyseerr-api-key: "<32 hex chars>"
    #   sabnzbd-api-key: "<32 hex chars>"
    #   sabnzbd-nzb-key: "<32 hex chars>"
    #   jellyfin-api-key: "<32 hex chars>"
    #   jellyfin-admin-password: "<your chosen password>"
    #   cloudflare-tunnel: "<full credentials JSON from Cloudflare dashboard>"
    #
    # The shared admin login: the arrs' Forms auth (arr.nix), FileBrowser
    # (files.nix), Immich's seeded admin (photos.nix) and Audiobookshelf's root
    # user (books.nix).
    sops.secrets."admin-username"           = {};
    sops.secrets."admin-password"           = {};

    # Kernel UDP buffer tuning for smooth streaming over Tailscale
    boot.kernel.sysctl = {
      "net.core.rmem_max"           = lib.mkDefault 26214400;
      "net.core.wmem_max"           = lib.mkDefault 26214400;
      "net.core.netdev_max_backlog" = lib.mkDefault 5000;
    };

  };
}
