{ self, inputs, ... }: {
  flake.nixosModules.helium = { pkgs, activeUser, ... }: {
    home-manager.users.${activeUser} = {
      home.packages = [
        inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };

    # Chromium enterprise policies - Helium reads from /etc/chromium/policies/managed/
    environment.etc."chromium/policies/managed/helium.json".text = builtins.toJSON {
      # Force install Bitwarden and pin it to the toolbar
      ExtensionSettings = {
        "nngceckbapebfimnlniiiahkandclblb" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
          toolbar_pin = "force_pinned";
        };
      };
      # Force bookmarks bar visible
      BookmarksBarEnabled = true;
      # Blank new tab page (removes "Add shortcut" widget)
      NewTabPageLocation = "about:blank";
      # Managed bookmark folders (read-only, always present)
      ManagedBookmarks = [
        { toplevel_name = "Bookmarks"; }
        {
          name = "Work";
          children = [
            { name = "Outlook"; url = "https://outlook.live.com"; }
          ];
        }
        {
          name = "Personal";
          children = [
            { name = "GitHub"; url = "https://github.com"; }
            { name = "Reddit"; url = "https://reddit.com"; }
            { name = "ProtonDB"; url = "https://www.protondb.com"; }
          ];
        }
      ];
    };
  };
}
