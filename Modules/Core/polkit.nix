{ ... }: {
  flake.nixosModules.polkit = { pkgs, ... }: {
    security.polkit.enable = true;
    services.udisks2.enable = true;
    services.gvfs.enable = true;

    # Not a polkit concern: NTFS support, most likely so udisks2 above can mount
    # Windows-formatted drives from the file manager. Left here because moving
    # it would change nothing; it is the odd one out if this module is split.
    boot.supportedFilesystems = [ "ntfs" ];

    # polkit_gnome is NOT in environment.systemPackages: the unit below runs it
    # by store path, and the package has nothing else to offer the system
    # profile — no bin/, and its XDG autostart entry is OnlyShowIn=GNOME;XFCE;Unity.
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
