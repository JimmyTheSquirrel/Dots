# navi — the cheatsheet UI (bound to `c`), with a preview pane.
#
# Only the tool and its look live here. The cheats themselves come from
# whichever modules have something to say: Modules/Shell/deploy-tools.nix adds
# rock's (system-rebuild, git-sync, Apollo, ssh shortcuts), and navi reads every
# *.cheat file under ~/.config/navi/cheats.
{ ... }: {
  flake.nixosModules.navi = { activeUser, ... }: {
    home-manager.users.${activeUser} = { config, lib, ... }:
    let
      naviDir = "${config.home.homeDirectory}/.config/navi";
      cheatsDir = "${naviDir}/cheats";
    in {
      programs.navi = {
        enable = true;
        enableZshIntegration = true;

        # ~/.config/navi/config.yaml — navi's default config location, so this
        # needs no NAVI_CONFIG. NAVI_PATH used to be exported too; it overrides
        # cheats.paths below, and only agreed with it by accident (it named
        # ~/.config/navi, one level above the cheats, and worked because navi
        # searches recursively). One source of truth now.
        settings = {
          cheats.paths = [ cheatsDir ];
          finder = {
            command = "fzf";
            overrides = lib.concatStringsSep " " [
              "--layout=reverse"
              "--no-sort"
              "--preview-window=up:18:wrap"
              "--preview '${naviDir}/preview.sh {}'"
            ];
          };
        };
      };

      # Here rather than in zsh.nix: zsh is on every host, navi is not, and an
      # alias to a missing command is just a confusing "command not found".
      programs.zsh.shellAliases.c = "navi";

      programs.zsh.initContent = lib.mkAfter ''
        # Wrap ONLY navi so it ignores FZF_DEFAULT_OPTS (e.g. --height 60%).
        # The empty assignment applies to this one command. It used to be an
        # `unset` inside the function, which runs in the interactive shell
        # itself — so the first `c` wiped fzf's colours (Ctrl-T, Alt-C, …) for
        # the rest of the session.
        navi() {
          FZF_DEFAULT_OPTS= command navi "$@"
        }
      '';

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
    };
  };
}
