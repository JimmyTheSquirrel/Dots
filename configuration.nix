# /etc/nixos/configuration.nix
{ config, pkgs, lib, ... }:

{
  ########################
  # Core imports
  ########################
  imports = [
    ./hardware-configuration.nix
    ./Modules/Games-Programs/Steam.nix
    ./Modules/Global_Modules/Grub.nix
    ./Modules/Global_Modules/Polkit.nix
  ];

  ########################
  # Host, network, locale
  ########################
  networking.hostName = "Sisyphus";
  networking.networkmanager.enable = true;

  time.timeZone = "Australia/Sydney";
  i18n.defaultLocale = "en_AU.UTF-8";


  ########################
  # Audio
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
  # AMD GPU (Radeon / RDNA4)
  ########################
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.cpu.amd.updateMicrocode = true;

  # Keep amdgpu OUT of initrd while stabilising (avoid stage-1 freezes)
  # boot.initrd.kernelModules = [ "amdgpu" ];

  # New enough kernel (has the freshest amdgpu bits)
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Xorg driver list (harmless on Wayland; some tools still read it)
  services.xserver.enable = false;
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Mesa/Vulkan userspace
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Wayland-friendly defaults (take effect once GUI is enabled)
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "Hyprland";
    GTK_USE_PORTAL = "1";
    AMD_VULKAN_ICD = "RADV";
  };

  programs.xwayland.enable = true;

  programs.hyprland.enable = true;
  services.displayManager.sddm = {
     enable = true;
     wayland.enable = true;
   };
   services.displayManager.defaultSession = "hyprland";

  ########################
  # Printing, users, packages
  ########################
  services.printing.enable = true;

  programs.zsh.enable = true;
  users.users.rock = {
    isNormalUser = true;
    description = "Rock";
    extraGroups = [ "networkmanager" "wheel" "audio" "video" ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      vscodium discord git fastfetch kitty home-manager swappy
    ];
  };

  environment.systemPackages = with pkgs; [
    efibootmgr
    vulkan-tools
    vulkan-validation-layers
    pciutils
    usbutils
    glxinfo
  ];

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [ pkgs.nerd-fonts.jetbrains-mono ];
  };

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.05";
}
