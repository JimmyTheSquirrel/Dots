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

    # What the Storage card's drive rows show, and what they open into. One
    # smartctl JSON report per drive → one flat object:
    #   state     active / standby / unknown
    #   temp, healthy (SMART overall), hours (power-on), ssd
    #   identity  model, family, serial, fw, capacity (bytes), rpm, form, link
    #   wear      cycles (power cycles), and for a spinning disk the attributes
    #             that predict failure — realloc (5), pending (197),
    #             uncorrectable (198), crc (199: cable, not disk), loads (193);
    #             for NVMe its health log instead (life used %, spare, data
    #             written/read, media errors, unsafe shutdowns)
    #   selftest  the newest self-test: type, result, at which power-on hour
    #   kname     the kernel's name (sda…), which /proc/diskstats is keyed by —
    #             asgard-stats runs with PrivateDevices and can't resolve the
    #             /dev/disk/by-id path itself
    #   at        when it was read
    smartJq = pkgs.writeText "asgard-smart.jq" ''
      def attr($id): ((.ata_smart_attributes.table // []) | map(select(.id == $id)) | first | .raw.value) // null;
      (.nvme_smart_health_information_log // null) as $nv
      | ((.ata_smart_self_test_log.standard.table // [])[0]) as $st
      | ((.nvme_self_test_log.table // [])[0]) as $nst
      | {
          state: "active", kname: $k, at: $at,
          temp: (.temperature.current // null),
          healthy: (.smart_status.passed // null),
          hours: (.power_on_time.hours // null),
          ssd: (.device.type == "nvme" or .rotation_rate == 0),
          model: (.model_name // null), family: (.model_family // null),
          serial: (.serial_number // null), fw: (.firmware_version // null),
          capacity: (.user_capacity.bytes // .nvme_total_capacity // null),
          rpm: (if (.rotation_rate // 0) > 0 then .rotation_rate else null end),
          form: (.form_factor.name // null),
          link: (.interface_speed.current.string // (if .device.type == "nvme" then "NVMe" else null end)),
          cycles: (.power_cycle_count // null),
          realloc: attr(5), pending: attr(197), uncorrectable: attr(198), crc: attr(199), loads: attr(193),
          nvme: (if $nv then {
            used: $nv.percentage_used, spare: $nv.available_spare,
            written: (($nv.data_units_written // 0) * 512000), read: (($nv.data_units_read // 0) * 512000),
            media_errors: $nv.media_errors, unsafe: $nv.unsafe_shutdowns, warning: $nv.critical_warning
          } else null end),
          selftest: (
            if $st then {type: $st.type.string, status: $st.status.string, passed: $st.status.passed, hours: $st.lifetime_hours}
            elif $nst then {type: ($nst.self_test_code.string // null), status: ($nst.self_test_result.string // null),
                            passed: (($nst.self_test_result.value // 1) == 0), hours: $nst.power_on_hours}
            else null end)
        }
    '';

    # `-n standby,3` makes smartctl exit with exactly 3 when the drive is
    # asleep — its default (2) is also the "device open failed" bit of its
    # usual bit-mask status, so it was ambiguous. A sleeping drive keeps
    # everything it reported when it was last awake (only state and temp
    # change), so its row can still open into its details without waking it.
    smartScript = pkgs.writeShellScript "asgard-smart" ''
      set -u
      prev=$(${pkgs.coreutils}/bin/cat ${smartFile} 2>/dev/null || echo '{}')
      out='{}'
      for dev in ${lib.escapeShellArgs (map (d: d.dev) disks)}; do
        kname=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink -f "$dev")")
        json=$(${pkgs.smartmontools}/bin/smartctl -n standby,3 -j -i -H -A -l selftest "$dev" 2>/dev/null) ; rc=$?
        if (( rc == 3 )); then
          entry=$(${pkgs.jq}/bin/jq -c --arg d "$dev" --arg k "$kname" \
            '(.[$d] // {}) + {state: "standby", temp: null, kname: $k}' <<<"$prev" 2>/dev/null \
            || echo '{"state":"standby"}')
        else
          entry=$(${pkgs.jq}/bin/jq -c --arg k "$kname" --argjson at "$(date +%s)" -f ${smartJq} <<<"$json" 2>/dev/null \
            || echo '{"state":"unknown"}')
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
