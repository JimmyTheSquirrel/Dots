# Apollo — the deployer / rescue ISO.
#
# One ISO with two jobs:
#   1. A full Niri rescue desktop (gparted, claude-code, a browser) for fixing a
#      machine by hand.
#   2. A headless deployment target. It joins the tailnet by itself at boot, then
#      waits. Everything after that is initiated from Sisyphus:
#        apollo-connect                     -> a shell on the stick
#        apollo-deploy <attr> <target>      -> nixos-anywhere installs that host
#
# It never reaches out to Sisyphus and never deploys anything on its own.
#
# Why nixos-anywhere works against this ISO over the tailnet: nixos-anywhere looks
# for VARIANT_ID=installer in /etc/os-release and, when it finds it, SKIPS the
# kexec phase. Nothing re-boots mid-install, so the SSH session (and the tailnet
# link carrying it) survives from start to finish.
#
# Build + copy to the Ventoy stick:  apollo-iso
# Put the tailnet key on the stick:  apollo-key
{ self, inputs, ... }:
let
  # The tailnet node name. On the tailnet it shows up as the stick it lives on,
  # which is what you type: `ssh rock@apollo`.
  tailnetName = "apollo";
in {
  flake.nixosConfigurations.rock-Apollo = self.lib.mkHost {
    activeUser = "rock";
    hostName = "Apollo";
    stateVersion = "25.05";

    modules = [
      # ISO base
      "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

      # Your actual modules — keybinds, shell, browser, all work
      self.nixosModules.niri
      self.nixosModules.noctalia
      self.nixosModules.helium
      self.nixosModules.audio
      self.nixosModules.locale
      self.nixosModules.zsh
      self.nixosModules.starship
      self.nixosModules.kitty
      self.nixosModules.git
      self.nixosModules.fastfetch
      self.nixosModules.btop
      self.nixosModules.polkit
      self.nixosModules.tailscale

      # Apollo-specific overrides
      ({ pkgs, lib, activeUser, ... }: {
        networking.hostName = tailnetName;
        nixpkgs.config.allowUnfree = true;
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
        networking.networkmanager.enable = true;

        # ── Keep nouveau away from the console ────────────────────────────────
        #
        # On an Ampere card (tested: RTX 3070 / GA104) nouveau loads its GSP
        # firmware, deactivates the VGA console, then reports
        #   [drm] Cannot find any crtc or sizes
        # and owns fb0 with no working output. The machine boots fine and is
        # reachable over SSH the whole time — the screens just go black about ten
        # seconds in, after Ventoy and GRUB displayed perfectly. Measured on her
        # machine from the kernel log:
        #   [ 0.52] Initialized simpledrm ... fb0: simpledrmdrmfb   <- console OK
        #   [ 7.52] nouveau: vgaarb: deactivate vga console
        #   [ 9.15] nouveau: [drm] Cannot find any crtc or sizes
        #   [10.10] fbcon: nouveaudrmfb (fb0) is primary device     <- console dies
        #
        # A deployer ISO needs no GPU acceleration, so the simplest correct answer
        # is to leave the EFI framebuffer (simpledrm) in charge. That path works on
        # essentially any UEFI machine, AMD or NVIDIA, which is what a universal
        # installer stick wants anyway.
        #
        # Her INSTALLED system is unaffected: it uses the proprietary driver, and
        # the nixpkgs nvidia module blacklists nouveau itself.
        boot.blacklistedKernelModules = [ "nouveau" ];
        boot.kernelParams = [ "nouveau.modeset=0" ];

        # Mount the Ventoy stick's exFAT partition (to read the tailnet key) and
        # whatever else is plugged in. profiles/base.nix already covers ext*,
        # ntfs, vfat and friends; exfat is the one it leaves out.
        boot.supportedFilesystems.exfat = true;

        # ── Console: text, not a desktop ──────────────────────────────────────
        #
        # This used to greetd-autologin straight into niri. Don't: on unknown
        # hardware a graphical session is the single most likely thing to fail, and
        # when it does you get a BLACK SCREEN with no way to tell whether the machine
        # is alive, still booting, or wedged — which is exactly what happened the
        # first time this ISO was booted on a real target.
        #
        # A text console always paints, works on every GPU, and can say something
        # useful. `desktop` starts niri by hand when the rescue GUI is actually wanted.
        # Turning OFF the display-manager framework entirely is the load-bearing
        # part. Modules/Desktop/niri.nix sets services.xserver.enable = true, which
        # switches on services.displayManager — and that framework CLAIMS tty1 for a
        # display manager: getty.target.wants/ is never populated, so getty@tty1
        # never starts. Force sddm and greetd off but leave this on and you get the
        # worst of both: display-manager.service fails (nothing to launch) AND no
        # console login appears. Result is a totally black screen on a machine that
        # is otherwise booted, networked and SSH-able. Diagnosed on her RTX 3070.
        services.xserver.enable = lib.mkForce false;
        services.displayManager.enable = lib.mkForce false;
        services.displayManager.sddm.enable = lib.mkForce false;
        services.greetd.enable = lib.mkForce false;
        services.getty.autologinUser = lib.mkForce activeUser;

        # Belt and braces: wire the tty1 getty explicitly. `services.getty` only
        # adds `autovt@tty1` to getty.target.wants when displayManager is off, and
        # on this ISO that want did not materialise — getty.target came out as a bare
        # symlink to systemd's upstream unit with nothing wanting a getty, so the
        # console stayed dead even after the display manager was disabled. Verified
        # by checking for the symlink in the built system, not by assuming.
        systemd.services."getty@tty1" = {
          enable = true;
          wantedBy = [ "getty.target" ];
        };

        # Print the status page on login (console and ssh alike).
        programs.zsh.loginShellInit = "apollo-status";

        # ── SSH: keys only ────────────────────────────────────────────────────
        #
        # This user deliberately has NO password. `users.users.*.password` and
        # `.initialPassword` are written verbatim into /nix/store/*-users-groups.json,
        # which is mode 0444 — on an ISO that means the password is greppable out of
        # the squashfs without even booting it. Combined with sshd (on by default via
        # profiles/installation-device.nix), passwordless sudo below, and this node
        # being on the tailnet, a baked password would hand root to every tailnet
        # node. Console access doesn't need one: greetd autologins into niri and the
        # installer profile autologins `nixos` on the TTY.
        services.openssh.settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "prohibit-password";
        };

        # User
        users.users.${activeUser} = {
          isNormalUser = true;
          extraGroups = [ "networkmanager" "wheel" "video" "render" "input" ];
          openssh.authorizedKeys.keys = [ self.lib.sshKeys.jimmy ];
          shell = pkgs.zsh;
        };
        programs.zsh.enable = true;
        programs.dconf.enable = true;
        security.sudo.wheelNeedsPassword = false;

        # nixos-anywhere --build-on local builds the target's closure on Sisyphus
        # and `nix copy`s it here, which the receiving user must be trusted to
        # accept. installation-device.nix trusts only `nixos`, so without this the
        # push fails on the copy with "cannot add path ... untrusted user".
        nix.settings.trusted-users = [ activeUser ];

        # ── Join the tailnet with a key carried on the stick ───────────────────
        #
        # The key is NOT in the ISO. An ISO's store is world-readable and this repo
        # is public, so the key lives as a plain file (`ts-authkey`) next to the ISO
        # on the Ventoy stick and is read at boot. The stick is the secret, not the
        # image — which also means rotating the 90-day key is editing one file
        # rather than rebuilding and re-copying a 2 GB ISO.
        #
        # Modelled on marsbar-tailscale-up (Modules/Server/marsbar.nix) — the only other
        # non-interactive tailnet join in this repo.
        systemd.services.apollo-tailscale-up = {
          description = "Join the tailnet using the auth key on the Apollo stick";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "tailscaled.service" "network-online.target" ];
          requires = [ "tailscaled.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = with pkgs; [ tailscale jq util-linux coreutils gnugrep gawk ];
          script = ''
            set -u

            # tailscaled creates its socket a beat after the unit starts.
            for _ in $(seq 1 60); do
              [ -S /run/tailscale/tailscaled.sock ] && break
              sleep 1
            done

            state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null || echo Unknown)
            if [ "$state" = "Running" ]; then
              echo "already on the tailnet — nothing to do"
              exit 0
            fi

            # Apollo is tried first by label; anything else mountable is tried
            # after, so a freshly-made stick with another label still works.
            keyfile=/run/apollo-authkey
            mnt=/run/apollo-stick
            mkdir -p "$mnt"

            candidates=""
            [ -e /dev/disk/by-label/Apollo ] && candidates="/dev/disk/by-label/Apollo"
            candidates="$candidates $(lsblk -lnpo NAME,FSTYPE | awk '$2 == "exfat" || $2 == "vfat" || $2 == "ntfs" || $2 ~ /^ext[234]$/ { print $1 }')"

            found=""
            # Look in the stick root and in keys/ (where the age backup already
            # lives, so it is the natural home for a key file).
            for dev in $candidates; do
              mountpoint -q "$mnt" && umount "$mnt"
              mount -o ro "$dev" "$mnt" 2>/dev/null || continue
              for cand in "$mnt/ts-authkey" "$mnt/keys/ts-authkey"; do
                [ -f "$cand" ] || continue
                # Skip comment lines before matching, and require a real body after
                # "tskey-". Both matter: the placeholder template shipped on the stick
                # EXPLAINS the format, so it contains the literal string "tskey-" in
                # its own comments — a bare `grep -m1 tskey-` matches that comment and
                # yields a 6-character "key" that fails at `tailscale up` with a
                # useless error. Found exactly that way; do not simplify this.
                grep -v '^[[:space:]]*#' "$cand" \
                  | grep -m1 -oE 'tskey-[A-Za-z0-9._-]{8,}' > "$keyfile" || true
                if [ -s "$keyfile" ]; then
                  chmod 600 "$keyfile"
                  found="$dev ($cand)"
                  break
                fi
              done
              umount "$mnt" 2>/dev/null || true
              [ -n "$found" ] && break
            done

            if [ -z "$found" ] || [ ! -s "$keyfile" ]; then
              echo "no ts-authkey found on any removable device."
              echo "expected at <stick>/ts-authkey or <stick>/keys/ts-authkey, containing a"
              echo "line starting tskey-. Fill in keys/ts-authkey on the stick, write one with"
              echo "'apollo-key' from Sisyphus, or just run 'sudo tailscale up' here."
              exit 0
            fi
            echo "found ts-authkey on $found"

            # NO --ssh. Tailscale SSH takes over port 22 ON THE TAILSCALE IP, so
            # enabling it means tailscaled — not OpenSSH — answers `ssh rock@apollo`.
            # A plain ssh client then gets a TCP accept and no banner at all, and
            # hangs; `nixos-anywhere` and `apollo-connect` both break. Cost an evening
            # to find: the node looked perfectly healthy (tailscale ping fine, port 22
            # "open") while being completely unreachable. OpenSSH + the authorized key
            # is the way in here.
            tailscale up --authkey="file:$keyfile" --hostname=${tailnetName}

            rm -f "$keyfile"
          '';
        };


        # ── The status page ───────────────────────────────────────────────────
        #
        # Printed on every login (console and ssh). Answers, without typing anything:
        # is it on the tailnet, what do I type from Sisyphus, and what hardware is
        # this — the last being exactly what Hosts/Kit-Kat/system.nix needs for
        # installDisk and the NVIDIA `open` setting.
        environment.systemPackages = with pkgs; [
          (pkgs.writeShellScriptBin "apollo-status" ''
            #!/usr/bin/env bash
            ts=${pkgs.tailscale}/bin/tailscale
            c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

            echo
            c "1;36" "  ╭───────────────────────────────────────────────────────────╮"; echo
            c "1;36" "  │  APOLLO — NixOS deployer                                  │"; echo
            c "1;36" "  ╰───────────────────────────────────────────────────────────╯"; echo
            echo

            state=$($ts status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.BackendState' 2>/dev/null || echo Unknown)
            ip=$($ts ip -4 2>/dev/null | head -1)
            if [ "$state" = "Running" ] && [ -n "$ip" ]; then
              printf "   tailnet   "; c "1;32" "connected"; printf "  %s  (as '%s')\n" "$ip" "$(hostname)"
              printf "   from Sisyphus: "; c "1;33" "ssh rock@$(hostname)"; echo
              printf "                  "; c "1;33" "apollo-connect"; echo
            else
              printf "   tailnet   "; c "1;31" "NOT CONNECTED"; printf "  (state: %s)\n" "$state"
              echo "   why:      journalctl -u apollo-tailscale-up --no-pager | tail -20"
              echo "   fix:      put a key in <stick>/keys/ts-authkey, or run: sudo tailscale up"
            fi
            echo

            echo "   disks     (the name below is what Hosts/<Host>/system.nix installDisk needs)"
            ${pkgs.util-linux}/bin/lsblk -dno NAME,SIZE,MODEL 2>/dev/null | sed 's/^/     /'
            echo

            gpu=$(${pkgs.pciutils}/bin/lspci 2>/dev/null | grep -iE 'vga|3d controller' | sed 's/^[^ ]* //' | head -2)
            [ -n "$gpu" ] && { echo "   gpu"; printf '%s\n' "$gpu" | sed 's/^/     /'; echo; }

            printf "   ram       %s\n" "$(awk '/MemTotal/ {printf "%.1f GB", $2/1048576}' /proc/meminfo)"
            echo
            echo "   here      apollo-status   reprint this"
            echo "             desktop         start the niri rescue desktop"
            echo "             lsblk / gparted / parted"
            echo
          '')

          # Niri is still installed; it just isn't started automatically. Launch it
          # deliberately when the graphical rescue tools are wanted.
          (pkgs.writeShellScriptBin "desktop" ''
            #!/usr/bin/env bash
            echo "starting niri — if the screen goes black, switch back with Ctrl-Alt-F1"
            exec niri-session
          '')
          # ── rescue toolkit + everything needed to install a host from here ──
          # rescue
          vim
          home-manager
          gparted
          parted
          ntfs3g
          exfatprogs
          nix-output-monitor
          claude-code
          wl-clipboard
          grim
          slurp
          # deploy
          git
          jq
          rsync
          tmux
          pciutils
          usbutils
          nixos-anywhere
          nixos-facter
          ssh-to-age
          sops
          age
          mkpasswd
          inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko
        ];

        # Fonts
        fonts = {
          fontconfig.enable = true;
          packages = with pkgs; [
            nerd-fonts.fantasque-sans-mono
          ];
        };

        # ISO config
        # The produced filename comes from image.baseName, NOT from isoImage.isoName.
        # isoImage.isoName was renamed to image.fileName in 25.05, and iso-image.nix
        # passes `"${config.image.baseName}.iso"` to make-iso9660-image regardless of
        # it — so the old `isoImage.isoName = "nixos-rescue-rock.iso"` here never did
        # anything and the ISO came out as nixos-minimal-<label>-x86_64-linux.iso.
        # baseName is set unconditionally upstream, hence mkForce.
        image.baseName = lib.mkForce "apollo-deployer";
        isoImage.volumeID = "APOLLO";
        isoImage.squashfsCompression = "zstd -Xcompression-level 6";
      })
    ];
  };

  # `nix build .#apollo-iso` — wrapped by the `apollo-iso` helper in Modules/Shell/navi.nix.
  perSystem = { ... }: {
    packages.apollo-iso = self.nixosConfigurations.rock-Apollo.config.system.build.isoImage;
  };
}
