{ self, inputs, pkgs, ... }: {
  flake.nixosModules.pi5-niri = { pkgs, lib, activeUser, ... }: {
    programs.niri = {
      enable = true;
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.wrappedNiri;
    };

    # Autologin directly into niri — no login screen
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "niri-session";
          user = activeUser;
        };
      };
    };

    services.xserver.xkb = {
      layout = "au";
      variant = "";
    };

    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gnome
        pkgs.xdg-desktop-portal-gtk
      ];
      config.common = {
        default = "gtk";
        "org.freedesktop.impl.portal.ScreenCast" = "gnome";
        "org.freedesktop.impl.portal.Screenshot" = "gnome";
        "org.freedesktop.impl.portal.RemoteDesktop" = "gnome";
      };
    };
  };
}
