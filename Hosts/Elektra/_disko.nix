# Elektra disks. Disko owns the partition table — `apollo-deploy` runs the
# formatting script against installDisk during the first install.
# (A plain NixOS module: import-tree skips paths containing "/_".)
{ inputs, ... }:
let
  # ✅ CONFIRMED 2026-10-02 off the machine itself, over SSH from the booted Apollo
  # stick: KINGSTON SNV3S1000G, 931.5 GB. The only other block device present was
  # the Apollo stick itself (sda, 233 GB SanDisk) — do not confuse them.
  # Everything on this device is destroyed by `apollo-deploy`.
  installDisk = "/dev/nvme0n1";
in {
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices.disk.main = {
    device = installDisk;
    type = "disk";

    # Only used by disko's make-disk-image (building a raw/qcow image). It does
    # NOT size the `--vm-test` VM: disko's test harness hardcodes
    # `emptyDiskImages = 4096` MiB per disk (lib/tests.nix) with no option to
    # change it, which is why a layout with a 16 G swap partition can never be
    # VM-tested. See Claude/deploy.md.
    imageSize = "32G";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };
        # 32G, to match her 31.3 GB of RAM — hibernate writes the whole of RAM
        # here, so anything smaller makes resumeDevice a lie. Measured off the
        # machine itself; the earlier 16G was a guess made before we could see it.
        # Costs 3% of a 931 GB disk.
        swap = {
          priority = 2;
          size = "32G";
          content = {
            type = "swap";
            resumeDevice = true;
          };
        };
        root = {
          priority = 3;
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
