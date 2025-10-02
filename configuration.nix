# /etc/nixos/configuration.nix
{ config, pkgs, ... }:

{
  ########################
  # Core imports & boot
  ########################
  imports = [
    ./hardware-configuration.nix
    ./Modules/Games-Programs/Steam.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  ########################
  # Host, network, locale
  ########################
  networking.hostName = "Sisyphus";
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

  ########################
  # Display stack (pure Wayland)
  ########################
  services.xserver.enable = false;      # no Xorg
  programs.xwayland.enable = true;      # XWayland for legacy apps
  programs.hyprland.enable = true;

  # SDDM on Wayland (no auto-login)
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  # Make Hyprland the default session in the greeter
  services.displayManager.defaultSession = "hyprland";

  ########################
  # Portals (non-KDE)
  ########################
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-wlr
    ];
  };

  ########################
  # Audio + permissions
  ########################
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  security.polkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  ########################
  # NVIDIA (RTX 3070)
  ########################
  services.xserver.videoDrivers = [ "nvidia" ];  # pulls NVIDIA userspace/GL
  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;                                # proprietary driver for 30-series
  };


  # Wayland/Electron/NVIDIA stability env
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "Hyprland";
    GTK_USE_PORTAL = "1";

    WLR_NO_HARDWARE_CURSORS = "1";
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  ########################
  # Printing, file manager helpers
  ########################
  services.printing.enable = true;
  services.gvfs.enable = true;       # mounting, trash, etc for Thunar
  services.tumbler.enable = true;    # thumbnails for Thunar

  ########################
  # Users, shells, packages
  ########################
  programs.zsh.enable = true;

  users.users.rock = {
    isNormalUser = true;
    description = "Rock";
    extraGroups = [ "networkmanager" "wheel" "audio" "video" ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      vscodium
      discord
      git
      fastfetch
      kitty
      home-manager
      rofi-wayland
      swappy

    ];
  };

fonts = {
  enableDefaultPackages = true;
  packages = with pkgs; [
    pkgs.nerd-fonts.jetbrains-mono
  ];
};


  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.05";
}
