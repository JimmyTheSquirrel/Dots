# Desktop — everything a machine with a screen needs and a headless server does
# not. Imported by Sisyphus and Elektra; NOT by Asgard (headless) and NOT by
# Apollo (the deployer ISO carries its own trimmed-down set).
#
# Split out of Modules/Core/base.nix, which every host imports — before the
# split Asgard, a media server with no display, was building LibreOffice, Prism
# Launcher, Moonlight and four Nerd Fonts, and running CUPS and a Bluetooth
# stack, purely because base.nix was shared.
#
# Also the one home for the session plumbing that Modules/Desktop/niri.nix and
# Modules/Desktop/hyprland.nix used to each carry a copy of (X server + keymap,
# cursor/Ozone session variables, Bluetooth, hardware.graphics). Whatever is
# specific to ONE compositor — its defaultSession, its portal mapping, its own
# cursor variables — stays in that compositor's module. The greeter itself
# (SDDM enable, theme, cursor) is Modules/Boot/sddm.nix.
{ ... }: {
  flake.nixosModules.desktop = { pkgs, activeUser, ... }: {
    # Services
    services.printing.enable = true;
    services.power-profiles-daemon.enable = true;
    services.upower.enable = true;
    programs.dconf.enable = true;
    programs.localsend.enable = true;
    programs.localsend.openFirewall = true;

    # Desktop packages.
    #
    # No `discord` or `spotify` here. Both used to be listed, but the clients
    # actually launched are Vesktop (Modules/Apps/discord.nix) and the spiced
    # Spotify (Modules/Apps/spicetify.nix); the vanilla copies were only ever
    # duplicates sitting behind them in PATH.
    environment.systemPackages = with pkgs; [
      feh
      grim
      slurp
      wl-clipboard
      adw-gtk3
      bibata-cursors
      mesa-demos
      vulkan-tools
      gparted
      wowup-cf
      # Minecraft 26.2 needs Java 25 (class file 69); jdk21 kept for older instances
      (prismlauncher.override {jdks = [pkgs.jdk25 pkgs.jdk21];})
      moonlight-qt
      # Drives `apollo-deploy` (Modules/Shell/navi.nix) from this side.
      nixos-anywhere
      mpv
      imv
      libreoffice-fresh
    ];

    home-manager.users.${activeUser} = {
      # Stale Chromium/Electron profile locks from a RENAMED machine.
      #
      # Every Chromium-based app (Brave, Helium, VSCodium, Vesktop, Spotify's CEF)
      # marks its profile in use with a SingletonLock symlink to
      # "<hostname>-<pid>". A lock left behind by a crash or power cut is
      # harmless while the hostname stays the same — the app sees the pid is
      # gone and takes it over. But one carrying ANOTHER hostname reads as "in
      # use by another computer", and the app won't open (an Electron app just
      # quits) until it is unlocked by hand. Elektra was renamed from Kit-Kat
      # (2026-10-09), so on every activation — each switch, and each boot — a
      # lock naming a different host whose pid isn't running is cleared. A live
      # lock (an app started before the rename) and this host's own locks are
      # never touched.
      home.activation.staleProfileLocks = {
        after = [ "writeBoundary" ];
        before = [ ];
        data = ''
          here=$(cat /proc/sys/kernel/hostname)
          for lock in "$HOME"/.config/*/SingletonLock "$HOME"/.config/*/*/SingletonLock "$HOME"/.cache/*/SingletonLock; do
            [ -L "$lock" ] || continue
            owner=$(readlink "$lock")
            [ "''${owner%-*}" = "$here" ] && continue
            pid=''${owner##*-}
            [ -n "$pid" ] && [ -d "/proc/$pid" ] && continue
            dir=$(dirname "$lock")
            run rm -f "$dir/SingletonLock" "$dir/SingletonSocket" "$dir/SingletonCookie"
          done
        '';
      };

      # System-wide DARK MODE preference.
      #
      # This one dconf key is what `xdg-desktop-portal` serves as
      # `org.freedesktop.appearance color-scheme`, and that is what every
      # Chromium/Electron app (Helium, Vesktop, Steam's CEF) and every website's
      # `prefers-color-scheme` actually reads. Without it the portal answers
      # `uint32 0` = *no preference*, which those apps render as LIGHT.
      #
      # ⚠️ NOT the same thing as GTK's own `gtk-application-prefer-dark-theme`
      # (a settings.ini key). That one is GTK-only — portals do not read it, so
      # setting it does nothing for Chromium apps, and neither substitutes for
      # the other. This repo does not set it anywhere: the copy that used to sit
      # in Modules/Desktop/thunar.nix was written to /etc/gtk-3.0, a path GTK on
      # NixOS never reads, so it was deleted as dead.
      #
      # Lived in the since-deleted Modules/gtk.nix, which also carried
      # adw-gtk3-dark + Papirus-Dark theming that was rejected on taste
      # (2026-09-25). Deleting that module silently took dark mode with it and
      # every app went light on the next rebuild — restored here ALONE,
      # deliberately without any of the theming. Don't re-add the rest.
      dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          # Video
          "video/quicktime"   = "mpv.desktop";
          "video/mp4"         = "mpv.desktop";
          "video/x-matroska"  = "mpv.desktop";
          "video/x-msvideo"   = "mpv.desktop";
          "video/webm"        = "mpv.desktop";
          "video/mpeg"        = "mpv.desktop";
          "video/ogg"         = "mpv.desktop";
          "video/x-flv"       = "mpv.desktop";
          "video/3gpp"        = "mpv.desktop";
          # Images
          "image/jpeg"        = "imv.desktop";
          "image/png"         = "imv.desktop";
          "image/gif"         = "imv.desktop";
          "image/webp"        = "imv.desktop";
          "image/bmp"         = "imv.desktop";
          "image/tiff"        = "imv.desktop";
          # Documents
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "writer.desktop";
          "application/msword"            = "writer.desktop";
          "application/vnd.oasis.opendocument.text" = "writer.desktop";
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "calc.desktop";
          "application/vnd.ms-excel"      = "calc.desktop";
          "application/vnd.oasis.opendocument.spreadsheet" = "calc.desktop";
          "application/pdf"               = "writer.desktop";
        };
      };
    };

    # Fonts
    fonts = {
      fontconfig.enable = true;
      packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        nerd-fonts.fira-code
        nerd-fonts.iosevka
        nerd-fonts.fantasque-sans-mono
      ];
    };

    environment.sessionVariables = {
      # Force SDL apps to use PulseAudio backend (routes through pipewire-pulse).
      # Prevents old games in Steam Linux Runtime (pressure-vessel) from connecting
      # to PipeWire directly with their bundled old libpipewire, which causes
      # system-wide audio dropouts.
      SDL_AUDIODRIVER = "pulseaudio";

      # Chromium/Electron apps (Helium, Vesktop, Spotify, VSCodium) run native
      # Wayland instead of going through XWayland.
      NIXOS_OZONE_WL = "1";

      # Bibata (above) for X11/XWayland clients and anything else that reads
      # the XCURSOR_* pair. Each compositor also names it in its own config
      # (niri's `cursor { }`, Hyprland's HYPRCURSOR_*), and the greeter in
      # Modules/Boot/sddm.nix — keep all of them on the same theme and size.
      XCURSOR_THEME = "Bibata-Modern-Classic";
      XCURSOR_SIZE = "24";
    };

    # The X server is not what the desktop runs on — both compositors are
    # Wayland — but SDDM's greeter is an X11 client, so it needs one.
    # `videoDrivers` is a per-machine hardware fact and lives with the host
    # (Hosts/Sisyphus/_hardware.nix; Modules/Core/nvidia.nix on Elektra).
    services.xserver.enable = true;
    services.xserver.xkb = {
      layout = "au";
      variant = "";
    };

    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    hardware.bluetooth.settings.Policy.AutoEnable = "true";
    services.blueman.enable = true;

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}
