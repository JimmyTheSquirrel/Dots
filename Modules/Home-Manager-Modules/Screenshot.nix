# Modules/Screenshot.nix
{ config, pkgs, lib, ... }:

let
  mainMod = "SUPER"; # match what you use in your Hyprland config
in
{
  home.packages = with pkgs; [
    grim
    slurp
    wl-clipboard
    jq
  ];

  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      bind = [
        # Area screenshot → clipboard
        "${mainMod} SHIFT, S, exec, grim -g \"$(slurp)\" - | wl-copy"

        # Fullscreen screenshot → clipboard
        "${mainMod}, S, exec, grim - | wl-copy"

        # Active window screenshot → clipboard
        "${mainMod} CTRL, S, exec, grim -g \"$(hyprctl activewindow -j | jq -r '.at[0]'),$(hyprctl activewindow -j | jq -r '.at[1]')+$(hyprctl activewindow -j | jq -r '.size[0]')x$(hyprctl activewindow -j | jq -r '.size[1]')\" - | wl-copy"
      ];
    };
  };
}
