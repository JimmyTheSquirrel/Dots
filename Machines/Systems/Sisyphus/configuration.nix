{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../../Modules/Config-Manager-Modules/Polkit.nix
    ../../../Modules/Config-Manager-Modules/Grub.nix
    ../../../Modules/Config-Manager-Modules/Steam.nix
    ../../../Modules/Config-Manager-Modules/Thunar.nix
    ../../../Modules/Config-Manager-Modules/Sddm.nix
    #../../../Modules/Config-Manager-Modules/arrr.nix
  ];

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    # --- Star Citizen cachix ---
    substituters = ["https://nix-citizen.cachix.org"];
    trusted-public-keys = [
      "nix-citizen.cachix.org-1:lPMkWc2X8XD4/7YPEEwXKKBg+SVbYTVrAaLA2wQTKCo="
    ];
  };

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "Sisyphus";
  networking.networkmanager.enable = true;

  # ✅ Noctalia requirements (widgets: wifi/bluetooth/power/battery)
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # --- Calendar sync for Noctalia (Google Calendar via EDS) ---
  programs.dconf.enable = true;

  time.timeZone = "Australia/Sydney";

  i18n.defaultLocale = "en_AU.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_AU.UTF-8";
    LC_IDENTIFICATION = "en_AU.UTF-8";
    LC_MEASUREMENT = "en_AU.UTF-8";
    LC_MONETARY = "en_AU.UTF-8";
    LC_NAME = "en_AU.UTF-8";
    LC_NUMERIC = "en_AU.UTF-8";
    LC_PAPER = "en_AU.UTF-8";
    LC_TELEPHONE = "en_AU.UTF-8";
    LC_TIME = "en_AU.UTF-8";
  };

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

  # ---- Graphics (AMD) ----
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Display stack: SDDM on X (stable), Hyprland Wayland session
  services.xserver.enable = true;
  services.xserver.videoDrivers = ["amdgpu"];

  services.displayManager.sddm.enable = true;
  services.displayManager.defaultSession = "hyprland";

  services.displayManager.sddm.settings = {
    General = {
      CursorTheme = "Bibata-Modern-Classic";
      CursorSize = 24;
    };
  };

  programs.hyprland.enable = true;
  programs.xwayland.enable = true;

  xdg = {
    portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-hyprland
      ];
    };

    mime = {
      enable = true;
      defaultApplications = {
        "text/plain" = ["codium.desktop"];
        "text/x-nix" = ["codium.desktop"];
        "text/markdown" = ["codium.desktop"];
        "application/json" = ["codium.desktop"];
        "application/x-yaml" = ["codium.desktop"];
        "application/toml" = ["codium.desktop"];
        "text/yaml" = ["codium.desktop"];
      };
    };
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";
    HYPRCURSOR_THEME = "Bibata-Modern-Classic";
    HYPRCURSOR_SIZE = "24";
  };

  services.xserver.xkb = {
    layout = "au";
    variant = "";
  };

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.zsh.enable = true;

  users.users.rock = {
    isNormalUser = true;
    description = "Rock";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    packages = with pkgs; [];
  };

  programs.localsend.enable = true;
  programs.localsend.openFirewall = true;

  # --- Star Citizen kernel tunables ---
  boot.kernel.sysctl = {
    "vm.max_map_count" = 16777216;
    "fs.file-max" = 524288;
  };

  # --- Star Citizen swap (32GB RAM, no extra swapDevices needed) ---
  zramSwap = {
    enable = true;
    memoryMax = 32 * 1024 * 1024 * 1024;
  };

  # ---- Packages (system-wide) ----
  environment.systemPackages = with pkgs; [
    git
    home-manager
    hyprpaper
    rofi
    grim
    slurp
    wl-clipboard
    mesa-demos
    vulkan-tools
    adw-gtk3
    swww
    btop
    discord
    spotify
    bibata-cursors
    r2modman
    gparted
    heroic
    lutris
    (prismlauncher.override {jdks = [pkgs.jdk21];})
    opencode
    feh
    # --- Star Citizen ---
    inputs.nix-citizen.packages.${pkgs.system}.rsi-launcher
  ];

  fonts = {
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.iosevka
    ];
  };

  programs.ssh.startAgent = true;

  system.stateVersion = "25.05";
}
