{ ... }: {
  flake.nixosModules.kde = { pkgs, ... }: {
    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.displayManager.sddm.wayland.enable = true;
    services.desktopManager.plasma6.enable = true;

    environment.plasma6.excludePackages = with pkgs.kdePackages; [
      konsole
      kate
      elisa
    ];

    programs.kdeconnect.enable = true;

    environment.systemPackages = with pkgs.kdePackages; [
      ark
      filelight
      kcalc
      dolphin
      dolphin-plugins
    ];
  };
}
