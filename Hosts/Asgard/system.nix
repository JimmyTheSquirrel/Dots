{ self, inputs, ... }:
let
  activeUser = "rock";
  hostName = "Asgard";

  hardwareConfig = { config, lib, modulesPath, ... }: {
    imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

    boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ "kvm-intel" ];
    boot.extraModulePackages = [ ];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };

  # Disko — declarative disk partitioning
  #   NVMe (1TB): boot + root (+ /downloads for SABnzbd temp)
  #   hdd  (8TB  ST8000VN002):  /mnt/disk1  — mergerfs branch 1, plus photos + arr state
  #   hdd2 (12TB WD122KFBX):    /mnt/disk2  — mergerfs branch 2
  #
  # The two HDDs are pooled into a single /data/media by mergerfs — see Modules/server.nix.
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
  # PAIRED with RequiresMountsFor= on every consuming service in Modules/server.nix: a missing disk
  # then means "services refuse to start and the box stays reachable" instead of "arrs re-initialise
  # on empty dirs the tmpfiles rules created on the NVMe". Never remove one without the other.
  diskoConfig = {
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
  };
in {
  flake.nixosConfigurations."${activeUser}-${hostName}" = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs activeUser; };
    modules = [
      hardwareConfig

      # Disko — declarative disk partitioning (NVMe + HDD)
      inputs.disko.nixosModules.disko
      diskoConfig

      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";
        home-manager.extraSpecialArgs = {
          inherit inputs activeUser hostName;
          pkgs-unstable = import inputs.nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        };
        home-manager.users.${activeUser} = {
          home.username = activeUser;
          home.homeDirectory = "/home/${activeUser}";
          home.stateVersion = "25.05";
        };
      }

      # Shared base modules (shell, git, fonts, nix settings, user setup)
      self.nixosModules.base
      self.nixosModules.locale
      self.nixosModules.sops
      self.nixosModules.zsh
      self.nixosModules.git
      self.nixosModules.starship
      self.nixosModules.fastfetch
      self.nixosModules.btop

      # The full media server stack
      self.nixosModules.server

      {
        networking.hostName = hostName;
        system.stateVersion = "25.05";

        # LAN advertises IPv6 (router RA) but has no working v6 upstream.
        # .NET apps (Jellyfin/arrs) try AAAA first and hang 100s per request —
        # broke TMDb metadata/poster fetching. Everything here is IPv4/Tailscale.
        networking.enableIPv6 = false;
        # enp3s0 gets SLAAC addresses from the router before the 'all' sysctl fires,
        # so the interface-specific sysctl stays 0 and the dead IPv6 address persists.
        # Set it explicitly here too.
        boot.kernel.sysctl."net.ipv6.conf.enp3s0.disable_ipv6" = true;
        # Belt-and-suspenders: tell glibc to prefer IPv4 over IPv6.
        # Default table has ::ffff:0:0/96 (IPv4-mapped) at precedence 10, below ::/0 at 40.
        # Raising it to 100 makes getaddrinfo() return IPv4 first — .NET uses this and
        # would otherwise AAAA-first → hang 100s waiting for the dead-routed v6 address.
        networking.getaddrinfo.precedence = {
          "::1/128" = 50;   # loopback — unchanged
          "::/0" = 40;      # native IPv6 — unchanged
          "2002::/16" = 30; # 6to4 — unchanged
          "::/96" = 20;     # IPv4-compat — unchanged
          "::ffff:0:0/96" = 100; # IPv4-mapped — raised above IPv6 to prefer IPv4
        };

        # Boot — systemd-boot (no GRUB on server, single system)
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;

        # Allow remote deploys from Sisyphus (nix-copy-closure needs trusted-users)
        nix.settings.trusted-users = [ "rock" ];

        # SSH for remote management
        services.openssh = {
          enable = true;
          settings.PasswordAuthentication = false;
        };

        # Passwordless sudo for server management
        security.sudo.wheelNeedsPassword = false;

        # Fallback password (change with passwd after first login)
        users.users.${activeUser}.initialPassword = "asgard";

        # /downloads on NVMe for fast SABnzbd unpacking
        systemd.tmpfiles.rules = [
          "d /downloads              0775 root  media -"
          "d /downloads/usenet       0775 root  media -"
        ];
      }
    ];
  };
}
