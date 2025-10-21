# modules/Wlogout.nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  accent = "#b4befe"; # tweak to your taste
in {
  programs.wlogout = {
    enable = true;

    # The order here becomes the grid order (left→right, top→bottom).
    # Supported fields come from wlogout's layout format (label/action/text/keybind/height/width/circular).
    layout = [
      {
        label = "lock";
        action = "hyprlock";
        text = "Lock";
        keybind = "l";
      }
      {
        label = "logout";
        action = "hyprctl dispatch exit 0";
        text = "Logout";
        keybind = "e";
      }
      {
        label = "suspend";
        action = "systemctl suspend";
        text = "Suspend";
        keybind = "s";
      }
      {
        label = "hibernate";
        action = "systemctl hibernate";
        text = "Hibernate";
        keybind = "h";
      }
      {
        label = "shutdown";
        action = "systemctl poweroff";
        text = "Shutdown";
        keybind = "p";
      }
      {
        label = "reboot";
        action = "systemctl reboot";
        text = "Reboot";
        keybind = "r";
      }
    ];

    # Minimal CSS: card-like tiles w/ labels (no icons).
    style = ''
      window {
        background-color: rgba(8, 10, 15, 0.6);
      }

      # wlogout uses GTK CSS. This makes each tile a rounded “card”.
      button {
        background: #1e1e2e;
        color: ${accent};
        border: none;
        border-radius: 20px;
        padding: 32px;
        font-size: 22px;
        font-weight: 600;
      }

      button:hover, button:focus {
        background: #2b2e3b;
      }

      /* Spacing around the grid */
      #layout {
        margin: 80px;
      }

      /* The text under the (normally optional) icon area */
      .text {
        margin-top: 6px;
      }
    '';
  };

  # Small wrapper so you always get a 2×3 grid with comfy spacing
  home.packages = [
    (pkgs.writeShellScriptBin "wlogout-menu" ''
      exec ${pkgs.wlogout}/bin/wlogout \
        --buttons-per-row 3 \
        --column-spacing 30 \
        --row-spacing 30 \
        --margin 80 \
        --protocol layer-shell
    '')
  ];

  # Optional: makes it visible in app launchers
  xdg.desktopEntries.wlogout-menu = {
    name = "Logout Menu";
    exec = "wlogout-menu";
    terminal = false;
    type = "Application";
    categories = ["System"];
  };
}
