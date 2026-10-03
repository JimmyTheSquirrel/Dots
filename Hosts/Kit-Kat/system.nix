# Kit-Kat — her machine. A separate physical box on the tailnet, NVIDIA, running a
# clone of Sisyphus's Niri/noctalia/skwd desktop.
#
# This host used to be "Elektra", a KDE boot profile on Sisyphus's own disk (same
# root UUID, same ESP, selected from the GRUB "System Select" submenu). It is now
# real hardware, which is why:
#   - Modules/grub.nix is NOT imported: it hardcodes Sisyphus's rootFsUuid and
#     emits menu entries for the three local profiles. This host is single-boot
#     and uses systemd-boot.
#   - the disks come from a disko config, not hand-written fileSystems by UUID.
#   - the rest of the hardware comes from nixos-facter, generated over SSH during
#     the install (see `apollo-deploy`).
#
# Deploy:    apollo-deploy kitkat-Kit-Kat        (first install — ERASES the disk)
# Rebuild:   system-rebuild kitkat Kit-Kat       (pushes over the tailnet)
{ self, inputs, ... }:
let
  activeUser = "kitkat";
  hostName = "Kit-Kat";

  # ✅ CONFIRMED 2026-10-02 off the machine itself, over SSH from the booted Apollo
  # stick: KINGSTON SNV3S1000G, 931.5 GB. The only other block device present was
  # the Apollo stick itself (sda, 233 GB SanDisk) — do not confuse them.
  # Everything on this device is destroyed by `apollo-deploy`.
  installDisk = "/dev/nvme0n1";

  # Disko owns the partition table. Inlined as a let-binding rather than put in
  # Hosts/Kit-Kat/disko.nix on purpose: import-tree imports EVERY .nix under
  # Hosts/, so a second .nix here would be read as a flake-parts module. That is
  # also why hardware.nix next door is a no-op stub. A .json file is safe.
  diskoConfig = {
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
  };

  # nixos-facter replaces the hand-written hardware block. It does not exist until
  # the first `apollo-deploy` generates it, so it is picked up conditionally —
  # that way this host still evaluates (and `--vm-test` still works) beforehand.
  facterReport = ./facter.json;
  haveFacter = builtins.pathExists facterReport;

  hardwareConfig = { lib, ... }: {
    imports = lib.optional haveFacter { hardware.facter.reportPath = facterReport; };

    warnings = lib.optional (!haveFacter) ''
      Hosts/Kit-Kat/facter.json is missing, so this configuration has no hardware
      report: no microcode, no detected kernel modules, no firmware. It is fine to
      `build` or `--vm-test` like this, but do NOT switch it onto real hardware.
      Generate it with: apollo-deploy kitkat-Kit-Kat
    '';
  };
