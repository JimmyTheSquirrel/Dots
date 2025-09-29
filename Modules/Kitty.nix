{ config, pkgs, ... }:

{
  programs.kitty = {
    enable = true;

    # fonts
    font = {
      # matches:  "font_family FantasqueSansM Nerd Font Mono Bold"
      # In kitty the “Bold” part is usually controlled by bold_font, so we set family only:
      name = "FantasqueSansM Nerd Font Mono";
      size = 16.0;
    };

    # most kitty.conf options map 1:1 here
    settings = {
      bold_font = "auto";
      italic_font = "auto";
      bold_italic_font = "auto";

      background_opacity = "0.4";
      dynamic_background_opacity = "yes";
      confirm_os_window_close = 0;

      # cursor
      cursor_trail = 1;

      # platform
      linux_display_server = "auto";

      # scrolling
      scrollback_lines = 2000;
      wheel_scroll_min_lines = 1;

      # misc
      enable_audio_bell = "no";
      window_padding_width = 4;

      # selection + colors
      selection_foreground = "none";
      selection_background = "none";
      foreground = "#dddddd";
      background = "#000000";
      cursor = "#dddddd";
    };

    # if you keep a theme file, include it like your old config
    extraConfig = ''
      include ~/.config/kitty/kitty-themes/00-Default.conf
    '';
  };

  # (optional) Have HM manage/symlink your themes folder/file
  # Point this to wherever your theme(s) live inside your flake repo
  # Example if you store them under ./dotfiles/kitty-themes in your repo:
  # xdg.configFile."kitty/kitty-themes".source = ./kitty-themes;
}
