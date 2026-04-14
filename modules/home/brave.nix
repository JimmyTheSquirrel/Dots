{ ... }: {
  flake.homeModules.brave = { config, hostName, ... }: {
    programs.brave = {
      enable = true;
      commandLineArgs = [
        "--password-store=basic"
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
        "--user-data-dir=${config.home.homeDirectory}/.config/BraveSoftware/Brave-Browser-${hostName}"
      ];
      extensions = [
        { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
      ];
    };

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
