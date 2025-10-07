# Modules/Global_Modules/Polkit.nix
{ config, pkgs, lib, ... }:

let
  agent = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
in {
  # System services needed for GUI mounting
  security.polkit.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  # Kernel driver for Windows partitions
  boot.supportedFilesystems = [ "ntfs" ];

  # Provide the agent binary
  environment.systemPackages = [ pkgs.polkit_gnome ];

  # Start a polkit authentication agent in each graphical user session
  systemd.user.services.polkit-gnome = {
    Unit = {
      Description = "polkit-gnome authentication agent";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = agent;
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # OPTIONAL: let wheel users mount without a password prompt
  # security.polkit.extraConfig = ''
  #   polkit.addRule(function(action, subject) {
  #     if (subject.isInGroup("wheel") &&
  #         (action.id == "org.freedesktop.udisks2.filesystem-mount" ||
  #          action.id == "org.freedesktop.udisks2.filesystem-mount-other-seat" ||
  #          action.id == "org.freedesktop.udisks2.loop-modify")) {
  #       return polkit.Result.YES;
  #     }
  #   });
  # '';
}
