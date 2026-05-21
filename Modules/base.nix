{...}: {
  flake.nixosModules.base = {
    pkgs,
    activeUser,
    inputs,
    ...
  }: {
    # Nix settings
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      substituters = ["https://nix-citizen.cachix.org"];
      trusted-public-keys = [
        "nix-citizen.cachix.org-1:lPMkWc2X8XD4/7YPEEwXKKBg+SVbYTVrAaLA2wQTKCo="
      ];
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

    # User
    users.users.${activeUser} = {
      isNormalUser = true;
      description = activeUser;
      extraGroups = ["networkmanager" "wheel" "video" "render" "input"];
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
      claude-code
      wowup-cf
      (prismlauncher.override {jdks = [pkgs.jdk21];})
      inputs.nix-citizen.packages.${pkgs.stdenv.hostPlatform.system}.rsi-launcher
      moonlight-qt
      nixos-anywhere
      mpv
      imv
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
