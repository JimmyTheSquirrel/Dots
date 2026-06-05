{ ... }: {
  flake.nixosModules.discord = { pkgs, activeUser, ... }: {
    home-manager.users.${activeUser} = { lib, ... }: {
      home.packages = [ pkgs.vesktop ];

      # Desktop entry that shows as "Discord" instead of "Vesktop"
      xdg.desktopEntries.discord = {
        name = "Discord";
        exec = "vesktop %U";
        icon = "discord";
        comment = "Discord with Vencord";
        categories = [ "Network" "InstantMessaging" ];
        terminal = false;
      };

      # Clear Vesktop cache on rebuild to prevent EPIPE errors
      home.activation.clearVesktopCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        rm -rf ~/.config/vesktop/Cache
        rm -rf ~/.config/vesktop/Code\ Cache
        rm -rf ~/.config/vesktop/GPUCache
      '';

      # Vencord settings with transparent theme
      xdg.configFile."vesktop/settings/quickCss.css".text = ''
        /* Transparent Discord for compositor transparency */
        :root {
          --background-primary: transparent !important;
          --background-secondary: rgba(0, 0, 0, 0.4) !important;
          --background-secondary-alt: rgba(0, 0, 0, 0.3) !important;
          --background-tertiary: rgba(0, 0, 0, 0.5) !important;
          --background-floating: rgba(0, 0, 0, 0.7) !important;
          --background-modifier-hover: rgba(255, 255, 255, 0.05) !important;
          --background-modifier-selected: rgba(255, 255, 255, 0.1) !important;
        }

        .theme-dark {
          --background-primary: transparent !important;
          --background-secondary: rgba(0, 0, 0, 0.4) !important;
          --background-secondary-alt: rgba(0, 0, 0, 0.3) !important;
          --background-tertiary: rgba(0, 0, 0, 0.5) !important;
        }

        /* Main app background */
        .app-3xd6d0,
        .app-2CXKsg,
        .appMount-2yBXZl,
        .bg-1QIAus,
        .container-1eFtFS,
        .chat-2ZfjoI,
        .chatContent-3KubbW,
        .members-3WRCEx,
        .membersWrap-3NUR2t {
          background: transparent !important;
        }

        /* Sidebar */
        .sidebar-1tnWFu,
        .container-1NXEtd,
        .panels-3wFtMD {
          background: transparent !important;
        }

        /* Server list */
        .wrapper-1_HaEi,
        .scroller-3X7KbA {
          background: transparent !important;
        }

        /* Channel list */
        .container-1NXEtd,
        .nav-2gJm_S {
          background: transparent !important;
        }
      '';

      # Tell Discord's WebRTC engine to use PipeWire natively instead of going
      # through the PulseAudio compat layer — prevents periodic voice audio dropouts.
      xdg.configFile."vesktop/argv.json".text = builtins.toJSON [
        "--enable-features=WebRTCPipeWireCapturer"
      ];

      # Vesktop settings for transparency
      xdg.configFile."vesktop/settings.json".text = builtins.toJSON {
        transparent = true;
        enabledThemes = [ "quickCss.css" ];
        enableReactDevtools = false;
        frameless = false;
        arRPC = true;
        disableMinSize = false;
        staticTitle = false;
        checkUpdates = false;
      };
    };
  };
}
