# ~/Dots/Modules/Hyprpanel/default.nix
{ pkgs, ... }:

{
  # Enable Hyprpanel
  programs.hyprpanel.enable = true;

  # Install hyprpanel and a Nerd Font so icons don’t break
home.packages = with pkgs; [
  hyprpanel
];











}
