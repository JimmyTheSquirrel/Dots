{ ... }: {
  flake.nixosModules.hyprland = { pkgs, ... }: {
    programs.hyprland.enable = true;
    programs.xwayland.enable = true;

    services.xserver.enable = true;
    services.xserver.videoDrivers = [ "amdgpu" ];
    services.xserver.xkb = {
      layout = "au";
      variant = "";
    };

    services.displayManager.sddm.enable = true;
    services.displayManager.defaultSession = "hyprland";
    services.displayManager.sddm.settings.General = {
      CursorTheme = "Bibata-Modern-Classic";
      CursorSize = 24;
    };

    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gnome
        pkgs.xdg-desktop-portal-hyprland
      ];
      config.common.default = "gtk";
    };

    xdg.mime = {
      enable = true;
      defaultApplications = {
        "text/plain" = [ "codium.desktop" ];
        "text/x-nix" = [ "codium.desktop" ];
        "text/markdown" = [ "codium.desktop" ];
        "application/json" = [ "codium.desktop" ];
        "application/x-yaml" = [ "codium.desktop" ];
        "application/toml" = [ "codium.desktop" ];
        "text/yaml" = [ "codium.desktop" ];
      };
    };

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      XCURSOR_THEME = "Bibata-Modern-Classic";
      XCURSOR_SIZE = "24";
      HYPRCURSOR_THEME = "Bibata-Modern-Classic";
      HYPRCURSOR_SIZE = "24";
    };

    hardware.bluetooth.enable = true;
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}
