{
  config,
  pkgs,
  ...
}: {
  programs.wlogout = {
    enable = true;

    # Five buttons, no hibernate
    layout = [
      {
        label = "lock";
        action = "hyprlock";
      }
      {
        label = "logout";
        action = "hyprctl dispatch exit 0";
      }
      {
        label = "suspend";
        action = "systemctl suspend";
      }
      {
        label = "shutdown";
        action = "systemctl poweroff";
      }
      {
        label = "reboot";
        action = "systemctl reboot";
      }
    ];
  };

  # Launch helper that lays them out horizontally
  home.packages = [
    (pkgs.writeShellScriptBin "wlogout-row" ''
      exec ${pkgs.wlogout}/bin/wlogout \
        --buttons-per-row 5 \
        --row-spacing 0 \
        --column-spacing 40 \
        --margin-left 80 --margin-right 80 \
        --margin-top 260 --margin-bottom 260 \
        --protocol layer-shell
    '')
  ];

  # Optional desktop entry so it shows up in launchers
  xdg.desktopEntries.wlogout-row = {
    name = "Logout (row)";
    exec = "wlogout-row";
    terminal = false;
    type = "Application";
    categories = ["System"];
  };
}
