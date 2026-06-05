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

    # Seed sunshine.conf with optimised defaults on first run.
    # Uses H.264 (hevc_mode=0) — H.265 via VAAPI causes a green bar artifact at the
    # bottom of the stream due to AMD VAAPI HEVC alignment requirements. H.264 is clean.
    # Web UI changes to sunshine.conf survive rebuilds (file only written when empty/missing),
    # EXCEPT hevc_mode which is always patched to 0 to prevent the green bar regression.
    home-manager.users.${activeUser} = { lib, ... }: {
      home.activation.sunshineConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        CONF="$HOME/.config/sunshine/sunshine.conf"
        mkdir -p "$(dirname "$CONF")"
        if [ ! -s "$CONF" ]; then
          cat > "$CONF" <<'EOF'
# H.264 only — H.265/VAAPI causes green bar artifact on the stream (alignment issue).
# 0=off, 1=enabled if supported, 2=prefer HEVC, 3=force HEVC
hevc_mode = 0

# Force AMD VAAPI hardware encoder (lower latency + CPU than software)
encoder = vaapi

# Forward Error Correction — 20% overhead to recover from 5G packet loss
fec_percentage = 20

# Monitor index 1 = HDMI-A-1 (1920x1080). Index 0 = DP-2 (2560x1080 ultrawide).
# On Wayland, output_name must be a numeric index, not the connector name.
output_name = 1
EOF
        else
          # Always enforce hevc_mode=0 to prevent green bar, even on existing configs.
          if grep -q "^hevc_mode" "$CONF"; then
            sed -i 's/^hevc_mode\s*=.*/hevc_mode = 0/' "$CONF"
          else
            echo "hevc_mode = 0" >> "$CONF"
          fi
          # Always enforce output_name to keep streaming the 1080p HDMI monitor.
          if grep -q "^output_name" "$CONF"; then
            sed -i 's/^output_name\s*=.*/output_name = 1/' "$CONF"
          else
            echo "output_name = 1" >> "$CONF"
          fi
        fi
      '';
    };
  };
}
