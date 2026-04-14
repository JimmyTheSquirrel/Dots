{ ... }: {
  flake.homeModules.zsh = { config, pkgs, ... }: {
    home.file.".config/zsh/zsh-helpers.sh" = {
      source = ./scripts/zsh-helpers.sh;
      executable = true;
    };

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      shellAliases = {
        ll = "ls -lh";
        la = "ls -lha";
        gs = "git status";
        c = "navi";
        brrt = "gofetch ~/Pictures/brrtfetch/gifs/defaults/brrt.gif";
      };

      plugins = [
        {
          name = "fzf-tab";
          src = pkgs.fetchFromGitHub {
            owner = "Aloxaf";
            repo = "fzf-tab";
            rev = "v1.1.2";
            sha256 = "sha256-Qv8zAiMtrr67CbLRrFjGaPzFZcOiMVEFLg1Z+N6VMhg=";
          };
        }
      ];

      initContent = ''
        if [ -f "${config.home.homeDirectory}/.config/zsh/zsh-helpers.sh" ]; then
          source "${config.home.homeDirectory}/.config/zsh/zsh-helpers.sh"
        fi

        if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
          command -v fastfetch >/dev/null && fastfetch
        fi

        clear() {
          command clear "$@"
          if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
            command -v fastfetch >/dev/null && fastfetch && echo ""
          fi
        }

        claude() {
          cd ~/Dots && command claude "$@"
        }

        setopt PROMPT_SUBST

        git_branch() {
          local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
          if [ -n "$branch" ]; then
            echo "%F{#665c54}│%f%F{#458588}$branch%f"
          fi
        }

        PROMPT='%F{#d65d0e}%n%f%F{#665c54}@%f%F{#d79921}%m%f %F{#665c54}│%f %F{#3e9c3e}%~%f$(git_branch) %(?.%F{#8ec07c}.%F{#fb4934})❯%f '

        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
        zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -1 --color=always $realpath'
        zstyle ':fzf-tab:*' fzf-flags \
          --height=40% \
          --border=none \
          --preview-window=right:55%:wrap \
          --color=fg:#ebdbb2,hl:#d79921 \
          --color=fg+:#d79921,bg+:-1,hl+:#d65d0e \
          --color=info:#83a598,prompt:#bdae93,pointer:#d65d0e \
          --color=marker:#d65d0e,spinner:#fabd2f,header:#665c54 \
          --color=border:#ebdbb2
      '';
    };

    programs.fzf = {
      enable = true;
      enableZshIntegration = true;

      defaultOptions = [
        "--height 60%"
        "--border rounded"
        "--layout=reverse"
        "--color=fg:#ebdbb2,bg:-1,hl:#d79921"
        "--color=fg+:#d79921,bg+:-1,hl+:#d65d0e"
        "--color=info:#83a598,prompt:#bdae93,pointer:#d65d0e"
        "--color=marker:#d65d0e,spinner:#fabd2f,header:#665c54"
        "--color=border:#ebdbb2"
      ];
    };
  };
}
