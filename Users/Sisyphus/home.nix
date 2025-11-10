# Home Manager config for user 'rock'
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  home.username = "rock";
  home.homeDirectory = "/home/rock";
  home.stateVersion = "25.05";

  imports = [
    ../../Hyprland/Hyprland.nix
    ../../Modules/Home-Manager-Modules/Zsh/Zsh.nix
    ../../Modules/Home-Manager-Modules/Vscodium.nix
    ../../Modules/Home-Manager-Modules/Kitty.nix
    ../../Modules/Home-Manager-Modules/Fastfetch.nix
    ../../Modules/Home-Manager-Modules/Brave.nix
    ../../Modules/Home-Manager-Modules/Screenshot.nix
    ../../Modules/Home-Manager-Modules/Wlogout.nix
    ../../Modules/Home-Manager-Modules/Wallpaper_Picker/WallpaperCarousel.nix
    ../../Modules/Home-Manager-Modules/Hyprpanel.nix
    ../../Modules/Home-Manager-Modules/App_Menu.nix
  ];

  programs.git.enable = true;
}
