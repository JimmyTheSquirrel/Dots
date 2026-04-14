{ inputs, ... }: {
  flake.homeModules.navi = { config, pkgs, lib, ... }:
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
      (pkgs.writeShellScriptBin "system-rebuild" ''
        #!/usr/bin/env bash
        set -euo pipefail

        cd "$HOME/Dots" || { echo ":: $HOME/Dots not found"; exit 1; }

        sys="''${1:-}"
        if [[ -z "$sys" ]]; then
          echo "Usage: system-rebuild <flake-key>   e.g.  system-rebuild rock-Sisyphus"
          echo "Available nixosConfigurations:"
          nix flake show . | sed -n 's/^ *nixosConfigurations\.\([A-Za-z0-9._-]\+\).*/  \1/p'
          exit 2
        fi

        sys="''${sys#\#}"

        echo -e "\n\033[1;34m==> Rebuilding NixOS + Home Manager (#''${sys})...\033[0m"
        sudo nixos-rebuild switch --flake ".#''${sys}"

        echo -e "\n\033[1;32m==> All done!\033[0m"
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
      % System Cleanup
      # Full system cleanup (GC, store optimise, journal, podman)
      nix-gc

      % System Rebuild
      # Rebuild Sisyphus (Hyprland)
      sudo nixos-rebuild switch --flake "$HOME/Dots#rock-Sisyphus"

      % System Rebuild
      # Rebuild Odysseus (Niri)
      sudo nixos-rebuild switch --flake "$HOME/Dots#rock-Odysseus"

      % System Rebuild
      # Rebuild Elektra (KDE Plasma 6)
      sudo nixos-rebuild switch --flake "$HOME/Dots#rock-Elektra"

      % Remove mimeapps.list (fix Home Manager conflict)
      # Delete the file Home Manager complains about
      rm -f "$HOME/.config/mimeapps.list"

      % Git Sync
      # Same as git-sync, but include a commit message
      git-sync "chore: sync"

      % Git Cleanup (Nuke)
      # Wipe commit history on main and keep only current snapshot (FORCE PUSH)
      cd "$HOME/Dots" && git checkout main && git pull --rebase origin main && git checkout --orphan _fresh_main && git add -A && git commit -m "chore: fresh start" && git branch -M main && git push -f origin main

      % Restart Podman Containers
      # Restart all running podman containers
      podman restart $(podman ps -q)
    '';
  };
}
