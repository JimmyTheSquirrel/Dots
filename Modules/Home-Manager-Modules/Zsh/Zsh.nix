{ config, pkgs, ... }:

{
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
    };

    # Use initContent (initExtra is deprecated)
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

      # Starship (guarded so terminals don’t break before HM runs)
      if command -v starship >/dev/null 2>&1; then
        eval "$(starship init zsh)"
      fi
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

      nix_shell = {
        disabled = false;
        format = "";
        symbol = "";
        impure_msg = "";
        pure_msg = "";
      };

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
