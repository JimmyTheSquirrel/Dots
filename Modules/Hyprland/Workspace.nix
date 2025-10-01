{ lib, ... }: {
  # --- WORKSPACES ---
  workspace = [
    # DP-1 ultrawide (main workspaces 1–6)
    "1, monitor:DP-1"
    "2, monitor:DP-1"
    "3, monitor:DP-1"
    "4, monitor:DP-1"
    "5, monitor:DP-1"
    "6, monitor:DP-1"

    # HDMI monitor (named workspaces with autospawn apps)
    "discord, monitor:HDMI-A-1, exec:discord"
    "spotify, monitor:HDMI-A-1, exec:spotify"

    # Blank HDMI workspaces
    "blank-01, monitor:HDMI-A-1, exec:$terminal"
    "blank-02, monitor:HDMI-A-1"
  ];

  # --- WINDOW RULES ---
  windowrule = [
    # Pin apps to named workspaces (silent = don’t steal focus)
    "workspace discord silent, class:^(discord)$"
    "workspace spotify silent, class:^(spotify)$"

    # Example: borderless floating windows
    "bordersize 0, floating:1"
    "rounding 0, floating:1"

    # Suppress maximize requests globally
    "suppressevent maximize, class:.*"

    # XWayland fixes
    "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
  ];
}
