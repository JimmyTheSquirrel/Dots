{ config, pkgs, ... }:

{
  imports = [
    ./Modules/Brave.nix
    ./Modules/Kitty.nix
    ./Modules/Zsh.nix
    ./Modules/Hyprpanel.nix
    ./Modules/Fastfetch.nix
];

# basically copy the whole nvchad that is fetched from github to ~/.config/nvim
  xdg.configFile."nvim/" = {
    source = (pkgs.callPackage ./Modules/Nvchad.nix{}).nvchad;
  };





  home.username = "rock";
  home.homeDirectory = "/home/rock";
  home.stateVersion = "25.05";

  home.packages = with pkgs; [ ];

  home.file = { };

  home.sessionVariables = { };

  programs.home-manager.enable = true;
}
