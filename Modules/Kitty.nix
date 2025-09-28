# Modules/Kitty.nix
{ config, pkgs, ... }:

{
  programs.kitty = {
    enable = true;

    font = {
      name = "FiraCode Nerd Font";   # pick a Nerd Font you like
      size = 12.0;
    };

    # Kitty config you’d normally put in kitty.conf
    extraConfig = ''
      shell /run/current-system/sw/bin/zsh

      # Appearance
      background_opacity 0.92
      confirm_os_window_close 0
      enable_audio_bell no
    '';
  };
}
