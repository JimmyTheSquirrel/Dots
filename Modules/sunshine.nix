{ ... }: {
  flake.nixosModules.sunshine = { activeUser, pkgs, ... }: {
    # Sunshine game streaming server — user service, kept as a FALLBACK only.
    #
    # ⚠️ autoStart false since 2026-09-28. Wolf (Modules/wolf.nix) is now the
    # streaming host and auto-starts instead; the two cannot coexist because
    # they bind the same Moonlight ports. These two autoStart settings are a
    # matched pair — never set both true.
    #
    # Turning this off is a win on its own, independent of Wolf: Sunshine
    # creates a virtual "Mouse passthrough (absolute)" uinput device for its
    # entire lifetime, not just while streaming, and it pins the DESKTOP cursor
    # to the captured output's coordinate space. Presents as "my mouse is stuck
    # on the top monitor". Restarting Sunshine does not clear it (the devices
    # are recreated at startup) — only stopping it does. Leaving it running
    # idle at every login cost us the desktop pointer for nothing.
    #
    # To use it again: stop Wolf first, then `systemctl --user start sunshine`.
    # NOTE it is a USER unit — never `sudo systemctl stop sunshine`.
    services.sunshine = {
      enable = true;
      autoStart = false;
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

    # User needs video + input group access for display/input capture, and
    # uinput to *inject* the client's gamepad/keyboard/mouse events —
    # /dev/uinput is root:uinput 0660, so without the group Sunshine opens it
    # read-only and controller input silently stops working on the stream.
    users.users.${activeUser}.extraGroups = [ "video" "input" "uinput" ];

    # Seed sunshine.conf with optimised defaults on first run.
    # Uses HEVC (hevc_mode=2) since 2026-09-27 — see the long note below. The old
    # green-bar artifact that forced H.264 did NOT reproduce on the RX 9060 XT.
    # Web UI changes to sunshine.conf survive rebuilds (file only written when empty/missing),
    # EXCEPT hevc_mode, output_name and capture, which are always patched back to prevent
    # known regressions (wrong monitor, boot-time portal dialog).
    home-manager.users.${activeUser} = { lib, ... }: {
      home.activation.sunshineConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        CONF="$HOME/.config/sunshine/sunshine.conf"
        mkdir -p "$(dirname "$CONF")"
        if [ ! -s "$CONF" ]; then
          cat > "$CONF" <<'EOF'
# HEVC — the RIGHT codec for the Eclipse Pi 5 client. Changed 1 -> 2 on 2026-09-27.
# 0=auto (advertise whatever the encoder supports), 1=do NOT advertise HEVC,
# 2=advertise HEVC Main, 3=advertise HEVC Main+Main10.
#
# Why this matters so much: the Pi 5 has NO H.264 hardware decoder (its single
# decode block is HEVC-only, /dev/video19). Forcing H.264 meant Eclipse decoded
# every frame in SOFTWARE. Measured on a live 1080p60 stream:
#
#            H.264 (software)      HEVC (hardware)
#   CPU          54.5%                 20.0%
#   bitrate      15 Mbps               23 Mbps
#
# i.e. 2.7x less CPU while carrying 50% MORE bitrate, and HEVC is ~30-50% more
# efficient per bit on top of that. Client log confirms the hardware path:
#   "Hwaccel V4L2 HEVC stateless V4; devices: /dev/media0,/dev/video19"
#
# ⚠️ This was previously pinned to 1 because hevc_vaapi produced a green bar at
# the bottom of the stream. That was an OLDER Sunshine on a DIFFERENT GPU —
# retested 2026-09-27 on the RX 9060 XT with Sunshine 2026.516 and the artifact
# is GONE (user confirmed on the TV). If a green bar ever returns, set this back
# to 1; that is the only value which truly forces H.264 (0 is *auto*, not "off",
# and any client asking for HEVC — like Eclipse — will get it).
#
# NOT 3 (Main10): Eclipse cannot output HDR at all (see Claude/eclipse.md), so
# 10-bit buys nothing here and only adds decode cost.
# NOT AV1: this GPU advertises av1_vaapi, but the Pi 5 has no AV1 hardware
# decoder, so AV1 would land straight back in software. HEVC is the target.
hevc_mode = 2

# Force AMD VAAPI hardware encoder (lower latency + CPU than software)
encoder = vaapi

# Forward Error Correction — 20% overhead to recover from 5G packet loss
fec_percentage = 20

# Stream HDMI-A-1 (1920x1080), not DP-2 (2560x1080 ultrawide).
# Use the CONNECTOR NAME, not the numeric index. With `output_name = 1` the
# startup/encoder-probe paths do honour the index and log HDMI-A-1, but the actual
# capture initialiser (the selection made right after CLIENT CONNECTED) ignores it
# and falls back to monitor 0 — so the stream silently showed the ultrawide desktop
# while the logs looked correct. The connector name is honoured by both paths.
# Verify after any change: the "Selected monitor" line AFTER "CLIENT CONNECTED".
output_name = HDMI-A-1

# Force the wlroots (zwlr_screencopy) capture backend. Left on auto, Sunshine also
# probes the XDG Portal backend at every startup, which pops a "Share Screen" dialog
# on the desktop each boot. Niri implements zwlr_screencopy_manager_v1, so wlgrab is
# what actually streams anyway — pinning it skips the portal probe entirely.
capture = wlr
EOF
        else
          # Re-apply the values that must not drift, even on existing configs.
          enforce() {
            if grep -q "^$1" "$CONF"; then
              sed -i "s/^$1\s*=.*/$1 = $2/" "$CONF"
            else
              echo "$1 = $2" >> "$CONF"
            fi
          }
          enforce hevc_mode 2           # 2 = advertise HEVC Main — Pi 5 hw-decodes it; H.264 would be SOFTWARE
          enforce output_name HDMI-A-1  # connector name — numeric index is ignored by the capture path
          enforce capture wlr           # skip the XDG Portal probe (share-screen dialog on boot)
        fi
      '';
    };
  };
}