in {
  flake.nixosConfigurations."${activeUser}-${hostName}" = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs activeUser; };
    modules = [
      # Hardware
      inputs.disko.nixosModules.disko
      diskoConfig
      hardwareConfig

      # Home Manager setup
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
          home.stateVersion = "26.05";
        };
      }

      # All modules (system + home config combined)
      self.nixosModules.base
      self.nixosModules.polkit
      self.nixosModules.nvidia
      self.nixosModules.grub-celeste
      self.nixosModules.plymouth
      self.nixosModules.sddm-umbrella
      self.nixosModules.hyprland
      self.nixosModules.noctalia
      self.nixosModules.skwd
      self.nixosModules.thunar
      self.nixosModules.steam
      self.nixosModules.audio
      self.nixosModules.locale
      self.nixosModules.sops-kitkat
      self.nixosModules.zsh
      self.nixosModules.starship
      self.nixosModules.kitty
      self.nixosModules.brave
      self.nixosModules.sleepy-cat
      self.nixosModules.helium
      self.nixosModules.git
      self.nixosModules.fastfetch
      self.nixosModules.btop
      self.nixosModules.vscodium
      self.nixosModules.screenshot
      self.nixosModules.navi
      self.nixosModules.spicetify
      self.nixosModules.discord
      self.nixosModules.tailscale

      # Deliberately NOT imported, and why:
      #   grub      — this machine's multi-profile loader; she uses grub-celeste
      #   sddm-nier — rock's greeter; hers is sddm-umbrella (both would collide)
      #   kde       — she's on Niri now; Modules/Desktops/kde.nix is unused
      #   skwd-wall — v1/QuickShell; conflicts with skwd (v2) by design
      #   sops      — that module is keyed to rock's hand-copied age key
      #   wolf      — Docker + a render node hardcoded to Sisyphus's RX 9060 XT
      #   sunshine  — pins output_name=HDMI-A-1 and grabs the desktop cursor
      #   rpcs3     — large, needs firmware she may never want

      # System-specific settings
      ({ config, lib, ... }: {
        networking.hostName = hostName;

        system.stateVersion = "26.05";
        # Bootloader comes from Modules/grub-celeste.nix (GRUB + the CelesteGRUB
        # theme), NOT from Modules/grub.nix — that one is this machine's multi-profile
        # loader and hardcodes Sisyphus's root UUID.

        # Plymouth's initrd GPU module. Wired here rather than in Modules/nvidia.nix
        # because the option is declared by Modules/plymouth.nix, and nvidia.nix
        # must stay importable on a host that has no plymouth.
        my.plymouth.initrdGpuModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

        # Her panels are DP-3 and DP-4 — read from /sys/class/drm over SSH while she
        # was booted from the Apollo stick (DP-1, DP-2 and both HDMI ports report
        # disconnected). `preferred` rather than a pinned mode because the refresh
        # rates were never measured; EDID picks correctly and a wrong hardcoded mode
        # is a black screen. Modules/Desktops/hyprland.nix appends a catch-all after
        # these, so an unlisted output still lights up.
        # No Millennium — that is rock's Steam ricing. She gets plain upstream
        # Steam: no CSS/JS injector, no extra openssl ABIs, no libXtst relink on
        # every launch (which is what stopped Steam starting at all here).
        # Square corners everywhere she can see them: Hyprland windows, the
        # noctalia bar, and the lockscreen widgets each have their own radius.
        # The cat greets her on every new interactive shell. `--once` rather than
        # the looping mode so opening a terminal never blocks, and guarded on an
        # interactive TTY so it cannot corrupt scp/rsync or a non-interactive ssh
        # command, which is exactly how a cute greeting breaks file transfers.
        home-manager.users.${activeUser}.programs.zsh.initContent =
          lib.mkAfter ''
            if [[ -o interactive ]] && [[ -t 1 ]]; then
              sleepy-cat --once
            fi
          '';

        my.hyprland.rounding = 0;

        # Blur and shadows off — the cheapest per-frame GPU saving on a 60 Hz
        # NVIDIA setup with a rotated output, and she wanted the plainer look.
        my.hyprland.effects = false;

        # Dark browser chrome AND dark pages, not just the frame.
        my.brave.forceDarkMode = true;

        # Google, not Brave Search. This is an enterprise policy, which means the
        # Settings dropdown locks and shows the "managed" badge — change it here,
        # not in the browser. Verify with brave://policy.
        my.brave.defaultSearchEngine = "google";

        # Sleek + Coral, instead of rock's local Text theme and its matugen
        # wallpaper pipeline. Setting `theme` also strips the two spicetify skwd
        # integrations, the matugen-colors.js extension and spotify-apply-colors
        # — see the option description in Modules/spicetify.nix.
        my.spicetify = {
          theme = "sleek";
          colorScheme = "Coral";
        };

        my.steam.millennium = false;

        # ── Her noctalia desktop ──────────────────────────────────────────────
        #
        # Captured from what she actually dialled in through the GUI. It has to be
        # here: Modules/noctalia.nix force-writes settings.toml on every rebuild,
        # so anything not recorded in Nix is silently reverted at the next switch.
        # Read back off her machine, not invented.
        my.noctalia.lockedSettingsExtra = {
          # The global corner-roundness scale (Appearance -> Interface in the GUI),
          # range 0.0-2.0. Setting it to 0 squares EVERYTHING noctalia draws in one
          # place — bar, panels, popups, lockscreen — rather than hunting down each
          # widget's own radius/capsule_radius.
          shell.corner_radius_scale = 0.0;

          # The rounded overlay noctalia paints over the four SCREEN corners
          # (Desktop -> Screen corners in the GUI). Separate from
          # corner_radius_scale above, which only scales the radii of noctalia's
          # own surfaces — this one masks the physical display edges, so it is
          # what makes "the corners of the screen look round".
          #
          # `enabled = false` rather than `size = 0`: turning it off in the GUI
          # leaves enabled = true and only drops the size, which still composites
          # a (tiny) mask every frame. rock keeps his at size 35.
          shell.screen_corners.enabled = false;

          bar.main = {
            # Bar radius explicitly 0 as well — corner_radius_scale above scales
            # radii, and 0 x anything is 0, but being explicit costs nothing.
            radius = 0;
            position = "bottom";
            background_opacity = 0.88;
            scale = 1.05;
            thickness = 32;
            margin_ends = 0;
            start = [ "workspaces" "spacer_2" "taskbar" ];
            end = [ "volume" "keybinds" "network" "bluetooth" "notifications" "tray" "clock" ];

            # The media/visualizer capsule carries its own radius, and it is a LIST
            # so recursiveUpdate replaces it wholesale rather than merging — the
            # whole entry has to be restated, not just the radius.
            capsule_group = [{
              id = "g1";
              enabled = true;
              members = [ "media" "audio_visualizer" ];
              fill = "surface_variant";
              opacity = 0.45;
              padding = 9.0;
              radius = 0;
            }];
          };

          widget = {
            audio_visualizer = { bands = 30; centered = false; scale = 1.1; width = 170; };
            clock = { capsule = false; capsule_opacity = 0.34; };
            keybinds.type = "kenn/keybind-cheatsheet:keybinds";
            network = { font_family = "42dot Sans"; show_label = false; vpn_status = "both"; };
            spacer_2 = { capsule = false; length = 104; scale = 0.4; type = "spacer"; };

            # show_all_outputs is the "show it on every monitor's bar" toggle —
            # she found this one herself in the GUI.
            # display = "none" hides the workspace NUMBERS, leaving just the pills.
            # (The other options are "id" and "name".)
            workspaces = { display = "none"; };

            taskbar = { scale = 1.35; show_all_outputs = true; };
            tray.drawer = true;
          };
        };

        my.hyprland = {
          # Real connector names, read from `hyprctl monitors` on the machine itself.
          # NOTE these differ from what nouveau reported on the installer ISO (DP-3 /
          # DP-4) — the proprietary nvidia driver enumerates them differently. Always
          # take these from the installed system, not from the live ISO.
          #   DP-3 = Dell U2421HE   (left)
          #   DP-2 = Philips 272V8  (right)
          monitors = [
            # transform,3 = 270 deg. The Dell is physically pivoted anticlockwise
            # (its top edge points left), so the output is counter-rotated to match.
            # Hyprland cannot detect a physical pivot — it always has to be told.
            "DP-3,1920x1080@60,0x0,1,transform,3"
            # Rotated, DP-3 occupies 1080 wide x 1920 tall — so the Philips starts at
            # x=1080, not 1920, or the mouse crosses an 840px dead gap. y=420 centres
            # the 1080-tall landscape panel against the 1920-tall portrait one.
            "DP-2,1920x1080@60,1080x420,1"
          ];
          primaryMonitor = "DP-2";
          secondaryMonitor = "DP-3";

          # Side monitor owns workspace 2 and starts there; 1 and 3-6 are the
          # Philips. Mod+2 therefore jumps focus to the pivoted Dell.
          secondaryWorkspace = 2;

          # Transparency dialled right back at her request — the shared default
          # (0.60 / 0.75) was far too see-through for her.
          opacityLight = "0.97";
          opacityStrong = "0.95";

          # skwd v2 has no `skwd` CLI — see the option's description.
          wallpaperCommand = "skwd-wall-v2";
        };

        # Her account. Both keys must live in ONE block: two separate
        # `users.users.${activeUser}.x = …` statements are duplicate *dynamic*
        # attribute keys, which Nix refuses to merge the way it merges static ones.
        users.users.${activeUser} = {
          # base.nix sets description = activeUser, i.e. "kitkat". This is the name
          # the SDDM greeter shows her, so give it the real spelling.
          description = "Kit Kat";

          # Her login password, from Secrets/kit-kat.yaml (NOT Secrets/secrets.yaml —
          # see Modules/sops.nix). This is what gives her a working password on the
          # very first boot; without it a fresh install has none at all.
          #
          # Because it is declarative, `passwd` will not stick across a rebuild —
          # changing her password means updating the secret.
          hashedPasswordFile = config.sops.secrets.user-password-hash.path;
        };

        # Remote deploys push store paths over SSH, and the receiving nix daemon
        # refuses paths from a user that is not trusted:
        #   error: cannot add path ... because it lacks a signature by a trusted key
        # Asgard already carries the same line for the same reason. Easy to miss
        # because the failure only appears on the FIRST push, after the install has
        # already succeeded — and at that point fixing it needs a rebuild, which is
        # the very thing that is broken. Bootstrap out by rebuilding once ON her
        # machine from a copy of this repo.
        nix.settings.trusted-users = [ activeUser ];

        # Needed for `system-rebuild kitkat Kit-Kat --target` to reach her. Your
        # pubkey arrives via Modules/base.nix.
        services.openssh = {
          enable = true;
          settings.PasswordAuthentication = false;
        };
      })
    ];
  };
}
