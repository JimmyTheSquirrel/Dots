{ ... }: {
  # Asgard — networking: Tailscale (+ the status proxy behind Glance's Yggdrasil
  # widget), the Ookla speed test and network panel, the Cloudflare tunnel, and
  # WAN egress shaping.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    inherit (config.asgard) lanInterface;
  in
  {

# ══════════════════════════════════════════════════════════════════════════════
# NETWORKING — Tailscale VPN + Cloudflare Tunnel
# Native NixOS services (not containers).
#
# Tailscale joins the tailnet by itself on first boot (authKeyFile below).
#
# Cloudflare tunnel setup (one-time before first build — already done for the
# tunnel below; only needed again for a NEW tunnel):
#   1. dash.cloudflare.com → Zero Trust → Networks → Tunnels → Create tunnel
#   2. Name it "asgard", copy the Tunnel UUID shown on the detail page
#   3. Download/copy the credentials JSON shown during creation
#   4. sops ~/Dots/Secrets/secrets.yaml
#        cloudflare-tunnel: '<full credentials JSON>'
#   5. Use that UUID as the key under services.cloudflared.tunnels
#
# Public URLs (bifrost-vault.com):
#   jellyfin.bifrost-vault.com  → localhost:8096
#   requests.bifrost-vault.com  → localhost:5055
#   photos.bifrost-vault.com    → localhost:2283
# ══════════════════════════════════════════════════════════════════════════════

    # --- Tailscale ---
    # authKeyFile replaces the old "run `sudo tailscale up` after first boot"
    # step: the module's tailscaled-autoconnect unit sends the key only while
    # the node is logged out (NeedsLogin / NeedsMachineAuth / Stopped), so on
    # an already-joined box it just reports "running" and exits. Same sops key
    # the marsbar node joins with (declared in Modules/Core/sops.nix).
    services.tailscale = {
      enable = true;
      openFirewall = true;
      authKeyFile = config.sops.secrets.tailscale-auth-key.path;
    };

    # Tailscale status API proxy — exposes node status for Glance dashboard
    # Queries tailscaled Unix socket and serves JSON on localhost:9553
    systemd.services.tailscale-status-proxy = {
      description = "Tailscale status HTTP proxy for Glance";
      after = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.curl pkgs.jq pkgs.python3 ];
      script = ''
        python3 -c '
import http.server, subprocess, json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            raw = subprocess.check_output([
                "curl", "-sf", "--unix-socket",
                "/var/run/tailscale/tailscaled.sock",
                "http://local-tailscaled.sock/localapi/v0/status"
            ])
            data = json.loads(raw)
            result = {
                "self": {
                    "name": data["Self"]["HostName"],
                    "ip": data["Self"]["TailscaleIPs"][0],
                    "online": data["Self"]["Online"]
                },
                "peers": [
                    {
                        "name": p["HostName"],
                        "ip": p["TailscaleIPs"][0] if p.get("TailscaleIPs") else "",
                        "online": p.get("Online", False)
                    }
                    for p in data.get("Peer", {}).values()
                ]
            }
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(result).encode())
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())
    def log_message(self, *args):
        pass

