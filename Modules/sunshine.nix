{ ... }: {
  flake.nixosModules.sunshine = { activeUser, pkgs, ... }: {
    # Sunshine game streaming server — starts as a user service when Niri logs in
    services.sunshine = {
      enable = true;
      autoStart = true;
      openFirewall = true;
    };

    # Larger UDP buffers for Moonlight streaming — 5G is bursty and the default
    # kernel buffers (212KB) are too small, causing drops under load.
    boot.kernel.sysctl = {
      "net.core.rmem_max"          = 26214400; # 25 MB receive buffer
      "net.core.wmem_max"          = 26214400; # 25 MB send buffer
      "net.core.netdev_max_backlog" = 5000;    # queued packets before drop
    };

    # uinput for virtual gamepad/keyboard/mouse input from client
    hardware.uinput.enable = true;

    # User needs video + input group access for display/input capture
    users.users.${activeUser}.extraGroups = [ "video" "input" ];

    # Seed sunshine.conf with 5G-optimised defaults on first run.
    # Uses HEVC (H.265) which needs ~40% less bandwidth than H.264 at the same quality.
    # Web UI changes to sunshine.conf will survive rebuilds (file only written when empty/missing).
    home-manager.users.${activeUser} = { lib, ... }: {
      home.activation.sunshineConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        CONF="$HOME/.config/sunshine/sunshine.conf"
        mkdir -p "$(dirname "$CONF")"
        if [ ! -s "$CONF" ]; then
          cat > "$CONF" <<'EOF'
# Prefer HEVC/H.265 — ~40% bandwidth saving over H.264, important for 5G.
# 0=off, 1=enabled if supported, 2=prefer HEVC, 3=force HEVC
hevc_mode = 2

# Force AMD VAAPI hardware encoder (lower latency + CPU than software)
encoder = vaapi

# Forward Error Correction — 20% overhead to recover from 5G packet loss
fec_percentage = 20
EOF
        fi
      '';
    };
  };
}
