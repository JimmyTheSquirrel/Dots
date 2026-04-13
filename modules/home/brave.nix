{ ... }: {
  flake.homeModules.brave = { ... }: {
    programs.brave = {
      enable = true;
      extensions = [
        { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
      ];
    };

    home.file.".config/brave-flags.conf".text = ''
      --password-store=basic
      --enable-features=UseOzonePlatform
      --ozone-platform=wayland
    '';

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = [ "brave-browser.desktop" ];
        "x-scheme-handler/http" = [ "brave-browser.desktop" ];
        "x-scheme-handler/https" = [ "brave-browser.desktop" ];
      };
    };

    programs.zsh.shellAliases.brave = "brave";
  };
}
