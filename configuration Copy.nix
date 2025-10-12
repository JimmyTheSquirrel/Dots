# /etc/nixos/configuration.nix
{ config, pkgs, lib, ... }:

{
  ########################
  # Core imports & boot
  ########################
  imports = [
    ./hardware-configuration.nix
    ./Modules/Games-Programs/Steam.nix
    ./Modules/Global_Modules/Grub.nix
    ./Modules/Global_Modules/Polkit.nix
    # ./Modules/Games-Programs/Spotify.nix
  ];

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
  # Display stack (Wayland + Hyprland)
  ########################
  services.xserver.enable = false;        # no Xorg
  programs.xwayland.enable = true;        # XWayland for legacy apps
  programs.hyprland.enable = true;

  # SDDM on Wayland
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.displayManager.defaultSession = "hyprland";

  ########################
  # Portals (Hyprland-friendly)
  ########################
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-hyprland
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
  # Bluetooth (off for now)
  ########################
  hardware.bluetooth.enable = false;

  ########################
  # AMD GPU (Radeon / RDNA4)
  ########################
  # Ensure the newest AMD firmware is present.
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.cpu.amd.updateMicrocode = true;

  # DO NOT load amdgpu in the initrd (stage-1) — this caused the freeze.
  # boot.initrd.kernelModules = [ "amdgpu" ];

  # New-enough kernel for RX 9000 series
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Bring KMS up safely after boot; remove these once stable.
  boot.kernelParams = [
    "amdgpu.dc=0"
    "amdgpu.aspm=0"
    # If dual monitors still race, pin modes later, e.g.:
    # "video=DP-1:2560x1080@60"
    # "video=DP-2:2560x1080@60"
  ];

  # Some DMs still read this; harmless on Wayland
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Mesa / Vulkan userspace
  hardware.graphics = {
    enable = true;
    enable32Bit = true;     # Steam/Wine
    extraPackages = with pkgs; [
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  # Wayland-friendly defaults
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "Hyprland";
    GTK_USE_PORTAL = "1";
    AMD_VULKAN_ICD = "RADV";  # prefer Mesa RADV over AMDVLK
  };

  ########################
  # Printing, file manager helpers
  ########################
  services.printing.enable = true;
  services.tumbler.enable = true;

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
    vulkan-tools
    vulkan-validation-layers
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
