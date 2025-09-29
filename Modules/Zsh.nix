{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -lh";
      la = "ls -lha";
      gs = "git status";
    };

    initContent = ''
      # --------------------------------
      # --- Dots helpers ---------------
      # --------------------------------
      system-rebuild() {
        (
          cd ~/Dots || exit 1
          echo -e "\n\033[1;34m==> Rebuilding NixOS system...\033[0m"
          sudo nixos-rebuild switch --flake . || { echo -e "\033[1;31mNixOS rebuild failed\033[0m"; exit 1; }
          echo -e "\n\033[1;34m==> Rebuilding Home Manager...\033[0m"
          home-manager switch --flake . || { echo -e "\033[1;31mHome Manager rebuild failed\033[0m"; exit 1; }
          echo -e "\n\033[1;32m==> All done!\033[0m"
        )
      }

      git-sync() {
        (
          set -e
          cd ~/Dots || exit 1
          if [[ -n "$1" ]]; then git add -A; git commit -m "$1" || echo "Nothing to commit."; fi
          if [[ -n "$(git status --porcelain=2 --untracked-files=all)" ]]; then
            STASH_MSG="autosync-$(date +%Y%m%d-%H%M%S)"
            echo "↪ repo dirty — stashing as $STASH_MSG"
            git stash push -u -m "$STASH_MSG"; HAD_STASH=1
          fi
          echo "↪ pulling (rebase)…"; git pull --rebase
          if [[ -n "$HAD_STASH" ]]; then echo "↪ restoring stashed changes…"; git stash pop || echo "⚠ stash pop had conflicts"; fi
          echo "↪ pushing…"; git push
        )
      }

      # --- Fastfetch on new Kitty tabs ---
      if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
        command -v fastfetch >/dev/null && fastfetch
      fi

      # --- Custom clear: re-run fastfetch ---
clear() {
  command clear "$@"
  if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
    command -v fastfetch >/dev/null && fastfetch && echo ""
  fi
}


      # --- Starship must be initialized last ---
      eval "$(starship init zsh)"
    '';
  };

  programs.starship = {
    enable = true;

    settings = {
      palette = "gruvmix";
      palettes.gruvmix = {
        color_orange   = "#d65d0e";
        color_yellow   = "#d79921";
        color_green    = "#3e9c3e";
        color_blue     = "#458588";
        color_fg0      = "#fbf1c7";
        color_charcoal = "#3c3836";
      };

format = "[](fg:color_orange)[$username](bg:color_orange fg:color_fg0)[](fg:color_orange bg:color_charcoal)[@](bg:color_charcoal fg:color_fg0)[](fg:color_charcoal bg:color_yellow)[ $hostname](bg:color_yellow fg:color_fg0)[](fg:color_yellow bg:color_green)[$directory](bg:color_green fg:color_fg0)[](fg:color_green bg:color_blue)$git_branch$git_status[](fg:color_blue bg:color_charcoal)[](fg:color_charcoal) $character";


      username = {
        show_always = true;
        style_user = "bg:color_orange fg:color_fg0";
        style_root = "bg:color_orange fg:color_fg0";
        format = "[$user]($style)";
      };

      hostname = {
        ssh_only = false;
        style = "bg:color_yellow fg:color_fg0";
        format = "[$hostname]($style)";
      };

      directory = {
        style = "bg:color_green fg:color_fg0";
        truncation_length = 3;
        truncation_symbol = "…/";
        format = "[$path]($style)";
      };

      git_branch = {
        symbol = "";
        style  = "bg:color_blue fg:color_fg0";
        format = "[ $symbol $branch ]($style)";
      };

      git_status = {
        style  = "bg:color_blue fg:color_fg0";
        format = "[ $all_status$ahead_behind ]($style)";
      };

      character = {
        success_symbol = "[](bold fg:#8ec07c)";
        error_symbol   = "[](bold fg:#fb4934)";
      };

      # Fully nuke nix_shell display
      nix_shell = {
        disabled = false;
        format = "";
        symbol = "";
        impure_msg = "";
        pure_msg = "";
      };

      # Disable everything else
      line_break     = { disabled = true; };
      os             = { disabled = true; };
      package        = { disabled = true; };
      status         = { disabled = true; };
      cmd_duration   = { disabled = true; };
      container      = { disabled = true; };
      sudo           = { disabled = true; };
      battery        = { disabled = true; };
      time           = { disabled = true; };
      memory_usage   = { disabled = true; };
      jobs           = { disabled = true; };
      nodejs         = { disabled = true; };
      rust           = { disabled = true; };
      golang         = { disabled = true; };
      python         = { disabled = true; };
      php            = { disabled = true; };
      java           = { disabled = true; };
      kotlin         = { disabled = true; };
      haskell        = { disabled = true; };
      docker_context = { disabled = true; };
      conda          = { disabled = true; };
      pixi           = { disabled = true; };
    };
  };
}
