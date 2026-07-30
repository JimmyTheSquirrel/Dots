{ self, inputs, ... }:
let
  anuratiFont = "${self}/Resources/Fonts/Anurati-Regular.otf";
in {
  flake.nixosModules.noctalia = { pkgs, activeUser, ... }: {
    imports = [ inputs.noctalia.nixosModules.default ];

    programs.noctalia = {
      enable = true;
      recommendedServices.enable = true;
    };

    home-manager.users.${activeUser} = {
      home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.anurati-font
        pkgs.playerctl
        pkgs.google-fonts
      ];

      # Declarative bar + desktop widget config — v5 reads all *.toml in
      # ~/.config/noctalia/ alphabetically and merges them.
      # GUI overrides go to ~/.local/state/noctalia/settings.toml (not here).
      home.file.".config/noctalia/nix-config.toml".text = ''
        [theme]
        dark = true

        [location]
        name = "Sydney"
        weather = true
        units = "metric"

        [shell]
        font_default = "Sans Serif"
        font_fixed = "monospace"

        [shell.panel]
        background_opacity = 0.93

        [shell.shadow]
        direction = "bottom_right"

        [bar.main]
        position = "top"
        floating = true
        background_opacity = 0.7
        margin_horizontal = 8
        margin_vertical = 8
        start = ["control-center", "workspaces"]
        center = ["media"]
        end = ["volume", "network", "bluetooth", "clock", "notifications", "tray"]

        [bar.main.monitor.HDMI-A-1]
        end = ["volume", "network", "bluetooth", "clock", "notifications"]

        [widget.workspaces]
        hide_unoccupied = true

        [widget.clock]
        format = "hh:mm a"
        use_primary_color = true

        [widget.media]
        hide_when_inactive = true
        show_album_art = true
        show_artist_first = true
        max_width = 500
        show_progress = true

        [widget.volume]
        show_on_hover = true

        [widget.network]
        show_on_hover = true

        [widget.bluetooth]
        show_on_hover = true

        [widget.tray]
        show_on_hover = true

        [desktop_widgets]
        enabled = true

        [desktop_widgets.widget.clock_main]
        type = "clock"
        output = "DP-2"
        cx = 1280.0
        cy = 540.0

        [desktop_widgets.widget.clock_hdmi]
        type = "clock"
        output = "HDMI-A-1"
        cx = 960.0
        cy = 540.0
      '';
    };
  };

  perSystem = { pkgs, system, ... }: {
    packages.anurati-font = pkgs.stdenvNoCC.mkDerivation {
      pname = "anurati-font";
      version = "1.0";
      dontUnpack = true;
      src = anuratiFont;
      installPhase = ''
        mkdir -p $out/share/fonts/opentype
        cp $src $out/share/fonts/opentype/Anurati-Regular.otf
      '';
      meta = {
        description = "Anurati - futuristic geometric display font";
        license = pkgs.lib.licenses.ofl;
      };
    };
  };
}
