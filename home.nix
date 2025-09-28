{ config, pkgs, ... }:

{
  imports = [
    ../../Modules/Brave.nix
    ../../Modules/Kitty.nix
    ../../Modules/Zsh.nix
    ../../Modules/Hyprpanel.nix
  ];

  home.username = "rock";
  home.homeDirectory = "/home/rock";
  home.stateVersion = "25.05";

  home.packages = with pkgs; [ ];

  home.file = { };

  home.sessionVariables = { };

  programs.home-manager.enable = true;
}
