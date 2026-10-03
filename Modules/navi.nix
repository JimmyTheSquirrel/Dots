{ ... }: {
  flake.nixosModules.navi = { pkgs, activeUser, ... }: {
    home-manager.users.${activeUser} = { config, lib, ... }:
    let
      naviDir = "${config.home.homeDirectory}/.config/navi";
      cheatsDir = "${naviDir}/cheats";
    in {
      programs.navi = {
        enable = true;
        enableZshIntegration = true;
      };

      programs.zsh.initContent = lib.mkAfter ''
        # Wrap ONLY navi so it ignores FZF_DEFAULT_OPTS (e.g. --height 60%)
        navi() {
          unset FZF_DEFAULT_OPTS
          ${pkgs.navi}/bin/navi "$@"
        }
      '';

      home.packages = [
        # The single entry point. Two jobs behind one menu:
        #   1. rebuild a system (local boot profile, or push to a remote machine)
        #   2. deploy a system onto NEW hardware through the Apollo USB
        #
        # The USB itself (building the ISO, writing the tailnet key) is deliberately
        # NOT here: it is a rare, fiddly operation done from this machine, not
        # something to stumble into from a rebuild menu. apollo-iso / apollo-key
        # still exist as commands. apollo-connect (SSH to the booted stick) is on
        # the navi cheatsheet.
        (pkgs.writeShellScriptBin "system-rebuild" ''
          #!/usr/bin/env bash
          set -euo pipefail
          cd "$HOME/Dots" || { echo "❌ ~/Dots not found"; exit 1; }

          # host              flake user   kind    ssh target
          # ------------------------------------------------------------------
          # Sisyphus          rock         local   -
          # Kit-Kat           kitkat       remote  kitkat@kit-kat
          #
          # kind=local  -> sudo nixos-rebuild -p <profile>   (GRUB boot profile here)
          # kind=remote -> nixos-rebuild --target-host       (separate machine, no -p)
          host_meta() {
            case "$1" in
              Sisyphus) echo "rock   local  -" ;;
              Kit-Kat)  echo "kitkat remote kitkat@kit-kat" ;;
              *)        echo "" ;;
            esac
          }

          ask() { local p="$1"; shift; local r; read -p "$p" r; echo "$r"; }
          title() {
            echo -e "\033[1;36m╭──────────────────────────────╮\033[0m"
            printf  "\033[1;36m│\033[0m %-28s \033[1;36m│\033[0m\n" "$1"
            echo -e "\033[1;36m╰──────────────────────────────╯\033[0m"
          }

          user="${activeUser}"
          system=""
          action="switch"
          target_override=""
          mode="rebuild"

          if [[ -z "''${1:-}" ]]; then
            # ── interactive ──────────────────────────────────────────────────
            title "Dots"
            echo ""
            echo "  1) Rebuild a system      — push changes to a machine that already runs NixOS"
            echo "  2) Deploy a system       — install onto NEW hardware booted from the Apollo USB"
            echo ""
            case "$(ask 'What [1-2]: ')" in
              1) mode="rebuild" ;;
              2) mode="deploy"  ;;
              *) echo "Invalid choice"; exit 1 ;;
            esac


            echo ""
            if [[ "$mode" == "deploy" ]]; then
              title "Deploy onto NEW hardware"
              echo ""
              echo -e "\033[1;33m  The target must already be booted from the Apollo USB.\033[0m"
              echo -e "\033[1;33m  Check with: apollo-connect\033[0m"
              echo ""
              echo "  1) Kit-Kat   (her machine)"
              echo ""
              case "$(ask 'Deploy which system [1]: ')" in
                1) system="Kit-Kat" ;;
                *) echo "Invalid choice"; exit 1 ;;
              esac

              echo ""
              echo "  1) Dry run   — print the disk script, change nothing"
              echo "  2) VM test   — apply the layout in a throwaway VM"
              echo "  3) INSTALL   — ERASES the target's disks"
              echo ""
              read -r fu _ _ <<< "$(host_meta "$system")"
              case "$(ask 'What [1-3]: ')" in
                1) exec apollo-deploy --dry-run "''${fu}-''${system}" ;;
                2) exec apollo-deploy --vm-test "''${fu}-''${system}" ;;
                3) exec apollo-deploy "''${fu}-''${system}" ;;
                *) echo "Invalid choice"; exit 1 ;;
              esac
            fi

            title "Rebuild a system"
            echo ""
            echo "  1) Sisyphus  (Niri — this disk)"
            echo "  2) Kit-Kat   (Hyprland — her machine, over the tailnet)"
            echo ""
            case "$(ask 'System [1-2]: ')" in
              1) system="Sisyphus" ;;
              2) system="Kit-Kat"  ;;
              *) echo "Invalid choice"; exit 1 ;;
            esac

            echo ""
            echo "  1) Switch  (rebuild & activate now)"
            echo "  2) Boot    (rebuild, activate on next boot)"
            echo "  3) Test    (build only, activate nothing)"
            echo ""
            case "$(ask 'Action [1-3]: ')" in
              1) action="switch" ;;
              2) action="boot"   ;;
              3) action="build"  ;;
              *) echo "Invalid choice"; exit 1 ;;
            esac
          else
            # ── CLI: system-rebuild USER SYSTEM [--boot] [--target HOST] ─────
            user="''${1:-}"
            system="''${2:-}"
            shift 2 || true
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --boot) action="boot" ;;
                --test|--build) action="build" ;;
                --target) target_override="''${2:-}"; shift ;;
                *) echo "Unknown option: $1"; exit 2 ;;
              esac
              shift
            done
            if [[ -z "$system" ]]; then
              echo "Usage: system-rebuild USER SYSTEM [--boot] [--target HOST]"
              echo "   or: system-rebuild            (interactive — rebuild/deploy/apollo)"
              exit 2
            fi
          fi

          # Asgard's config is edited ON Asgard — Claude/server-info.md: "edit
          # server.nix on Asgard, not here — it drifts". Pushing this repo's copy
          # would overwrite the live config with a stale one, so refuse unless an
          # explicit --target says you really mean it.
          if [[ "$system" == "Asgard" && -z "$target_override" ]]; then
            echo -e "\033[1;31m==> Asgard is managed on Asgard, not from here.\033[0m"
            echo "    ssh asgard && sudo nixos-rebuild switch --flake ~/Dots#rock-Asgard"
            echo "To override deliberately: system-rebuild rock Asgard --target asgard"
            exit 1
          fi

          read -r meta_user meta_kind meta_target <<< "$(host_meta "$system")"
          [[ -n "''${meta_user:-}" ]] && user="$meta_user"
          remote_host=""
          [[ "''${meta_kind:-}" == "remote" ]] && remote_host="''${meta_target#*@}"
          [[ -n "$target_override" ]] && remote_host="$target_override"

          flake_key="''${user}-''${system}"

          if [[ -n "$remote_host" ]]; then
            ssh_target="''${user}@''${remote_host}"
            echo -e "\n\033[1;34m==> Deploying ''${system} to ''${ssh_target}...\033[0m"
            if [[ "$action" == "build" ]]; then
              cmd=(nixos-rebuild build --flake ".#''${flake_key}")
            else
              # --ask-sudo-password prompts here and feeds it over; only Asgard sets
              # wheelNeedsPassword = false.
              cmd=(nixos-rebuild "''${action}" --flake ".#''${flake_key}"
                   --target-host "''${ssh_target}" --ask-sudo-password)
            fi
          else
            profile=$(echo "$system" | tr '[:upper:]' '[:lower:]')
            echo -e "\n\033[1;34m==> ''${action^} ''${system} (profile: ''${profile})...\033[0m"
            cmd=(sudo nixos-rebuild "''${action}" -p "''${profile}" --flake ".#''${flake_key}")
          fi

          if "''${cmd[@]}"; then
            echo -e "\n\033[1;32m==> Done!\033[0m"
            # An `if`, not `[[ ... ]] && echo`. As the LAST statement in the script
            # that form returns the test's status, so a successful *switch* (where
            # the test is false) made the whole command exit 1 — printing "Done!"
            # and then reporting failure to anything chaining off it.
            if [[ "$action" == "boot" && -z "$remote_host" ]]; then
              echo -e "\033[1;33m==> Reboot and select ''${system} from GRUB.\033[0m"
            fi
          else
            echo -e "\n\033[1;31m==> Build failed.\033[0m"
            exit 1
          fi
        '')

        (pkgs.writeShellScriptBin "git-sync" ''
          #!/usr/bin/env bash
          set -euo pipefail

          ORIG_DIR="$PWD"
          trap 'cd "$ORIG_DIR"' EXIT

          cd "$HOME/Dots" || { echo ":: $HOME/Dots not found"; exit 1; }

          if [[ -n "''${1:-}" ]]; then
            git add -A
            git commit -m "''${1}" || echo ":: Nothing to commit."
          fi

          HAD_STASH=0
          if [[ -n "$(git status --porcelain=2 --untracked-files=all)" ]]; then
            STASH_MSG="autosync-$(date +%Y%m%d-%H%M%S)"
            echo ":: repo dirty - stashing as $STASH_MSG"
            git stash push -u -m "$STASH_MSG"
            HAD_STASH=1
          fi

          branch="$(git branch --show-current)"
          if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
            echo ":: no upstream for '$branch' - setting origin/$branch"
            git fetch origin
            git push -u origin "$branch"
          fi

          echo ":: pulling (rebase)..."
          git pull --rebase

          if [[ "$HAD_STASH" -eq 1 ]]; then
            echo ":: restoring stashed changes..."
            git stash pop || echo "!! stash pop had conflicts"
          fi

          echo ":: pushing..."
          git push
        '')

        (pkgs.writeShellScriptBin "nix-gc" ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo -e "\n\033[1;34m==> [1/4] Removing generations older than 7 days...\033[0m"
          sudo nix-collect-garbage --delete-older-than 7d

          echo -e "\n\033[1;34m==> [2/4] Optimising nix store (deduplicating)...\033[0m"
          sudo nix-store --optimise

          echo -e "\n\033[1;34m==> [3/4] Vacuuming systemd journal (keeping last 7 days)...\033[0m"
          journalctl --vacuum-time=7d

          echo -e "\n\033[1;34m==> [4/4] Pruning unused podman images/containers/volumes...\033[0m"
          podman system prune -f

          echo -e "\n\033[1;32m==> All done! Nix store size:\033[0m"
          du -sh /nix/store
        '')

        # ── Apollo: the deployer USB ────────────────────────────────────────────
        #
        # Hosts/Rescue/system.nix builds the ISO. These four commands are the whole
        # workflow from this side; nothing is ever initiated by the stick itself.
        #
        #   apollo-iso      build the ISO and copy it onto the Ventoy stick
        #   apollo-key      put the tailnet auth key on the stick (from sops)
        #   apollo-connect  wait for the booted stick to appear, then SSH in
        #   apollo-deploy   install a host onto the booted machine (WIPES ITS DISK)

        (pkgs.writeShellScriptBin "apollo-iso" ''
          #!/usr/bin/env bash
          set -euo pipefail
          cd "$HOME/Dots" || { echo "❌ ~/Dots not found"; exit 1; }

          echo -e "\033[1;34m==> Building .#apollo-iso ...\033[0m"
          out=$(nix build .#apollo-iso --no-link --print-out-paths)
          iso="$out/iso/apollo-deployer.iso"
          [[ -f "$iso" ]] || { echo "❌ no ISO at $iso"; ls -l "$out/iso" || true; exit 1; }
          echo ":: $iso ($(du -h "$iso" | cut -f1))"

          dest=$(findmnt -rn -o TARGET -S LABEL=Apollo || true)
          if [[ -z "$dest" ]]; then
            if [[ -e /dev/disk/by-label/Apollo ]]; then
              echo -e "\033[1;33m==> Apollo is plugged in but not mounted. Mount it with:\033[0m"
              echo "    udisksctl mount -b /dev/disk/by-label/Apollo"
            else
              echo -e "\033[1;33m==> Apollo not found. Plug the Ventoy stick in, then re-run.\033[0m"
            fi
            echo ":: ISO is built and ready at:"
            echo "   $iso"
            exit 0
          fi

          # The stick already keeps images in ISOs/ (Ventoy scans subdirectories),
          # so follow that rather than dropping it in the root.
          sub="$dest"
          [[ -d "$dest/ISOs" ]] && sub="$dest/ISOs"

          echo -e "\033[1;34m==> Copying to $sub ...\033[0m"
          cp --no-preserve=mode,ownership "$iso" "$sub/apollo-deployer.iso"
          sync
          echo -e "\033[1;32m==> Done. Boot it from Ventoy on the target machine.\033[0m"
          echo -e "\033[1;33m   Secure Boot must be off, or Ventoy's shim MOK-enrolled.\033[0m"
        '')

        (pkgs.writeShellScriptBin "apollo-key" ''
          #!/usr/bin/env bash
          set -euo pipefail
          cd "$HOME/Dots" || { echo "❌ ~/Dots not found"; exit 1; }

          dest=$(findmnt -rn -o TARGET -S LABEL=Apollo || true)
          if [[ -z "$dest" ]]; then
            echo "❌ Apollo is not mounted."
            [[ -e /dev/disk/by-label/Apollo ]] \
              && echo "   udisksctl mount -b /dev/disk/by-label/Apollo"
            exit 1
          fi

          # The key is a plain file on the stick, never baked into the ISO: an ISO's
          # Nix store is world-readable and this repo is public. The stick is the
          # secret. Rotating the (max 90-day) key is re-running this command.
          echo -e "\033[1;33m==> This writes the tailnet installer key in cleartext to:\033[0m"
          # keys/ is where the age backup already lives, so the tailnet key goes
          # there too. The boot unit checks both keys/ts-authkey and the root.
          keydir="$dest/keys"
          mkdir -p "$keydir"
          echo "    $keydir/ts-authkey"
          read -p "Continue? [y/N] " ok
          [[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "aborted"; exit 1; }

          sops -d --extract '["tailscale-installer-key"]' Secrets/secrets.yaml \
            | tr -d '[:space:]' > "$keydir/ts-authkey"
          [[ -s "$keydir/ts-authkey" ]] || { echo "❌ decrypt produced nothing"; exit 1; }
          sync
          echo -e "\033[1;32m==> Key written ($(wc -c < "$keydir/ts-authkey") bytes).\033[0m"
          echo ":: note: exFAT has no permissions — physical possession of the stick is the control."
        '')

        (pkgs.writeShellScriptBin "apollo-connect" ''
          #!/usr/bin/env bash
          set -euo pipefail

          # Resolve the LIVE apollo node, not the name "apollo".
          #
          # Ephemeral nodes linger in the device list for a while after going
          # offline, and Tailscale will not reuse a name that is still taken — so the
          # second boot of the stick registers as `apollo-1`, the third as `apollo-2`.
          # Hardcoding `apollo` then points at a DEAD node: ssh hangs, deploys fail,
          # and the live machine is sitting right there. Pick by prefix + Online.
          resolve_apollo() {
            tailscale status --json 2>/dev/null \
              | ${pkgs.jq}/bin/jq -r '[.Peer[]? | select(.HostName | startswith("apollo")) | select(.Online) | .TailscaleIPs[0]] | first // empty'
          }
          node="''${APOLLO_NODE:-}"

          if ! tailscale status >/dev/null 2>&1; then
            echo "❌ tailscaled isn't reachable here. Is tailscale up on this machine?"
            exit 1
          fi
          if [ -z "$node" ]; then
            node=$(resolve_apollo)
            if [ -z "$node" ]; then
              echo -n ":: waiting for the Apollo stick to join the tailnet "
              for _ in $(seq 1 60); do
                node=$(resolve_apollo)
                [ -n "$node" ] && { echo " found."; break; }
                echo -n "."
                sleep 2
              done
            fi
          fi

          if [ -z "$node" ]; then
            echo ""
            echo "❌ no online apollo* node after 2 minutes."
            echo "   On the stick: check 'systemctl status apollo-tailscale-up', and that"
            echo "   keys/ts-authkey is present on the Ventoy partition ('apollo-key' writes it)."
            exit 1
          fi
          echo ":: using node '$node'"

          # The ISO is read-only, so it generates a FRESH ssh host key on every boot.
          # Without these options every single use of the stick trips
          # "REMOTE HOST IDENTIFICATION HAS CHANGED". A new identity each boot is the
          # expected behaviour here, and the tailnet is already authenticating the node.
          exec ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o GlobalKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "rock@''${node}" "$@"
        '')

        (pkgs.writeShellScriptBin "apollo-deploy" ''
          #!/usr/bin/env bash
          set -euo pipefail
          cd "$HOME/Dots" || { echo "❌ ~/Dots not found"; exit 1; }

          vm_test=0
          dry_run=0
          while true; do
            case "''${1:-}" in
              --vm-test) vm_test=1; shift ;;
              --dry-run) dry_run=1; shift ;;
              *) break ;;
            esac
          done

          attr="''${1:-}"
          if [[ -z "$attr" ]]; then
            echo "Usage: apollo-deploy [--vm-test|--dry-run] <flake-attr> [ssh-target]"
            echo "   e.g. apollo-deploy kitkat-Kit-Kat"
            echo "        apollo-deploy --dry-run kitkat-Kit-Kat   # print the disko script"
            echo "        apollo-deploy --vm-test kitkat-Kit-Kat   # apply it in a VM (see caveat)"
            echo ""
            echo "Env: APOLLO_EXTRA_FILES=<dir>  override; default ~/.local/share/apollo/<Host>"
            exit 2
          fi
          # Default target is the LIVE apollo* node, resolved the same way
          # apollo-connect does it. Ephemeral nodes linger in the device list after
          # going offline and Tailscale will not reuse a taken name, so the second
          # boot of the stick is `apollo-1`, the third `apollo-2`. A hardcoded
          # `rock@apollo` then aims at a DEAD node while the live machine sits there.
          if [ -n "''${2:-}" ]; then
            target="$2"
          else
            n=$(tailscale status --json 2>/dev/null \
                | ${pkgs.jq}/bin/jq -r '[.Peer[]? | select(.HostName | startswith("apollo")) | select(.Online) | .TailscaleIPs[0]] | first // empty')
            [ -z "$n" ] && { echo "❌ no online apollo* node — is the stick booted?"; exit 1; }
            target="rock@$n"
            echo ":: target resolved to $target"
          fi

          # Attr is <user>-<Host>; the facter report lives with the host it describes.
          host="''${attr#*-}"
          facter="./Hosts/''${host}/facter.json"
          [[ -d "./Hosts/''${host}" ]] || { echo "❌ no Hosts/''${host}/ in this repo"; exit 1; }

          if [[ "$dry_run" == 1 ]]; then
            # The disko script itself, printed rather than run. Works for any layout
            # whatever its size, and shows the exact sgdisk/mkfs/mount commands that
            # would be issued against the host's disk.
            echo -e "\033[1;34m==> disko script for .#''${attr} (nothing is executed):\033[0m\n"
            script=$(nix build ".#nixosConfigurations.''${attr}.config.system.build.diskoScript" \
                       --no-link --print-out-paths)
            cat "$script"
            echo -e "\n\033[1;32m==> That script builds. Check the device names above before installing.\033[0m"
            exit 0
          fi

          if [[ "$vm_test" == 1 ]]; then
            echo -e "\033[1;34m==> VM-testing .#''${attr} (no target touched) ...\033[0m"
            echo -e "\033[1;33m:: caveat: disko's test harness hardcodes a 4 GiB disk"
            echo -e "   (emptyDiskImages = 4096, lib/tests.nix — not settable from our config),"
            echo -e "   so a layout with more than ~4 GiB of fixed-size partitions can never"
            echo -e "   pass here. Kit-Kat's 16 G swap puts it over; use --dry-run for those.\033[0m"
            echo ""

            # ⚠ `nixos-anywhere --vm-test` EXITS 0 EVEN WHEN THE TEST FAILS. A failed
            # disko run inside the VM surfaces only as text — "RequestedAssertionFailed"
            # / "failed (exit code N)" — while the wrapper still returns success. So the
            # output is the outcome here, never $?.
            log=$(mktemp)
            nixos-anywhere --flake ".#''${attr}" --vm-test 2>&1 | tee "$log"
            if grep -qE "RequestedAssertionFailed|failed \(exit code|error: build of" "$log"; then
              echo -e "\n\033[1;31m==> VM test FAILED (despite exit 0 — see above).\033[0m"
              if grep -q "not saving changes" "$log"; then
                echo "sgdisk could not write the table, which is almost certainly the 4 GiB"
                echo "harness disk rather than your partitioning. Use --dry-run, or shrink the"
                echo "swap partition in Hosts/''${host}/system.nix temporarily to smoke-test it."
              fi
              rm -f "$log"
              exit 1
            fi
            rm -f "$log"
            echo -e "\n\033[1;32m==> VM test passed: the layout applies cleanly.\033[0m"
            exit 0
          fi

          args=(
            --flake ".#''${attr}"
            --target-host "$target"
            --generate-hardware-config nixos-facter "$facter"
            --build-on local
            --ssh-option StrictHostKeyChecking=no
            --ssh-option UserKnownHostsFile=/dev/null
          )
          # Files planted onto the new system during the install — chiefly the
          # PRE-GENERATED ssh host key whose age identity is already a recipient of
          # that host's sops file. Without it the machine generates its own host key
          # at first boot, sops has never heard of that identity, and the very first
          # activation cannot decrypt anything — which for Kit-Kat means no login
          # password. The only fix at that point is to reinstall or hand-copy a key.
          #
          # Default location is OUTSIDE the repo on purpose: this repo is public and
          # these are private keys. Generate a host's set with:
          #   mkdir -p ~/.local/share/apollo/<Host>/etc/ssh
          #   ssh-keygen -t ed25519 -N "" -C root@<Host> \
          #     -f ~/.local/share/apollo/<Host>/etc/ssh/ssh_host_ed25519_key
          #   nix run nixpkgs#ssh-to-age -- -i <that>.pub     # -> the age recipient
          # then add that recipient to .sops.yaml and `sops updatekeys` the host's file.
          extra="''${APOLLO_EXTRA_FILES:-$HOME/.local/share/apollo/''${host}}"
          if [[ -d "$extra" ]]; then
            args+=(--extra-files "$extra")
            echo -e "\033[1;32m:: planting these onto the new system:\033[0m"
            find "$extra" -type f -printf '     /%P\n' 2>/dev/null
            echo ""
          else
            echo -e "\033[1;31m:: NO extra files found at $extra\033[0m"
            echo "   The new system will generate its own ssh host key, so any sops secret"
            echo "   keyed to that host key will NOT decrypt on first boot — for a desktop"
            echo "   that usually means no login password."
            echo ""
            read -p "   Continue anyway? [y/N] " ok
            [[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "aborted"; exit 1; }
          fi

          # Show the MACHINE, not just the config name. Typing "Kit-Kat" proves you
          # know which config you are installing; it proves nothing about which
          # physical box is on the other end of the tailnet. If a different machine
          # were booted from an Apollo stick, the old prompt would happily wipe it.
          echo -e "\033[1;34m:: asking $target what it is...\033[0m"
          ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
              -o LogLevel=ERROR -o ConnectTimeout=15 -o BatchMode=yes "$target" '
            printf "  machine   : %s %s\n" "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" "$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
            printf "  ram       : %s\n" "$(awk "/MemTotal/ {printf \"%.1f GB\", \$2/1048576}" /proc/meminfo)"
            echo   "  disks     :"
            lsblk -dno NAME,SIZE,MODEL 2>/dev/null | sed "s/^/              /"
          ' || { echo "❌ could not reach $target to identify it"; exit 1; }
          echo ""

          echo -e "\033[1;31m╭────────────────────────────────────────────────────────────╮\033[0m"
          echo -e "\033[1;31m│  This ERASES every disk named in ''${host}'s disko config.   │\033[0m"
          echo -e "\033[1;31m╰────────────────────────────────────────────────────────────╯\033[0m"
          echo "  flake attr : .#''${attr}"
          echo "  target     : $target"
          echo "  WILL WIPE  : $(grep -oP 'installDisk\s*=\s*"\K[^"]+' "Hosts/''${host}/system.nix" 2>/dev/null || echo '(see disko config)')"
          echo "  facter out : $facter  (overwritten)"
          echo ""
          echo -e "\033[1;33m  Check the disk above appears in that machine's disk list.\033[0m"
          echo ""
          read -p "Type the host name ('"''${host}"') to proceed: " confirm
          [[ "$confirm" == "''${host}" ]] || { echo "aborted"; exit 1; }

          # nixos-anywhere detects VARIANT_ID=installer on the Apollo ISO and skips
          # kexec, so this SSH session (and the tailnet link under it) survives the
          # whole install.
          nixos-anywhere "''${args[@]}"

          echo -e "\n\033[1;32m==> Installed. Review and commit the generated $facter.\033[0m"
        '')
      ];

      home.sessionVariables = {
        NAVI_CONFIG = "${naviDir}/config.yaml";
        NAVI_PATH = "${naviDir}";
      };

      home.file.".config/navi/preview.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail

          raw="''${1-}"

          # Strip ANSI escape codes
          line="$(printf "%s" "$raw" | sed -r "s/\x1B\[[0-9;]*[[:alpha:]]//g")"

          # UI columns are separated by 2+ spaces: Title  Description  Command
          title="$(printf "%s" "$line" | awk -F "[[:space:]][[:space:]]+" "{print \$1}")"
          ui_desc="$(printf "%s" "$line" | awk -F "[[:space:]][[:space:]]+" "{print \$2}")"

          CHEATS_DIR="$HOME/.config/navi/cheats"
          desc=""
          cmd=""

          for f in "$CHEATS_DIR"/*.cheat; do
            [[ -f "$f" ]] || continue

            if [[ -z "$desc" ]]; then
              d="$(
                awk -v t="$title" '
                  BEGIN { inblk=0 }
                  /^%[[:space:]]+/ {
                    sect = substr($0, 3)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", sect)
                    inblk = (sect == t)
                    next
                  }
                  inblk && /^#[[:space:]]*/ {
                    s=$0
                    sub(/^#[[:space:]]*/, "", s)
                    print s
                    exit
                  }
                ' "$f"
              )"
              [[ -n "$d" ]] && desc="$d"
            fi

            if [[ -z "$cmd" ]]; then
              c="$(
                awk -v t="$title" '
                  BEGIN { inblk=0 }
                  /^%[[:space:]]+/ {
                    sect = substr($0, 3)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", sect)
                    inblk = (sect == t)
                    next
                  }
                  inblk {
                    if ($0 ~ /^%[[:space:]]+/) exit
                    if ($0 ~ /^#/) next
                    if ($0 ~ /^[[:space:]]*$/) next
                    print
                  }
                ' "$f"
              )"
              [[ -n "$c" ]] && cmd="$c"
            fi

            [[ -n "$desc" && -n "$cmd" ]] && break
          done

          [[ -z "$desc" ]] && desc="$ui_desc"
          [[ -z "$cmd"  ]] && cmd="(command not found in cheats)"

          header="CHEATS"
          inner=52
          top="$(printf '%-54s' | tr ' ' '-')"
          top="+-$top-+"
          lp=$(( (inner - ''${#header}) / 2 ))
          rp=$(( inner - ''${#header} - lp ))
          mid="| $(printf "%*s" "$lp" "")$header$(printf "%*s" "$rp" "") |"
          bot="+-$(printf '%-54s' | tr ' ' '-')-+"

          echo "$top"
          echo "$mid"
          echo "$bot"
          echo

          echo "Title:"
          echo "  $title"
          echo
          echo "Description:"
          echo "  $desc"
          echo
          echo "Command:"
          echo

          formatted="$(printf "%s" "$cmd" | sed -E "
            s/[[:space:]]*(&&|;)[[:space:]]*/\n  * /g
            1s/^/  * /
          ")"

          cols="''${FZF_PREVIEW_COLUMNS:-140}"
          printf "%s\n" "$formatted" | fold -s -w "$cols"
        '';
      };

      home.file.".config/navi/config.yaml".text = ''
        cheats:
          paths:
            - ${cheatsDir}

        finder:
          command: fzf
          overrides: >
            --layout=reverse
            --no-sort
            --preview-window=up:18:wrap
            --preview '${naviDir}/preview.sh {}'
      '';

      home.file.".config/navi/cheats/rhys.cheat".text = ''
        % Dots
        # Everything: rebuild a system, deploy new hardware, Apollo USB
        system-rebuild

        % Dots
        # Full system cleanup (GC, store optimise, journal, podman)
        nix-gc

        % Dots
        # Commit, pull --rebase, push
        git-sync "chore: sync"

        % Dots
        # Open encrypted secrets (decrypts in editor, re-encrypts on save)
        sops ~/Dots/Secrets/secrets.yaml

        % SSH
        # Asgard — media server
        ssh asgard

        % SSH
        # Apollo — the booted deployer USB (waits for it to appear)
        apollo-connect

        % SSH
        # Kit-Kat — her machine
        ssh kitkat@kit-kat
      '';
    };
  };
}
