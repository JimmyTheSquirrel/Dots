# Disko — declarative disk partitioning
#   NVMe (1TB): boot + root (+ /downloads for SABnzbd temp)
#   hdd  (8TB  ST8000VN002):  /mnt/disk1  — mergerfs branch 1, plus photos + arr state
#   hdd2 (12TB WD122KFBX):    /mnt/disk2  — mergerfs branch 2
#
# The two HDDs are pooled into a single /data/media by mergerfs — see Modules/Server/.
# mergerfs merges the directory tree, not blocks: every file lives whole on one disk, so a
# dead drive costs only its own files. Media paths are unchanged for every service.
#
# Disks are addressed by /dev/disk/by-id/... deliberately. Adding the 12TB shuffled the letters
# (the 8TB moved sda -> sdb), which silently made the old `device = "/dev/sda"` point at the
# WRONG disk. Never use /dev/sdX here.
#
# WARNING: the disko *NixOS module* only generates fileSystems entries — it never formats.
# Formatting happens only via the separate disko script. NEVER run that script on Asgard: it
# would wipe both drives. Both partitions below already exist and were made by hand with
# matching partlabels (disk-hdd-data, disk-hdd2-data), per the Fresh Deploy Checklist.
#
# Both mounts are `nofail` DELIBERATELY. Without it, a disconnected HDD times the boot out after
# ~90s and drops to emergency mode *before networking* — the box goes completely unreachable and
# needs physical recovery (this happened on 2026-08-10). `nofail` is only safe because it is
# PAIRED with RequiresMountsFor= on every consuming service in Modules/Server/: a missing disk
# then means "services refuse to start and the box stays reachable" instead of "arrs re-initialise
# on empty dirs the tmpfiles rules created on the NVMe". Never remove one without the other.
{ inputs, ... }: {
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices = {
    disk = {
      nvme = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "fmask=0077" "dmask=0077" ];
              };
            };
            root = {
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
      # 8TB — mergerfs branch 1. Also holds /data/photos (Immich) and /data/.state (arr
      # SQLite DBs), which are bind-mounted out and deliberately kept OFF the FUSE pool.
      hdd = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST8000VN002-2ZM188_WPV3KR6R";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/disk1";
                mountOptions = [ "defaults" "nofail" ];
              };
            };
          };
        };
      };
      # 12TB — mergerfs branch 2. Formatted with `-m 0` (no root reserve): a pure data disk
      # needs none, and mergerfs `minfreespace` is the proper guard. Saves ~600GB.
      hdd2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD122KFBX-68CCHN0_WD-B01NL0DD";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/disk2";
                mountOptions = [ "defaults" "nofail" ];
              };
            };
          };
        };
      };
    };
  };
}
