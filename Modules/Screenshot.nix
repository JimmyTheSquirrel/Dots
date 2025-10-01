
# Modules/Screenshot.nix
{ config, pkgs, ... }:

{
  # Install screenshot + clipboard tools
  home.packages = with pkgs; [
    grim
    slurp
    wl-clipboard
  ];

  # Hyprland keybinds for screenshots
  wayland.windowManager.hyprland = {
    settings = {
      bind = [
        # Area screenshot → clipboard
        "$mainMod SHIFT, P, exec, grim -g \"$(slurp)\" - | wl-copy"

        # Fullscreen screenshot → clipboard
        "$mainMod, P, exec, grim - | wl-copy"

        # Optional: active window screenshot → clipboard
        "$mainMod CTRL, P, exec, grim -g \"$(hyprctl activewindow -j | jq -r '.at[0]'),$(hyprctl activewindow -j | jq -r '.at[1]')+$(hyprctl activewindow -j | jq -r '.size[0]')x$(hyprctl activewindow -j | jq -r '.size[1]')\" - | wl-copy"
      ];
    };
  };
}
