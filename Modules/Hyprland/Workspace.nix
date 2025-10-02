{ lib, ... }: {
  # ---- WORKSPACES ----
  workspace = [
    # DP-4 ultrawide (main workspaces 1–6)
    "1, monitor:DP-4"
    "2, monitor:DP-4"
    "3, monitor:DP-4"
    "4, monitor:DP-4"
    "5, monitor:DP-4"
    "6, monitor:DP-4"

    # HDMI-A-2 named workspaces (persistent)
    "name:discord,  monitor:HDMI-A-2, persistent:true"
    "name:spotify,  monitor:HDMI-A-2, persistent:true"
    "name:blank-01, monitor:HDMI-A-2, persistent:true"
    "name:blank-02, monitor:HDMI-A-2, persistent:true"
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

    # Ensure blank-01 exists at startup
    "hyprctl dispatch workspace name:blank-01"

    # Jump focus back to ultrawide (DP-4) after creating HDMI workspaces
    "hyprctl dispatch focusmonitor DP-4"
  ];
}
