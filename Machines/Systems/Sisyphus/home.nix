# Home Manager config for user 'rock'
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
    ../../../Environments/Hyprland/Hyprland.nix
    ../../../Modules/Home-Manager-Modules/Zsh/Zsh.nix
    ../../../Modules/Home-Manager-Modules/Zsh/Navi.nix
    ../../../Modules/Home-Manager-Modules/Vscodium.nix
    ../../../Modules/Home-Manager-Modules/Kitty.nix
    ../../../Modules/Home-Manager-Modules/Fastfetch.nix
    ../../../Modules/Home-Manager-Modules/Brave.nix
    ../../../Modules/Home-Manager-Modules/Screenshot.nix
    ../../../Modules/Home-Manager-Modules/Rimsort.nix
    ../../../Modules/Home-Manager-Modules/Noctalia/noctalia.nix
    ../../../Modules/Home-Manager-Modules/git.nix
    #../../../Modules/Home-Manager-Modules/Swaylock.nix
    ../../../Modules/Home-Manager-Modules/Skwd.nix
    ../../../Modules/Home-Manager-Modules/Steam.nix
  ];

  # --- Fixes ---
  home.activation.removeMimeAppsList = lib.mkBefore ''
    rm -f "${config.home.homeDirectory}/.config/mimeapps.list"
  '';
}
