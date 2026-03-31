{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  activeUser,
  ...
}: {
  home.username = activeUser;
  home.homeDirectory = "/home/${activeUser}";
  home.stateVersion = "25.05";

  imports = [
    ../../../Environments/Niri/Niri.nix
    ../../../Modules/Home-Manager-Modules/Zsh/Zsh.nix
    ../../../Modules/Home-Manager-Modules/Zsh/Navi.nix
    ../../../Modules/Home-Manager-Modules/Vscodium.nix
    ../../../Modules/Home-Manager-Modules/Kitty.nix
    ../../../Modules/Home-Manager-Modules/Fastfetch.nix
    ../../../Modules/Home-Manager-Modules/Brave.nix
    ../../../Modules/Home-Manager-Modules/Rimsort.nix
    ../../../Modules/Home-Manager-Modules/Noctalia/noctalia.nix
    ../../../Modules/Home-Manager-Modules/GTK.nix
    ../../../Modules/Home-Manager-Modules/Thunar-Home.nix
    ../../../Modules/Home-Manager-Modules/git.nix
    # Screenshots handled inside Niri.nix keybinds
  ];

  home.activation.removeMimeAppsList = lib.mkBefore ''
    rm -f "${config.home.homeDirectory}/.config/mimeapps.list"
  '';
}
