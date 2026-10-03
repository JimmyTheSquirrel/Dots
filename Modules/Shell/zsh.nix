{ ... }: {
  flake.nixosModules.zsh = { pkgs, lib, activeUser, ... }: {
    # The EDITOR fallback below. This is NixOS's default anyway; it is stated
    # so that switching nano off elsewhere conflicts here, loudly, instead of
    # leaving EDITOR naming a command that is not installed.
    programs.nano.enable = true;

    home-manager.users.${activeUser} = { config, ... }: {
      # A terminal editor that exists on EVERY host this module reaches.
      # lib.mkDefault so Modules/Apps/vscodium.nix can replace it with
      # `codium --wait` where VSCodium is actually installed.
      #
      # This was hardcoded to `codium --wait` everywhere, but Asgard and Apollo
      # have no VSCodium — there `git commit`, `sudoedit` and `systemctl edit`
      # all failed with "codium: command not found".
      home.sessionVariables = {
        EDITOR = lib.mkDefault "nano";
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
          # `c` (navi) is set in Modules/Shell/navi.nix, where navi itself is.
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
          if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
            command -v fastfetch >/dev/null && fastfetch
          fi

          clear() {
            command clear "$@"
            if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
              command -v fastfetch >/dev/null && fastfetch && echo ""
            fi
          }

          # Start Claude Code in the Dots repo where there is one. Guarded because
          # zsh is on every host and ~/Dots is not (Kit-Kat, Apollo): the old
          # unguarded `cd ~/Dots && command claude` meant `claude` did nothing
          # at all there except print "no such file or directory".
          claude() {
            [[ -d ~/Dots ]] && cd ~/Dots
            command claude "$@"
          }

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
  };
}
