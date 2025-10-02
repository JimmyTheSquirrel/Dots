{ config, pkgs, ... }:

{
  imports = [
    ./Modules/Brave.nix
    ./Modules/Kitty.nix
    ./Modules/Zsh.nix
    ./Modules/Hyprpanel/Hyprpanel.nix
    ./Modules/Fastfetch.nix
    ./Modules/Vscodium.nix
    ./Modules/Nemo.nix
    ./Modules/Screenshot.nix
    ./Modules/WallpaperCarousel.nix
    ./Modules/Hyprland/Hyprland.nix

];

  home.username = "rock";
  home.homeDirectory = "/home/rock";
  home.stateVersion = "25.05";

  home.packages = with pkgs; [
    pkgs.swww
   ];

  home.file = { };

  home.sessionVariables = { };

  programs.home-manager.enable = true;
}
