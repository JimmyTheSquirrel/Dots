# Modules/Global_Modules/Polkit.nix
{ config, pkgs, lib, ... }:

{
  security.polkit.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  boot.supportedFilesystems = [ "ntfs" ];
  environment.systemPackages = [ pkgs.polkit_gnome ];

  systemd.user.services.polkit-gnome = {
    description = "polkit-gnome authentication agent";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
  };

  # Optional: allow wheel users to mount without a password
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
