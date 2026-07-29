{...}: {
  flake.nixosModules.base = {
    config,
    pkgs,
    inputs,
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
      description = activeUser;
      extraGroups = ["networkmanager" "wheel" "video" "render" "input"];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII8xJxKA/gdesYlTECQmBqvqZ0XhgmA08pagXZI95cKl jimmy"
      ];
      shell = pkgs.zsh;
      packages = [];
    };

    programs.zsh.enable = true;

    # Common packages
    environment.systemPackages = with pkgs; [
      git
      home-manager
      btop
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
      (prismlauncher.override {jdks = [pkgs.jdk21];})
moonlight-qt
      nixos-anywhere
      mpv
      imv
      libreoffice-fresh
    ];

    home-manager.users.${activeUser} = {
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

    zramSwap = {
      enable = true;
      memoryMax = 32 * 1024 * 1024 * 1024;
    };
  };
}
