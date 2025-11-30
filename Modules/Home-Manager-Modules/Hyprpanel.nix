{
  pkgs,
  inputs,
  ...
}: {
  programs.hyprpanel = {
    enable = true;
    package = pkgs.hyprpanel;

    settings = {
      layout = {
        bar.layouts = {
          "0" = {
            left = ["dashboard" "workspaces"];
            middle = ["media"];
            right = ["volume" "systray" "notifications"];
          };
        };
      };

      bar.launcher.autoDetectIcon = true;
      bar.workspaces.show_icons = true;

      menus.clock = {
        time = {
          military = true;
          hideSeconds = true;
        };
        weather.unit = "metric";
      };

      menus.dashboard.directories.enabled = false;
      menus.dashboard.stats.enable_gpu = true;

      theme = {
        bar.transparent = true;

        font = {
          name = "CaskaydiaCove Nerd Font";
          size = "16px";
        };

        # ⇣ Matugen integration (matches the GUI fields)
        matugen = {
          enable = true; # "Enable Matugen" toggle
          theme = "dark"; # dark | light | system
          scheme = "tonal-spot"; # e.g. vibrant, expressive, content, tonal-spot...
          variation = "standard_1"; # matches the dropdown in the screenshot
          contrast = 0; # -1 .. 1 (0 is default)
        };
      };
    };
  };

  # ensure the binaries/fonts exist
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    nerd-fonts.caskaydia-cove
    python312Packages.pywal # optional, if you also use pywal
    matugen # <-- required so the GUI toggle becomes clickable
  ];
}
