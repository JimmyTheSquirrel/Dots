{ ... }: {
  # Asgard — downloads: SABnzbd (through nixflix) confined to a Mullvad
  # WireGuard network namespace, and Decluttarr, which clears dead queue items.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    inherit (config.asgard) tailnetIp tailnetFqdn vethHostIp vethNamespaceIp;
  in
  {

    nixflix = {
      # SABnzbd usenet download client
      usenetClients.sabnzbd = {
        enable = true;
        settings = {
          misc = {
            api_key._secret  = config.sops.secrets."sabnzbd-api-key".path;
            nzb_key._secret  = config.sops.secrets."sabnzbd-nzb-key".path;
            port = 8080;
            par2_multicore = 1;
            par2_threads = 12;
            abort_max_missing = 10;
            fail_hopeless_jobs = true;
            pause_on_pwrar = 2;            # 0=warn, 1=pause, 2=abort. Abort → Failed status → Decluttarr blocklists + Sonarr/Radarr re-search. Prevents jobs stalling forever on encrypted/corrupt RARs.
            # Every name SAB is reached by. The tailnet IP here was stale
            # (100.119.193.77, from before a re-key) until it was derived.
            host_whitelist = lib.concatStringsSep "," [
              "asgard" tailnetFqdn tailnetIp "host.containers.internal" vethNamespaceIp
            ];
            inet_exposure = 4;
            x_frame_options = 0;
            web_color = "Night";
            web_compact = true;
            web_fullscreen = true;
            web_tabbed = true;

            # Performance
            article_cache_size = "1G";     # RAM cache — reduces disk thrashing
            enable_par_cleanup = true;     # delete par2 files after successful repair
            pause_on_post_processing = false; # keep downloading while post-processing

            # Direct Unpack — KEEP OFF. Known SAB bug: starts unrar before deobfuscation
            # completes on obfuscated NZBs → partial extracts → jobs marked failed with full
            # MKV sitting in _FAILED_ folder (forum t=27128). Must set BOTH keys: SAB's
            # test_disk_performance() in directunpacker.py forces direct_unpack=True on any
            # disk >100 MB/s when direct_unpack_tested=False. Setting tested=True skips that.
            direct_unpack = false;
            direct_unpack_tested = true;

            # Cleanup hygiene — SAB doesn't auto-delete partial files by default.
            # delete_failed makes SAB nuke incomplete folder when job transitions to failed
            # (won't catch .1 races or _FAILED_ bug #2840 — the zombie sweeper handles those).
            delete_failed = true;
            history_retention = "30";
            history_retention_option = "days-archive";

            # Skip pre-download article verification. With pre_check=1 SAB scans every
            # article on the server before download starts — adds the "Checking" phase
            # that clogs the queue UI for minutes. Real download already checks article
            # CRCs (verify_xff_header path), pre_check is redundant.
            pre_check = false;

            # SAB upstream default. Was set to 3 from a now-rolled-back perf-tuning attempt.
            max_art_tries = 5;
          };
          servers = [
            {
              name = "FrugalUsenet";
              host = "aunews.frugalusenet.com";
              port = 563;
              username._secret = config.sops.secrets."usenet/frugalusenet/username".path;
              password._secret = config.sops.secrets."usenet/frugalusenet/password".path;
              connections = 60;
              ssl = true;
              priority = 0;
              timeout = 30;
              required = true;
            }
            {
              name = "Newshosting";
              host = "news.newshosting.com";
              port = 563;
              username._secret = config.sops.secrets."usenet/newshosting/username".path;
              password._secret = config.sops.secrets."usenet/newshosting/password".path;
              connections = 30;
              ssl = true;
              priority = 0;
              timeout = 30;
              optional = false;
            }
          ];
        };
      };
    };

    # unrar in SABnzbd service PATH — required for RAR-packed NZBs
    systemd.services.sabnzbd.path = [ pkgs.unrar ];

    # ── Mullvad VPN namespace for SABnzbd ──────────────────────────────────────
    # Creates an isolated network namespace with a WireGuard tunnel to Mullvad.
    # SABnzbd runs inside this namespace — all Usenet traffic goes through the VPN.
    # A veth pair bridges the namespace to the host so the SABnzbd web UI (port 8080)
    # remains accessible from Tailscale/LAN.
    #
    # If the VPN goes down, SABnzbd has no network — acts as a kill switch.

    # 1. Create the "vpn" network namespace
    systemd.services."netns-vpn" = {
      description = "VPN network namespace";
      before = [ "network.target" "wg-mullvad.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.iproute2}/bin/ip netns add vpn";
        ExecStop = "${pkgs.iproute2}/bin/ip netns del vpn";
      };
    };

    # 2. WireGuard interface inside the namespace
    systemd.services.wg-mullvad = {
      description = "WireGuard tunnel (Mullvad) in vpn namespace";
      bindsTo = [ "netns-vpn.service" ];
      requires = [ "network-online.target" ];
      after = [ "netns-vpn.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        # Create WireGuard interface and move it into the namespace
        ${pkgs.iproute2}/bin/ip link add wg0 type wireguard
        ${pkgs.iproute2}/bin/ip link set wg0 netns vpn

        # Configure WireGuard with Mullvad credentials
        ${pkgs.iproute2}/bin/ip netns exec vpn \
          ${pkgs.wireguard-tools}/bin/wg set wg0 \
            private-key ${config.sops.secrets."mullvad-wg-private-key".path} \
            peer 4JpfHBvthTFOhCK0f5HAbzLXAVcB97uAkuLx7E8kqW0= \
            allowed-ips 0.0.0.0/0,::/0 \
            endpoint 146.70.200.2:51820 \
            persistent-keepalive 25

        # Assign addresses and bring up
        ${pkgs.iproute2}/bin/ip -n vpn address add 10.66.10.54/32 dev wg0
        ${pkgs.iproute2}/bin/ip -n vpn -6 address add fc00:bbbb:bbbb:bb01::3:a35/128 dev wg0
        ${pkgs.iproute2}/bin/ip -n vpn link set wg0 up
        ${pkgs.iproute2}/bin/ip -n vpn route add default dev wg0
        ${pkgs.iproute2}/bin/ip -n vpn -6 route add default dev wg0

        # Bring up loopback inside namespace
        ${pkgs.iproute2}/bin/ip -n vpn link set lo up
      '';
      preStop = ''
        ${pkgs.iproute2}/bin/ip -n vpn link del wg0 || true
      '';
    };

    # 3. Veth pair — bridges SABnzbd web UI from vpn namespace to host
    #    Host side: veth-vpn-br 10.200.1.1/24
    #    VPN side:  veth-vpn    10.200.1.2/24
    systemd.services.veth-vpn = {
      description = "Veth bridge to vpn namespace (SABnzbd web UI)";
      bindsTo = [ "wg-mullvad.service" ];
      after = [ "wg-mullvad.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        ${pkgs.iproute2}/bin/ip link add veth-vpn-br type veth peer name veth-vpn
        ${pkgs.iproute2}/bin/ip link set veth-vpn netns vpn

        # Host side
        ${pkgs.iproute2}/bin/ip address add ${vethHostIp}/24 dev veth-vpn-br
        ${pkgs.iproute2}/bin/ip link set veth-vpn-br up

        # VPN namespace side
        ${pkgs.iproute2}/bin/ip -n vpn address add ${vethNamespaceIp}/24 dev veth-vpn
        ${pkgs.iproute2}/bin/ip -n vpn link set veth-vpn up

        # Allow namespace to reach host (for arr API callbacks)
        ${pkgs.iproute2}/bin/ip netns exec vpn \
          ${pkgs.iproute2}/bin/ip route add ${vethHostIp}/32 dev veth-vpn
      '';
      preStop = ''
        ${pkgs.iproute2}/bin/ip link del veth-vpn-br || true
      '';
    };

    # 3b. socat proxy — exposes SABnzbd (inside vpn namespace) on host port 8080
    # All access goes through this: web UI, arr callbacks, Glance's queue
    # widgets, Tailscale.
    systemd.services.sabnzbd-proxy = {
      description = "SABnzbd proxy (host:8080 → vpn namespace)";
      bindsTo = [ "veth-vpn.service" ];
      after = [ "veth-vpn.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:8080,fork,reuseaddr,bind=0.0.0.0 TCP:${vethNamespaceIp}:8080";
        Restart = "always";
        RestartSec = 2;
      };
    };

    # 4. DNS inside the vpn namespace — Mullvad's DNS server
    environment.etc."netns/vpn/resolv.conf".text = "nameserver 10.64.0.1\n";

    # 4b. WG watchdog — wg-mullvad is a oneshot, so when Mullvad's peer route
    # flaps it doesn't recover on its own (SAB sees "No route to host" until
    # the upstream heals minutes later). This pings the VPN gateway every 60s
    # inside the netns and restarts wg-mullvad on 3 consecutive failures.
    systemd.services.wg-mullvad-watchdog = {
      description = "Restart wg-mullvad when tunnel unreachable";
      after = [ "wg-mullvad.service" ];
      wants = [ "wg-mullvad.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Restart = "always";
        RestartSec = 30;
      };
      script = ''
        FAILS=0
        while true; do
          if ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iputils}/bin/ping -c1 -W3 10.64.0.1 > /dev/null 2>&1; then
            FAILS=0
          else
            FAILS=$((FAILS + 1))
            echo "wg-mullvad ping failed ($FAILS/3)"
            if [ "$FAILS" -ge 3 ]; then
              echo "wg-mullvad unreachable — restarting tunnel"
              ${pkgs.systemd}/bin/systemctl restart wg-mullvad.service
              FAILS=0
              sleep 30
            fi
          fi
          sleep 60
        done
      '';
    };

    # 5. Bind SABnzbd to the vpn namespace
    systemd.services.sabnzbd = {
      bindsTo = [ "wg-mullvad.service" ];
      after = [ "veth-vpn.service" "wg-mullvad.service" ];
      # (No PrivateNetwork override here: nixflix's sabnzbd unit never sets it,
      # so the old `PrivateNetwork = mkForce false` was overriding nothing.)
      serviceConfig = {
        NetworkNamespacePath = "/var/run/netns/vpn";
        BindReadOnlyPaths = [ "/etc/netns/vpn/resolv.conf:/etc/resolv.conf" ];
      };
    };

    # DNS inside the VPN namespace (SABnzbd's sandbox) fails due to routing
    # conflicts. Bypass it entirely for the usenet server — /etc/hosts is read
    # first (nsswitch: files before dns), so getaddrinfo() never touches DNS.
    # IPs confirmed reachable via the Mullvad tunnel on port 563.
    networking.hosts = {
      "45.125.247.68"  = [ "aunews.frugalusenet.com" ];
      "45.125.247.108" = [ "aunews.frugalusenet.com" ];
      "85.12.62.251"   = [ "news.newshosting.com" ];
    };

    # IP forwarding — required for veth NAT (SABnzbd web UI from vpn namespace)
    boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault true;

# ══════════════════════════════════════════════════════════════════════════════
# AUTOMATION — Decluttarr queue cleaner
# Polls the arr + SABnzbd APIs and removes stalled / failed-import / failed
# downloads, so the arrs blocklist and re-search instead of waiting on a dead
# job forever. Its config — API keys included — is generated from the existing
# per-service sops secrets by decluttarr-config.service (defined further down,
# next to the container) before the container starts. No separate secret, no
# first-boot steps.
# ══════════════════════════════════════════════════════════════════════════════

    systemd.services.decluttarr-config = {
      description = "Generate Decluttarr YAML config from sops secrets";
      wantedBy = [ "podman-decluttarr.service" ];
      before   = [ "podman-decluttarr.service" ];
      partOf   = [ "podman-decluttarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/decluttarr/config
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        LIDARR_KEY=$(cat ${config.sops.secrets."lidarr-api-key".path})
        SABNZBD_KEY=$(cat ${config.sops.secrets."sabnzbd-api-key".path})
        cat > /var/lib/decluttarr/config/config.yaml << EOF
instances:
  sonarr:
    - base_url: http://host.containers.internal:8989
      api_key: $SONARR_KEY
  radarr:
    - base_url: http://host.containers.internal:7878
      api_key: $RADARR_KEY
  lidarr:
    - base_url: http://host.containers.internal:8686
      api_key: $LIDARR_KEY
download_clients:
  sabnzbd:
    - name: SABnzbd
      base_url: http://host.containers.internal:8080
      api_key: $SABNZBD_KEY
jobs:
  remove_stalled: true
  remove_failed_imports: true
  remove_failed_downloads: true
  remove_metadata_missing: true
  remove_orphans: false
EOF
        chmod 600 /var/lib/decluttarr/config/config.yaml
      '';
    };

    virtualisation.oci-containers.containers.decluttarr = {
      image = "ghcr.io/manimatter/decluttarr:latest";
      volumes = [ "/var/lib/decluttarr/config:/app/config" ];
      autoStart = true;
    };

    sops.secrets."sabnzbd-api-key"              = {};
    sops.secrets."sabnzbd-nzb-key"              = {};
    sops.secrets."usenet/frugalusenet/username"    = {};
    sops.secrets."usenet/frugalusenet/password"    = {};
    sops.secrets."usenet/newshosting/username"     = {};
    sops.secrets."usenet/newshosting/password"     = {};
    sops.secrets."mullvad-wg-private-key"       = { mode = "0400"; };

  };
}
