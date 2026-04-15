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
    ];

    # Fonts
    fonts = {
      fontconfig.enable = true;
      packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        nerd-fonts.fira-code
        nerd-fonts.iosevka
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
