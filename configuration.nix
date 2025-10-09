# /etc/nixos/configuration.nix
{ config, pkgs, ... }:

{
  ########################
  # Core imports & boot
  ########################
  imports = [
    ./hardware-configuration.nix
    ./Modules/Games-Programs/Steam.nix
    ./Modules/Global_Modules/Grub.nix
    ./Modules/Global_Modules/Polkit.nix
   #./Modules/Games-Programs/Spotify.nix
  ];

  #boot.loader.systemd-boot.enable = true;
  #boot.loader.efi.canTouchEfiVariables = true;

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

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

########################
# AMD GPU (Radeon / amdgpu)
########################
services.xserver.videoDrivers = [ "amdgpu" ];

hardware.graphics = {
  enable = true;
  enable32Bit = true;     # Steam/Wine 32-bit
  extraPackages = with pkgs; [
    vaapiVdpau
    libvdpau-va-gl
    # optional Vulkan OpenCL/ROCm pieces if you use them:
    # rocmPackages.clr.icd
  ];
};

# Wayland-friendly defaults (keep the Wayland bits, drop NVIDIA-specific ones)
environment.sessionVariables = {
  NIXOS_OZONE_WL = "1";
  ELECTRON_OZONE_PLATFORM_HINT = "auto";
  XDG_SESSION_TYPE = "wayland";
  XDG_CURRENT_DESKTOP = "Hyprland";
  GTK_USE_PORTAL = "1";
  # Do NOT set any NVIDIA vars; no WLR_NO_HARDWARE_CURSORS override needed for AMD
};

  ########################
  # Printing, file manager helpers
  ########################
  services.printing.enable = true;
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
      swappy
    ];
  };

environment.systemPackages = with pkgs; [
  efibootmgr
];

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
