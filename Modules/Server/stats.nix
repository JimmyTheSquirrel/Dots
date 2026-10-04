{ ... }: {
  # ════════════════════════════════════════════════════════════════════════════
  # asgard-stats — the live numbers behind the dashboard's Asgard + Storage cards
  # ════════════════════════════════════════════════════════════════════════════
  # Glance's built-in server-stats widget showed three tiny bars (CPU, RAM, one
  # disk) refreshed on page load. This replaces it with a stream: CPU per core,
  # temperatures, fans, memory, LAN throughput, every disk + the mergerfs pool,
  # drive health, what Jellyfin is playing and what SABnzbd is downloading —
  # pushed to the page every 2 s
  # over Server-Sent Events (Resources/Asgard-Stats/asgard-stats.py, rendered by
  # Resources/Glance/stats.js).
  #
  # Two units, split by privilege:
  #   asgard-stats  DynamicUser. /proc, /sys and statvfs need nothing more.
  #   asgard-smart  root oneshot every 5 min: `smartctl -n standby` per drive
  #                 → /var/lib/asgard-smart/smart.json (world-readable). The
  #                 `-n standby` is the point: a sleeping drive is reported as
  #                 asleep, never woken to be asked its temperature.
  #
  # :9552 is reachable over tailscale0 only (trusted, Modules/Server/default.nix)
  # — deliberately absent from allowedTCPPorts, like :9555 and :9556.
  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    port = 9552;

    # The disks come from the disko layout (Hosts/Asgard/_disko.nix) — device +
    # the mountpoint of its data partition — so this can't drift from what is
    # actually mounted. Only the human labels are written here.
    labels = {
      nvme = "System · NVMe";
      hdd = "Disk 1 · 8 TB IronWolf";
      hdd2 = "Disk 2 · 12 TB WD Red Plus";
    };
    mountOf = disk:
      let
        parts = lib.attrValues (disk.content.partitions or { });
        mounts = lib.filter (m: m != null && m != "/boot")
          (map (p: p.content.mountpoint or null) parts);
      in if mounts == [ ] then null else lib.head mounts;
    disks = lib.filter (d: d.mount != null) (lib.mapAttrsToList (id: d: {
      inherit id;
      label = labels.${id} or id;
      dev = d.device;
      mount = mountOf d;
    }) config.disko.devices.disk);

    smartFile = "/var/lib/asgard-smart/smart.json";

    # One JSON object keyed by device: state (active/standby/unknown), temp °C,
    # SMART overall health, power-on hours, and whether it's solid-state (so the
    # page doesn't call the NVMe "spinning"). `-n standby,3` makes smartctl exit
    # with exactly 3 when the drive is asleep — its default (2) is also the
    # "device open failed" bit of its usual bit-mask status, so it was ambiguous.
    smartScript = pkgs.writeShellScript "asgard-smart" ''
      set -u
      out='{}'
      for dev in ${lib.escapeShellArgs (map (d: d.dev) disks)}; do
        json=$(${pkgs.smartmontools}/bin/smartctl -n standby,3 -j -H -A "$dev" 2>/dev/null) ; rc=$?
        if (( rc == 3 )); then
          entry='{"state":"standby"}'
        else
          entry=$(${pkgs.jq}/bin/jq -c '{
            state: "active",
            temp: (.temperature.current // null),
            healthy: (.smart_status.passed // null),
            hours: (.power_on_time.hours // null),
            ssd: (.device.type == "nvme" or .rotation_rate == 0)
          }' <<<"$json" 2>/dev/null || echo '{"state":"unknown"}')
        fi
        out=$(${pkgs.jq}/bin/jq -c --arg d "$dev" --argjson e "$entry" '.[$d] = $e' <<<"$out")
      done
      ${pkgs.jq}/bin/jq -c --argjson at "$(date +%s)" '. + {_at: $at}' <<<"$out" > ${smartFile}.tmp
      chmod 0644 ${smartFile}.tmp
      mv ${smartFile}.tmp ${smartFile}
    '';
  in {
    systemd.services.asgard-stats = {
      description = "Live host stats for the Asgard dashboard (SSE on :${toString port})";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "jellyfin.service" ];
      environment = {
        ASGARD_STATS_PORT = toString port;
        LAN_IFACE = config.asgard.lanInterface;
        POOL_MOUNT = "/data/media";
        SMART_FILE = smartFile;
        ASGARD_DISKS = builtins.toJSON disks;
        JELLYFIN_URL = "http://127.0.0.1:8096";
        # The socat proxy into the Mullvad namespace (downloads.nix) — the same
        # path Glance and speedtest.service use.
        SABNZBD_URL = "http://127.0.0.1:8080";
        DASH_ORIGINS = lib.concatStringsSep "," (import ./_origins.nix config.asgard);
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../../Resources/Asgard-Stats/asgard-stats.py}";
        DynamicUser = true;
        # Now Playing and Downloads; read per poll from the credentials dir, and
        # only polled while a dashboard is connected.
        LoadCredential = [
          "jellyfin-api-key:${config.sops.secrets."jellyfin-api-key".path}"
          "sabnzbd-api-key:${config.sops.secrets."sabnzbd-api-key".path}"
        ];
        Restart = "always";
        RestartSec = 5;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      };
    };

    systemd.services.asgard-smart = {
      description = "Drive health + temperature for the dashboard, without waking sleeping drives";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = smartScript;
        StateDirectory = "asgard-smart";
        StateDirectoryMode = "0755";
      };
    };
    systemd.timers.asgard-smart = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
