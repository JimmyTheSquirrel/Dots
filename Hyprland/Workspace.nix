{ lib, ... }: {
  # ---- WORKSPACES ----
  workspace = [
    # DP-2 ultrawide (main workspaces 1–6)
    "1, monitor:DP-2"
    "2, monitor:DP-2"
    "3, monitor:DP-2"
    "4, monitor:DP-2"
    "5, monitor:DP-2"
    "6, monitor:DP-2"

    # HDMI-A-1 named workspaces
    "name:discord,  monitor:HDMI-A-1"
    "name:spotify,  monitor:HDMI-A-1"
    "name:blank-01, monitor:HDMI-A-1"
    "name:blank-02, monitor:HDMI-A-1"
  ];

  # ---- WINDOW RULES ----
  windowrule = [
    # Pin apps to named workspaces (silent = don’t steal focus)
    "workspace name:discord silent, class:^(discord|vesktop)$"
    "workspace name:spotify silent, class:^(spotify)$"

    # Example: borderless floating windows
    "bordersize 0, floating:1"
    "rounding 0, floating:1"

    # Suppress maximize requests globally
    "suppressevent maximize, class:.*"

    # XWayland fixes
    "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
  ];

  # ---- AUTOSTART WORKSPACES ----
  exec-once = [
    # Spawn Discord into its workspace (if not already running)
    "hyprctl dispatch exec [workspace name:discord silent] discord"

    # Spawn Spotify into its workspace
    "hyprctl dispatch exec [workspace name:spotify silent] spotify"
  ];
}