http.server.HTTPServer(("127.0.0.1", 9553), Handler).serve_forever()
        '
      '';
      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
      };
    };

    # ── Internet speed test ─────────────────────────────────────────────────────
    # Ookla's official CLI, not speedtest-cli/librespeed — it is the number the
    # ISP will actually argue about, and it needs no server-list curation.
    #
    # Reading the result: DOWNLOAD is the honest line rate. UPLOAD is not — every
    # WAN-bound packet goes through the 30 Mbit htb class in wan-egress-shaping
    # below, so this reports ~30 on a 50 Mbit uplink **by design**. The widget
    # says so next to the figure; don't go hunting for a broken uplink.
    #
    # The download figure is only honest because the run pauses SABnzbd first
    # (see the script). Ookla measures whatever capacity is spare, so before that
    # was added the timer happily fired mid-download and published the leftovers:
    # 47.8 Mb/s against 421 on the same link twenty seconds later.
    systemd.services.speedtest = {
      description = "Internet speed test (Ookla) → /var/lib/speedtest/latest.json";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        # Not optional. The CLI does std::string(getenv("HOME")) unguarded, so
        # with no HOME it aborts on `basic_string::_M_construct null not valid`
        # and dumps core before it ever touches the network. It keeps its
        # license-acceptance flag under $HOME/.config/ookla.
        HOME = "/var/lib/speedtest";
      };
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "speedtest";
        # A test takes ~30s, plus 11s of settling before it; a hung one must not
        # wedge the timer forever.
        TimeoutStartSec = "5m";
        # The queue is resumed here rather than at the end of the script so it
        # happens on *any* stop — including the unit being killed on
        # TimeoutStartSec, which is exactly the case where a script-level trap
        # would be least reliable. The marker is what authorises the resume, so a
        # queue that was already paused by hand is never silently restarted.
        ExecStopPost = pkgs.writeShellScript "speedtest-resume-sab" ''
          [ -e /var/lib/speedtest/.sab-paused ] || exit 0
          ${pkgs.coreutils}/bin/rm -f /var/lib/speedtest/.sab-paused
          key=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."sabnzbd-api-key".path})
          ${pkgs.curl}/bin/curl -fsS --max-time 10 \
            "http://localhost:8080/api?apikey=$key&output=json&mode=resume" >/dev/null
        '';
      };
      # Written to a temp file and renamed, so a failed or half-written run never
      # replaces a good result — the panel keeps showing the last known-good one.
      script = ''
        out=/var/lib/speedtest/latest.json
        tmp=$(${pkgs.coreutils}/bin/mktemp /var/lib/speedtest/.latest.XXXXXX)
        raw=$(${pkgs.coreutils}/bin/mktemp /var/lib/speedtest/.raw.XXXXXX)

        # Ookla measures spare capacity, not link capacity, so the line has to be
        # quiet or the result is meaningless — SABnzbd alone will happily sit on
        # 245 Mb/s of a 425 Mb/s link and drag the figure down to a fifth of it.
        #
        # set_pause is a pause with a deadline: if this unit dies hard enough
        # that ExecStopPost never runs, SAB resumes by itself after 6 minutes
        # (one past TimeoutStartSec), so a failure here can never strand the
        # queue. Every step fails open — no key, no SAB, no answer, no pause, and
        # the test still runs.
        #
        # The marker is deliberately not cleared here. One left behind means a
        # previous run was killed before ExecStopPost, so letting it survive into
        # this run is what gets the queue resumed at the end of it.
        key=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."sabnzbd-api-key".path} || true)
        sab="http://localhost:8080/api?apikey=$key&output=json"
        if ${pkgs.curl}/bin/curl -fsS --max-time 10 "$sab&mode=queue" \
             | ${pkgs.gnugrep}/bin/grep -q '"paused":false'; then
          if ${pkgs.curl}/bin/curl -fsS --max-time 10 \
               "$sab&mode=config&name=set_pause&value=6" >/dev/null; then
            ${pkgs.coreutils}/bin/touch /var/lib/speedtest/.sab-paused
          fi
        fi

        # Let the in-flight NNTP connections drain, then log what is *still* on
        # the wire. SAB is the only thing this unit can pause; if a Jellyfin
        # stream or an arr import is running, the figures below are leftovers
        # again and this line is the only way to tell after the fact.
        ${pkgs.coreutils}/bin/sleep 8
        rx1=$(${pkgs.coreutils}/bin/cat /sys/class/net/${lanInterface}/statistics/rx_bytes)
        ${pkgs.coreutils}/bin/sleep 3
        rx2=$(${pkgs.coreutils}/bin/cat /sys/class/net/${lanInterface}/statistics/rx_bytes)
        echo "background traffic at test start: $(( (rx2 - rx1) * 8 / 3 / 1000000 )) Mb/s down"

        if ${lib.getExe pkgs.ookla-speedtest} \
             --format=json --accept-license --accept-gdpr > "$raw"; then
          # On the first run of a fresh machine the EULA goes to stdout *ahead*
          # of the JSON, so this takes the result line rather than the whole
          # stream — otherwise latest.json is a licence notice.
          ${pkgs.gnugrep}/bin/grep -m1 '^{' "$raw" > "$tmp" || true
        fi

        if [ -s "$tmp" ]; then
          ${pkgs.coreutils}/bin/mv "$tmp" "$out"
          ${pkgs.coreutils}/bin/rm -f "$raw"
        else
          ${pkgs.coreutils}/bin/rm -f "$tmp" "$raw"
          exit 1
        fi
      '';
    };

    systemd.timers.speedtest = {
      description = "Run an internet speed test every 6 hours";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00/6:05:00";
        # Catch up after downtime, so the panel is never showing a result from
        # before the last reboot with no explanation.
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };

    # ── Network panel endpoint (port 9555, Tailscale-only) ─────────────────────
    # Backs the Network group on the Glance main page: live throughput sampled
    # from /proc/net/dev plus the last speed-test result, and a POST /run that
    # triggers a fresh test from the "Run now" button.
    #
    # Replaced `flow` inside a second read-only ttyd on :7682. ttyd kills its
    # child whenever the websocket drops — a backgrounded tab was enough — and
    # xterm.js then painted its reconnect banner over the panel, which is what it
    # spent most of its life showing. See Resources/Network-Panel/network-panel.py.
    #
    # Runs as root purely so POST /run can `systemctl start speedtest.service`.
    # It is not exposed beyond the tailnet: 9555 is deliberately absent from
    # allowedTCPPorts and only reachable via trusted tailscale0.
    systemd.services.network-panel = {
      description = "Network throughput + speed test endpoint for Glance";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.systemd ];
      environment = {
        NETPANEL_IFACE = lanInterface;
        NETPANEL_PORT = "9555";
        # The dashboards allowed to call it cross-origin (comma-separated) —
        # the main Glance polls /api and POSTs /run from the browser. Same list
        # as ha-bridge and eclipse-control: Modules/Server/_origins.nix.
        DASH_ORIGINS = lib.concatStringsSep "," (import ./_origins.nix config.asgard);
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../../Resources/Network-Panel/network-panel.py}";
        Restart = "always";
        RestartSec = 5;
      };
    };

    services.cloudflared = {
      enable = true;
      tunnels = {
        "804d54a8-e7ad-4f34-812d-3052cf862c47" = {
          credentialsFile = config.sops.secrets."cloudflare-tunnel".path;
          default = "http_status:404";
          ingress = {
            "jellyfin.bifrost-vault.com"  = "http://localhost:8096";
            "requests.bifrost-vault.com"  = "http://localhost:5055";
            "photos.bifrost-vault.com"    = "http://localhost:2283";
          };
        };
      };
    };

    # --- WAN egress shaping ---
    # Jellyfin's transcoder delivers segments in on/off bursts that momentarily
    # saturate the full 50 Mbit uplink (~180ms latency spikes every ~3s, which
    # rubber-bands game sessions on the LAN). Cap WAN-bound traffic at 30 Mbit
    # so it flows smoothly below line rate; LAN/tailnet destinations (RFC1918)
    # bypass the cap so local direct-play of high-bitrate remuxes is unaffected.
    systemd.services.wan-egress-shaping = {
      description = "Cap WAN-bound upload at 30 Mbit (smooth Jellyfin transcode bursts)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        tc=${pkgs.iproute2}/bin/tc
        dev=${lanInterface}
        # htb doesn't support in-place change, so "replace" fails on an existing
        # root — tear down and rebuild from scratch (also clears classes/filters)
        $tc qdisc del dev $dev root 2>/dev/null || true
        $tc qdisc add dev $dev root handle 1: htb default 20
        $tc class add dev $dev parent 1: classid 1:1 htb rate 940mbit
        $tc class add dev $dev parent 1:1 classid 1:10 htb rate 910mbit ceil 940mbit
        # burst/cburst explicit — htb's auto-computed default at this rate is
        # ~1600 bytes (one packet), which sounds harmless but isn't: it means
        # every burst above a single packet gets throttled by the token
        # bucket itself, not just rate-limited on average. Discovered
        # 2026-09-11 chasing Eclipse's remote Jellyfin playback "plays a
        # chunk, stalls, plays a chunk" stutter — `tc -s class show` had 190M
        # cumulative overlimits and a token count sitting in permanent
        # deficit. 300KB (~80ms at 30 Mbit) lets Kodi's aggressive read-ahead
        # bursts (filecache readfactor 20x, see Claude/eclipse.md) through
        # smoothly while the long-run average is still capped at 30 Mbit.
        $tc class add dev $dev parent 1:1 classid 1:20 htb rate 30mbit ceil 30mbit burst 300k cburst 300k
        $tc qdisc add dev $dev parent 1:20 fq_codel
        $tc filter add dev $dev parent 1: protocol ip prio 1 u32 match ip dst 192.168.0.0/16 flowid 1:10
        $tc filter add dev $dev parent 1: protocol ip prio 1 u32 match ip dst 10.0.0.0/8 flowid 1:10
        $tc filter add dev $dev parent 1: protocol ip prio 1 u32 match ip dst 172.16.0.0/12 flowid 1:10
      '';
    };

    sops.secrets."cloudflare-tunnel"        = {};

  };
}
