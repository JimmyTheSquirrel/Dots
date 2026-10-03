{ ... }: {
  flake.nixosModules.polkit = { pkgs, ... }: {
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
  };
}
