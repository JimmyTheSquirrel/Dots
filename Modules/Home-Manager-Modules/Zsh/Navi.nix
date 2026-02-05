{
  config,
  pkgs,
  ...
}: let
  naviDir = "${config.home.homeDirectory}/.config/navi";
  cheatsDir = "${naviDir}/cheats";

  # Make your “custom commands” real executables on PATH (so navi can run them)
  systemRebuildBin = pkgs.writeShellScriptBin "system-rebuild" ''
    #!/usr/bin/env bash
    set -euo pipefail

    cd "$HOME/Dots" || { echo "❌ $HOME/Dots not found"; exit 1; }

    sys="''${1:-}"
    if [[ -z "$sys" ]]; then
      echo "Usage: system-rebuild <flake-key>   e.g.  system-rebuild Sisyphus"
      echo "Available nixosConfigurations:"
      nix flake show . | sed -n 's/^ *nixosConfigurations\.\([A-Za-z0-9._-]\+\).*/  \1/p'
      exit 2
    fi

    # Allow '#Sisyphus' muscle memory
    sys="''${sys#\#}"

    echo -e "\n\033[1;34m==> Rebuilding NixOS system (#''${sys})...\033[0m"
    echo "+ sudo nixos-rebuild switch --flake .#''${sys}"
    sudo nixos-rebuild switch --flake ".#''${sys}"

    echo -e "\n\033[1;34m==> Rebuilding Home Manager (#''${sys})...\033[0m"
    echo "+ home-manager switch --flake .#''${sys}"
    home-manager switch --flake ".#''${sys}"

    echo -e "\n\033[1;32m==> All done!\033[0m"
  '';

  gitSyncBin = pkgs.writeShellScriptBin "git-sync" ''
    #!/usr/bin/env bash
    set -euo pipefail

    ORIG_DIR="$PWD"
    trap 'cd "$ORIG_DIR"' EXIT

    cd "$HOME/Dots" || { echo "❌ $HOME/Dots not found"; exit 1; }

    # Optional commit message
    if [[ -n "''${1:-}" ]]; then
      git add -A
      git commit -m "''${1}" || echo "↪ Nothing to commit."
    fi

    # Stash if dirty (including untracked)
    HAD_STASH=0
    if [[ -n "$(git status --porcelain=2 --untracked-files=all)" ]]; then
      STASH_MSG="autosync-$(date +%Y%m%d-%H%M%S)"
      echo "↪ repo dirty — stashing as $STASH_MSG"
      git stash push -u -m "$STASH_MSG"
      HAD_STASH=1
    fi

    # Ensure upstream exists
    branch="$(git branch --show-current)"
    if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
      echo "↪ no upstream for '$branch' — setting origin/$branch"
      git fetch origin
      git push -u origin "$branch"
    fi

    echo "↪ pulling (rebase)…"
    git pull --rebase

    if [[ "$HAD_STASH" -eq 1 ]]; then
      echo "↪ restoring stashed changes…"
      git stash pop || echo "⚠ stash pop had conflicts"
    fi

    echo "↪ pushing…"
    git push
  '';
in {
  programs.navi = {
    enable = true;
    enableZshIntegration = true;
  };

  # Ensure the helper binaries exist so navi can execute them
  home.packages = [
    systemRebuildBin
    gitSyncBin
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
      line="$(printf "%s" "$raw" | sed -r 's/\x1B\[[0-9;]*[[:alpha:]]//g')"

      # UI columns are separated by 2+ spaces: Title  Description  Command
      title="$(printf "%s" "$line" | awk -F '[[:space:]][[:space:]]+' '{print $1}')"
      ui_desc="$(printf "%s" "$line" | awk -F '[[:space:]][[:space:]]+' '{print $2}')"

      CHEATS_DIR="$HOME/.config/navi/cheats"

      desc=""
      cmd=""

      for f in "$CHEATS_DIR"/*.cheat; do
        [[ -f "$f" ]] || continue

        # Description: first "# ..." line after "% Title"
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

        # Command: non-empty, non-comment lines after "% Title" until next "%"
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

      # --- Header box (the “cheat title thing”) ---
      header="CHEATS"
      inner=52
      top="┌$(printf '─%.0s' $(seq 1 $((inner+2))))┐"
      lp=$(( (inner - ''${#header}) / 2 ))
      rp=$(( inner - ''${#header} - lp ))
      mid="│ $(printf "%*s" "$lp" "")$header$(printf "%*s" "$rp" "") │"
      bot="└$(printf '─%.0s' $(seq 1 $((inner+2))))┘"

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

      # Split chained commands into bullets
      formatted="$(printf "%s" "$cmd" | sed -E '
        s/[[:space:]]*(&&|;)[[:space:]]*/\n  • /g
        1s/^/  • /
      ')"

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
    # Delete old generations and optimise store (free space)
    sudo nix-collect-garbage -d && sudo nix-store --optimise

    % System Rebuild
    # Rebuild NixOS + Home Manager for Sisyphus
    system-rebuild Sisyphus

    % Git Sync
    # Same as git-sync, but include a commit message
    git-sync "chore: sync"
  '';
}
