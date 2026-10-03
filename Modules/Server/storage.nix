{ ... }: {
  # Asgard — storage: the mergerfs media pool, the bind mounts that keep SQLite
  # off FUSE, the fail-closed RequiresMountsFor guards, and every data directory.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  {

    # ══════════════════════════════════════════════════════════════════════════
    # Storage pool — mergerfs unites the 8TB + 12TB into one /data/media
    # ══════════════════════════════════════════════════════════════════════════
    #
    #   /mnt/disk1   8TB  ext4   ─┐
    #                             ├─ mergerfs ──> /data/media
    #   /mnt/disk2   12TB ext4   ─┘
    #
    #   /data/photos  <- bind /mnt/disk1/photos   (Immich)
    #   /data/.state  <- bind /mnt/disk1/.state   (arr SQLite DBs)
    #
    # mergerfs is a UNION filesystem: it merges the directory tree, not blocks. Every file lives
    # whole on exactly one disk, and the pool is a single namespace so each file appears exactly
    # once. Losing a drive costs only that drive's files — the survivor keeps serving. This is
    # why mergerfs and NOT LVM/btrfs-single/RAID0, which span one filesystem across both spindles
    # and lose everything if either disk dies.
    #
    # Only MEDIA is pooled. The arr databases (/data/.state) and Immich's library (/data/photos)
    # stay on real ext4 via bind mounts — SQLite on FUSE is a known source of locking corruption,
    # and those two are only ~3.8G combined, so there is no capacity reason to pool them.
    #
    # Every service path is unchanged by this: nixflix mediaDir/stateDir, the container bind
    # mounts, immich mediaLocation and the tmpfiles rules below all still point at /data/...
    #
    # NOTE: /mnt/disk2/media must exist before the pool can mount — mergerfs errors on a missing
    # branch, and tmpfiles runs too late to help. It was created by hand at install time.
    # (pkgs.mergerfs is added to environment.systemPackages in default.nix, next to kitty.terminfo)
    programs.fuse.userAllowOther = true;  # required for allow_other

    fileSystems."/data/media" = {
      device = "/mnt/disk1/media:/mnt/disk2/media";
      fsType = "fuse.mergerfs";
      options = [
        "category.create=mfs"   # new files -> branch with most free space (the 12TB)
        "moveonenospc=true"     # branch fills mid-write -> relocate rather than ENOSPC
        "minfreespace=50G"      # stop choosing a branch below this
        "cache.files=partial"
        "dropcacheonclose=true"
        "allow_other"           # podman containers + non-root services must read it
        "fsname=mediapool"
        "nofail"
        "x-systemd.requires-mounts-for=/mnt/disk1"
        "x-systemd.requires-mounts-for=/mnt/disk2"
      ];
    };

    fileSystems."/data/photos" = {
      device = "/mnt/disk1/photos";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.requires-mounts-for=/mnt/disk1" ];
    };

    fileSystems."/data/.state" = {
      device = "/mnt/disk1/.state";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.requires-mounts-for=/mnt/disk1" ];
    };

    # Hard mount dependencies — SAFETY CRITICAL.
    # If the pool fails to mount, /data/media is an empty directory on the NVMe. Services must
    # refuse to start rather than run against an empty library: Jellyfin would blank the library,
    # and the *-missing-search units would trigger a mass re-download of the entire collection.
    # RequiresMountsFor makes each unit fail closed instead.
    # These HAD to be dotted paths while everything lived in one server.nix: Nix merges dotted
    # paths into attrset *literals* only, so a computed `systemd.services = lib.genAttrs ...`
    # collided with the many `systemd.services.<name> = { ... }` definitions beside it. This file
    # defines no other services, so genAttrs would work now — the explicit list is kept because
    # each line can carry its own why.
    systemd.services.sonarr.unitConfig.RequiresMountsFor              = [ "/data/media" "/data/.state" ];
    systemd.services.radarr.unitConfig.RequiresMountsFor              = [ "/data/media" "/data/.state" ];
    systemd.services.lidarr.unitConfig.RequiresMountsFor              = [ "/data/media" "/data/.state" ];
    systemd.services.jellyfin.unitConfig.RequiresMountsFor            = [ "/data/media" "/data/.state" ];
    systemd.services.sonarr-rootfolders.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.radarr-rootfolders.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.lidarr-rootfolders.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.jellyfin-libraries.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.podman-audiobookshelf.unitConfig.RequiresMountsFor = [ "/data/media" ];
    systemd.services.podman-shelfarr.unitConfig.RequiresMountsFor     = [ "/data/media" ];
    # Without this, a boot with the pool missing would have Suwayomi happily
    # re-download its whole library onto the NVMe root — the same failure mode
    # sonarr-missing-search is guarded against.
    systemd.services.suwayomi-server.unitConfig.RequiresMountsFor     = [ "/data/media" ];
    systemd.services.podman-filebrowser.unitConfig.RequiresMountsFor  = [ "/data/media" "/data/photos" ];
    systemd.services.immich-server.unitConfig.RequiresMountsFor       = [ "/data/photos" ];

    # --- Data directories ---
    systemd.tmpfiles.rules = [
      "d /data                      0755 root  root  -"
      "d /data/media                0775 root  media -"
      "d /data/media/tv             0775 root  media -"
      "d /data/media/movies         0775 root  media -"
      "d /data/media/music          0775 root  media -"
      # books + audiobooks are 0777 where every sibling is 0775 because the book
      # containers used to run as PGID 1001, a group that does not exist here
      # (see "Shared media group" in default.nix), so group-write was no use to them. PGID is
      # now the real media gid — but files already written under 1001 keep that
      # group, so these stay 0777 until those are chgrp'd to media by hand.
      "d /data/media/books          0777 root  media -"
      "d /data/media/manga          0775 root  media -"
      # /downloads is on the NVMe root, for fast SABnzbd unpacking.
      "d /downloads                 0775 root  media -"
      "d /downloads/usenet          0775 root  media -"
      "d /data/photos               0775 root  media -"
      "d /data/.state/services      0775 root  media -"
      "d /data/media/audiobooks               0777 root  media -"
      # Container state dirs
      "d /var/lib/audiobookshelf             0775 root  media -"
      "d /var/lib/audiobookshelf/config      0775 root  media -"
      "d /var/lib/audiobookshelf/metadata    0775 root  media -"
      # ⚠️ Must be owned by the container's PUID/PGID (1000/media), NOT root.
      # Shelfarr's Rails app drops to uid 1000, and its SQLite DBs run in WAL
      # mode — so on every write it may need to CREATE `-wal`/`-shm` files in
      # this directory. With the directory root-owned the existing DB files are
      # still writable (they're owned by rock), so it looks fine, and then any
      # clean shutdown checkpoints the WAL away and the app can never recreate
      # it. Presents as `SQLite3::ReadOnlyException: attempt to write a readonly
      # database` and a hard 500 on EVERY login, because solid_cache writes on
      # the session path. The gid is read from the media group, exactly like the
      # container's PGID, so the two cannot drift apart again (they were both a
      # literal 1001 — a gid with no group behind it).
      "d /var/lib/shelfarr                   0755 1000  ${toString config.users.groups.media.gid}  -"

      "d /var/lib/filebrowser       0775 root  media -"
      "d /var/lib/decluttarr        0755 root  root  -"
      "d /var/lib/decluttarr/config 0755 root  root  -"
      "d /var/lib/recyclarr              0700 root  root  -"
    ];

  };
}
