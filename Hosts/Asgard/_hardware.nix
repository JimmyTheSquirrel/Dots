# Asgard hardware — a plain NixOS module, imported by ./system.nix.
# (import-tree skips paths containing "/_", so this is not a flake-parts module.)
{ config, lib, pkgs, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];

  # ── Fan/voltage monitoring — Gigabyte B760M H DDR4, ITE IT8689E at 0xa40 ──────
  #
  # Without this the box reports ZERO fans: hwmon shows only temperatures (nvme,
  # coretemp, gigabyte_wmi, jc42 DIMMs, acpitz) and not one fan*_input or pwm*
  # entry — not even the CPU fan. Two separate things block it, and BOTH must be
  # handled or you get a silent no-op:
  #
  #   1. The IN-TREE it87 does not support the IT8689E. It fails "No such device"
  #      even when the resource conflict below is bypassed — verified directly, so
  #      the ACPI workaround ALONE is not enough. Only the out-of-tree driver works:
  #        it87: Found IT8689E chip at 0xa40, revision 2
  #
  #   2. ACPI claims the chip's I/O region (/proc/ioports: 0a40-0a4f : pnp 00:00),
  #      so even the working driver is refused with "Device or resource busy".
  #      `ignore_resource_conflict=1` bypasses it for THIS DRIVER ONLY — deliberately
  #      preferred over the global acpi_enforce_resources=lax kernel param, which
  #      relaxes the same protection for every driver on the system and needs a reboot.
  #
  # Why insmod-by-path instead of boot.kernelModules: extraModulePackages leaves BOTH
  # copies in the merged module tree, and depmod registers only the in-tree one —
  #   modules.dep:  kernel/drivers/hwmon/it87.ko.xz   (in-tree, broken here)
  #   also present: kernel/drivers/hwmon/it87.ko      (out-of-tree, works)
  # so `modprobe it87` resolves to the driver that cannot see this chip. insmod takes
  # an explicit path and bypasses that resolution entirely. Blacklisting keeps anything
  # else from autoloading the in-tree one first and squatting on the module name
  # (blacklist affects modprobe only — it does not block the insmod below).
  #
  # MONITORING ONLY. BIOS Smart Fan 6 still drives the curves (pwm*_enable=2 = auto).
  # Do NOT also enable `fancontrol` — two controllers fighting over the same PWM
  # registers makes the fans oscillate.
  #
  # Covers the motherboard headers only. The Jonsbo N5 drive-cage fans hang off the
  # case backplane on raw 12V from a Molex power port — no PWM wire, no tach wire —
  # so no driver can ever see or control them. They must be moved onto a SYS_FAN
  # header (fan3 is free) to be controllable at all.
  boot.extraModulePackages = [ config.boot.kernelPackages.it87 ];
  boot.blacklistedKernelModules = [ "it87" ];

  systemd.services.it87 = {
    description = "Load out-of-tree it87 hwmon driver (ITE IT8689E)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = [
        # insmod does NOT resolve dependencies (that is modprobe's job), and it87
        # needs hwmon_vid. Without this the unit dies "Unknown symbol in module" —
        # but ONLY on a cold boot: after a nixos-rebuild switch hwmon_vid is already
        # resident, so the failure hides until the machine actually reboots.
        "${pkgs.kmod}/bin/modprobe hwmon_vid"
        # Drop any already-loaded copy, so a restart (or a hand-loaded module left
        # over from debugging) does not fail the unit with "File exists".
        "-${pkgs.kmod}/bin/rmmod it87"
      ];
      ExecStart = "${pkgs.kmod}/bin/insmod ${config.boot.kernelPackages.it87}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/kernel/drivers/hwmon/it87.ko ignore_resource_conflict=1";
      ExecStop = "${pkgs.kmod}/bin/rmmod it87";
    };
  };

  environment.systemPackages = with pkgs; [
    lm_sensors    # `sensors` — fan RPM + temps
    smartmontools # `smartctl` — per-drive temperature, the metric a fan curve should track
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
