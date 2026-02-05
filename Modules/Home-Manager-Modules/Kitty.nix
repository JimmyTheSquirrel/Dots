{ config, pkgs, ... }:

{
  programs.kitty = {
    enable = true;

    font = {
      name = "FantasqueSansM Nerd Font Mono";
      size = 16.0;
    };

    settings = {
      bold_font = "auto";
      italic_font = "auto";
      bold_italic_font = "auto";

      # Transparency & blur vibe
      background_opacity = "0.70";
      dynamic_background_opacity = "yes";

      # No nags on close
      confirm_os_window_close = 0;

      # Cursor
      cursor_shape = "beam";
      cursor_blink_interval = 0;
      cursor_trail = 1;

      # Scrolling
      scrollback_lines = 5000;
      wheel_scroll_min_lines = 1;

      # Misc
      enable_audio_bell = "no";
      window_padding_width = 12;

      # Gruvbox-inspired palette
      foreground = "#ebdbb2";
      background = "#1d2021";
      cursor     = "#ebdbb2";
      color0     = "#282828";
      color1     = "#cc241d";
      color2     = "#98971a";
      color3     = "#d79921";
      color4     = "#458588";
      color5     = "#b16286";
      color6     = "#689d6a";
      color7     = "#a89984";
      color8     = "#928374";
      color9     = "#fb4934";
      color10    = "#b8bb26";
      color11    = "#fabd2f";
      color12    = "#83a598";
      color13    = "#d3869b";
      color14    = "#8ec07c";
      color15    = "#ebdbb2";
    };
  };
}
