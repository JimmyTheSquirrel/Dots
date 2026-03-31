{
  config,
  pkgs,
  inputs,
  activeUser,
  ...
}: {
  imports = [
    ../../../Modules/Config-Manager-Modules/Polkit.nix
    ../../../Modules/Config-Manager-Modules/Grub.nix
    ../../../Modules/Config-Manager-Modules/Steam.nix
    ../../../Modules/Config-Manager-Modules/Thunar.nix
    ../../../Modules/Config-Manager-Modules/SDDM/Sddm.nix
  ];

  # ============================================================
  # NIX SETTINGS
  # ============================================================
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    substituters = ["https://nix-citizen.cachix.org"];
    trusted-public-keys = [
      "nix-citizen.cachix.org-1:lPMkWc2X8XD4/7YPEEwXKKBg+SVbYTVrAaLA2wQTKCo="
    ];
  };

  nixpkgs.config.allowUnfree = true;

  # ============================================================
  # SYSTEM
  # ============================================================
  system.stateVersion = "25.05";

  networking.hostName = "Odysseus";
  networking.networkmanager.enable = true;

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

  # ============================================================
  # HARDWARE
  # ============================================================
  hardware.bluetooth.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.ckb-next.enable = true;
  services.udev.packages = [pkgs.ckb-next];

  # ============================================================
  # DISPLAY & SESSION
  # ============================================================
  services.xserver.enable = true;
  services.xserver.videoDrivers = ["amdgpu"];
  services.xserver.xkb = {
    layout = "au";
    variant = "";
  };

  services.displayManager.sddm.enable = true;
  services.displayManager.defaultSession = "niri";
  services.displayManager.sddm.settings.General = {
    CursorTheme = "Bibata-Modern-Classic";
    CursorSize = 24;
  };

  programs.niri.enable = true;
  programs.xwayland.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common.default = "gtk";
  };

  xdg.mime = {
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

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";
    GTK_USE_PORTAL = "1";
  };

  # ============================================================
  # AUDIO
  # ============================================================
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ============================================================
  # SERVICES
  # ============================================================
  services.printing.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  programs.localsend.enable = true;
  programs.localsend.openFirewall = true;

  programs.ssh.startAgent = true;

  # ============================================================
  # USERS
  # ============================================================
  users.users.${activeUser} = {
    isNormalUser = true;
    description = activeUser;
    extraGroups = [
      "networkmanager"
      "wheel"
      "audio"
      "video"
      "render"
      "input"
    ];
    shell = pkgs.zsh;
    packages = [];
  };

  programs.zsh.enable = true;

  # ============================================================
  # PACKAGES
  # ============================================================
  environment.systemPackages = with pkgs; [
    # --- Core ---
    git
    home-manager
    btop

    # --- Niri / Wayland ---
    xwayland-satellite
    swww
    grim
    slurp
    wl-clipboard
    playerctl

    # --- Desktop ---
    adw-gtk3
    bibata-cursors
    xdg-user-dirs
    ckb-next

    # --- Graphics debugging ---
    mesa-demos
    vulkan-tools

    # --- Apps ---
    discord
    spotify
    gparted
    heroic
    lutris
    opencode
    (prismlauncher.override {jdks = [pkgs.jdk21];})

    # --- Star Citizen ---
    inputs.nix-citizen.packages.${pkgs.system}.rsi-launcher
  ];

  # ============================================================
  # FONTS
  # ============================================================
  fonts = {
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.iosevka
    ];
  };

  # ============================================================
  # KERNEL / PERFORMANCE
  # ============================================================
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
}
