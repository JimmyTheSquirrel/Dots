# Elektra — USB, Bluetooth and Wi-Fi coexistence fixes for her specific
# hardware. Hers only; see Hosts/Elektra/system.nix.
#
# ⚠️ Named for her machine on purpose: ./_hardware.nix is the generated facter
# report, a different thing entirely. This file is hand-written and is about
# three named devices on HER desk.
{ ... }: {
  flake.nixosModules.elektra-peripherals = { config, ... }: {
    # Keep the onboard RTL8852BU Bluetooth radio (13d3:3570) out of USB
    # autosuspend. It dropped her Razer Barracuda X's A2DP link outright
    # ("connection terminated unexpectedly") while the TH99 keyboard shared
    # the radio over BT; the keyboard now lives on its 2.4G dongle instead.
    # ⚠️ This is a BOOT parameter — a switch alone does not apply it.
    # Verify: cat /sys/module/btusb/parameters/enable_autosuspend → N
    boot.kernelParams = [ "btusb.enable_autosuspend=0" ];

    # The same pinning again on the devices themselves, which is what
    # `power/control` actually obeys and is visible at a glance:
    #   cat /sys/bus/usb/devices/1-5/power/control → on
    #
    # Plus her desk hub — two chained Genesys USB2 chips (05e3:0610) with
    # 05e3:0620 on the USB3 side. The TH99's 2.4G dongle goes deaf behind it
    # after idle: it stays enumerated, the kernel logs nothing, and only a
    # physical replug recovers it (a keyboard power-cycle does not). Hub
    # runtime suspend is the last host-side power-saving factor in that
    # path, so pin it off and the hub is ruled out if it happens again.
    #
    # Ported by hand on 2026-11-22 from her local clone's `69990c9`, which
    # was built against the pre-rename Kit-Kat host and cannot be merged —
    # see Claude/elektra-handover.md.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="13d3", ATTR{idProduct}=="3570", TEST=="power/control", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05e3", ATTR{idProduct}=="0610", TEST=="power/control", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05e3", ATTR{idProduct}=="0620", TEST=="power/control", ATTR{power/control}="on"
    '';

    # Boot with the Wi-Fi radio OFF; she turns it on from the network icon in
    # her noctalia bar when she wants it (that switch flips NM's
    # WirelessEnabled, same as `nmcli radio wifi on`).
    #
    # Why: she is on ethernet (enp5s0), so the onboard Wi-Fi (rtw89_8852be,
    # wlp4s0) sat enabled-but-disconnected and NetworkManager kept scanning —
    # and this RTL8852B combo shares ONE ANTENNA between Wi-Fi and Bluetooth.
    # Every scan's sweep of the 2.4 GHz channels starved her headset's A2DP
    # stream for 60–280 ms, which she hears as "music cutting in and out".
    # Measured on her machine 2026-11-23 with btmon alongside `iw event -T`:
    # 48 stalls >60 ms in 17.4 min with the radio on, 0 in 12.6 min with it
    # off (52,177 packets). A disconnected adapter scans far MORE than a
    # connected one, so "the Wi-Fi is unused" was never the same as "off".
    #
    # ⛔ Not `networking.networkmanager.unmanaged`, and not blacklisting
    # rtw89_8852be: both also stop the scans, but they hide the card from NM
    # so her bar's switch would do nothing. Turning Wi-Fi back on brings the
    # scanning — and the dropouts — with it. That is her call to make.
    #
    # Diagnosed and written up by the Claude session on her own machine;
    # ported from Handover/2026-11-23-wifi-scan-bt-dropouts.md.
    systemd.services.wifi-radio-off-at-boot = {
      description = "Start with the Wi-Fi radio off (Bluetooth audio coexistence)";
      after = [ "NetworkManager.service" ];
      wants = [ "NetworkManager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.networking.networkmanager.package}/bin/nmcli radio wifi off";
      };
    };
  };
}
