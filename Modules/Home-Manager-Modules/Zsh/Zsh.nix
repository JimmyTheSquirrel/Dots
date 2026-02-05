{
  config,
  pkgs,
  ...
}: {
  # Install helper script into a stable path in your home
  home.file.".config/zsh/zsh-helpers.sh" = {
    source = ./Scripts/zsh-helpers.sh;
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
      # Load helper functions
      if [ -f "${config.home.homeDirectory}/.config/zsh/zsh-helpers.sh" ]; then
        source "${config.home.homeDirectory}/.config/zsh/zsh-helpers.sh"
      fi

      # Fastfetch on new Kitty tabs
      if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
        command -v fastfetch >/dev/null && fastfetch
      fi

      # Custom clear: re-run fastfetch
      clear() {
        command clear "$@"
        if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
          command -v fastfetch >/dev/null && fastfetch && echo ""
        fi
      }

      # Custom prompt with borders - single line
      setopt PROMPT_SUBST

      # Git branch function
      git_branch() {
        local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
        if [ -n "$branch" ]; then
          echo "%F{#665c54}│%f%F{#458588}$branch%f"
        fi
      }

      # Build the prompt - single line with separators
      PROMPT='%F{#d65d0e}%n%f%F{#665c54}@%f%F{#d79921}%m%f %F{#665c54}│%f %F{#3e9c3e}%~%f$(git_branch) %(?.%F{#8ec07c}.%F{#fb4934})❯%f '

      # fzf-tab configuration - orange selected file, blue info/counter
      zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
      zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -1 --color=always $realpath'
      zstyle ':fzf-tab:*' fzf-flags --color=fg:#ebdbb2,hl:#d79921 --color=fg+:#d79921,bg+:-1,hl+:#d65d0e --color=info:#83a598,prompt:#bdae93,pointer:#d65d0e --color=marker:#d65d0e,spinner:#fabd2f,header:#665c54 --color=border:#ebdbb2
    '';
  };

  # Add fzf integration
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
}
