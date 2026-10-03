{ self, ... }: {
  # SSH public keys, defined once and consumed by every host that grants
  # access. base.nix installs it for the primary user; Hosts/Rescue/system.nix
  # needs the same key without importing all of base, so it lives here.
  flake.lib.sshKeys = {
    jimmy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII8xJxKA/gdesYlTECQmBqvqZ0XhgmA08pagXZI95cKl jimmy";
  };

  flake.nixosModules.base = {
    config,
    pkgs,
    inputs,
    lib,
    activeUser,
    ...
  }: let
    pkgs-unstable = import inputs.nixpkgs-unstable {
      system = pkgs.system;
      config.allowUnfree = true;
    };
  in {
    # Nix settings
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
    };

    nixpkgs.config.allowUnfree = true;

    # Networking
    networking.networkmanager.enable = true;

    # Services
    services.printing.enable = true;
    services.power-profiles-daemon.enable = true;
    services.upower.enable = true;
    programs.dconf.enable = true;
    programs.localsend.enable = true;
    programs.localsend.openFirewall = true;
    programs.ssh.startAgent = true;
    programs.ssh.extraConfig = ''
      Host asgard
        HostName 100.126.205.100
        User rock
        SetEnv TERM=xterm-256color
    '';

    # User
    users.users.${activeUser} = {
      isNormalUser = true;
      # mkDefault so a host can give the account a real display name (the SDDM
      # greeter shows this) without needing mkForce.
      description = lib.mkDefault activeUser;
      extraGroups = ["networkmanager" "wheel" "video" "render" "input"];
      openssh.authorizedKeys.keys = [
        self.lib.sshKeys.jimmy
      ];
      shell = pkgs.zsh;
      packages = [];
    };

    programs.zsh.enable = true;

    # Common packages
    environment.systemPackages = with pkgs; [
      git
      home-manager
      feh
      grim
      slurp
      wl-clipboard
      adw-gtk3
      bibata-cursors
      mesa-demos
      vulkan-tools
      discord
      spotify
      gparted
      pkgs-unstable.claude-code
      wowup-cf
      # Minecraft 26.2 needs Java 25 (class file 69); jdk21 kept for older instances
      (prismlauncher.override {jdks = [pkgs.jdk25 pkgs.jdk21];})
      moonlight-qt
      nixos-anywhere
      mpv
      imv
      libreoffice-fresh
    ];

    home-manager.users.${activeUser} = {
      # System-wide DARK MODE preference.
      #
      # This one dconf key is what `xdg-desktop-portal` serves as
      # `org.freedesktop.appearance color-scheme`, and that is what every
      # Chromium/Electron app (Helium, Vesktop, Steam's CEF) and every website's
      # `prefers-color-scheme` actually reads. Without it the portal answers
      # `uint32 0` = *no preference*, which those apps render as LIGHT.
      #
      # ⚠️ NOT the same key as `gtk-application-prefer-dark-theme` in
      # Modules/thunar.nix. That one is GTK-only — portals do not read it, so
      # setting it does nothing for Chromium apps. Both are needed, and neither
      # substitutes for the other.
      #
      # Lived in the since-deleted Modules/gtk.nix, which also carried
      # adw-gtk3-dark + Papirus-Dark theming that was rejected on taste
      # (2026-09-25). Deleting that module silently took dark mode with it and
      # every app went light on the next rebuild — restored here ALONE,
      # deliberately without any of the theming. Don't re-add the rest.
      #
      # Harmless on Elektra: xdg-desktop-portal-kde sources its scheme from
      # KDE's own settings (kde.nix sets colorScheme = BreezeDark).
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

    # Performance
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc
        zlib
        openssl
        curl
        icu
      ];
    };

    # Force SDL apps to use PulseAudio backend (routes through pipewire-pulse).
    # Prevents old games in Steam Linux Runtime (pressure-vessel) from connecting
    # to PipeWire directly with their bundled old libpipewire, which causes
    # system-wide audio dropouts.
    environment.sessionVariables.SDL_AUDIODRIVER = "pulseaudio";

    boot.kernel.sysctl = {
      "vm.max_map_count" = 16777216;
      "fs.file-max" = 524288;
    };

    # Do NOT add `kernel.split_lock_mitigate = 0` here expecting it to help the
    # `took a bus_lock trap` spam from Steam/Spotify. Checked against the 6.18
    # source (arch/x86/kernel/cpu/bus_lock.c): these AMD CPUs raise #DB and land
    # in handle_bus_lock(), which in sld_warn state only calls
    # pr_warn_ratelimited(). The sysctl is read exclusively by split_lock_warn()
    # — the #AC split-lock path — so it is a no-op here. Discriminate by the log
    # prefix: "#DB ... bus_lock trap" is unaffected, "#AC ... split_lock trap"
    # is not. Only `split_lock_detect=off` as a kernelParam silences #DB, and
    # the traps cost ~microseconds each, so that is log hygiene, not a fix.

    zramSwap = {
      enable = true;
      memoryMax = 32 * 1024 * 1024 * 1024;
    };
  };
}
