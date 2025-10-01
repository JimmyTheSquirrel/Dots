# Modules/Fastfetch.nix
{ pkgs, ... }:

let
  jsonConfig = builtins.toJSON {
    logo = {
      # Medium logo via Kitty graphics (works great in kitty)
      type = "kitty";
      source = "${pkgs.nixos-icons}/share/pixmaps/nix-snowflake.png";
      height = 9;                 # tweak 10–14 to taste
      padding = { top = 1; left = 1; };
    };

    display = { separator = " 󰑃  "; };

    modules = [
      "break"

      # --- OS / Kernel / Packages / Shell ---
      { type = "os";       key = " DISTRO"; keyColor = "yellow"; }
      { type = "kernel";   key = "│ ├";     keyColor = "yellow"; }
      { type = "packages"; key = "│ ├󰏖";    keyColor = "yellow"; }
      { type = "shell";    key = "│ └";    keyColor = "yellow"; }

      # --- Desktop / Theming ---
      { type = "wm";           key = " DE/WM";   keyColor = "blue"; }
      { type = "wmtheme";      key = "│ ├󰉼";     keyColor = "blue"; }
      { type = "icons";        key = "│ ├󰀻";     keyColor = "blue"; }
      { type = "cursor";       key = "│ ├";     keyColor = "blue"; }
      { type = "terminalfont"; key = "│ ├";     keyColor = "blue"; }
      { type = "terminal";     key = "│ └";     keyColor = "blue"; }

      # --- System Info ---
      { type = "host";    key = "󰌢 SYSTEM"; keyColor = "green"; }
      { type = "cpu";     key = "│ ├󰻠";    keyColor = "green"; }
      { type = "gpu";     key = "│ ├󰻑";    keyColor = "green"; format = "{2}"; }
      { type = "display"; key = "│ ├󰍹";    keyColor = "green"; compactType = "original-with-refresh-rate"; }
      { type = "memory";  key = "│ ├󰾆";    keyColor = "green"; }
      { type = "swap";    key = "│ ├󰓡";    keyColor = "green"; }
      { type = "uptime";  key = "│ └󰅐";    keyColor = "green"; }

      # (Removed sound/player/media and the rainbow custom line)
      "break"
    ];
  };
in
{
  home.packages = [ pkgs.fastfetch ];

  xdg.configFile."fastfetch/config.jsonc".text = jsonConfig;

}
