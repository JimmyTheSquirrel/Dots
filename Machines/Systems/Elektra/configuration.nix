# System config for Elektra (KDE Plasma 6 / Wayland)
{
  config,
  pkgs,
  activeUser,
  ...
}: {
  imports = [
    ../../../Modules/Config-Manager-Modules/Polkit.nix
    ../../../Modules/Config-Manager-Modules/Grub.nix
    ../../../Modules/Config-Manager-Modules/Steam.nix
    ../../../Modules/Config-Manager-Modules/Sddm.nix
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "Elektra";
  networking.networkmanager.enable = true;

  # --- Noctalia requirements ---
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
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

  # --- Graphics (AMD) ---
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  services.xserver.videoDrivers = ["amdgpu"];

  # --- Display Stack: SDDM + KDE Plasma 6 Wayland ---
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.displayManager.defaultSession = "plasma";
  services.desktopManager.plasma6.enable = true;

  # --- Portals ---
  xdg.portal = {
    enable = true;
    extraPortals = [pkgs.xdg-desktop-portal-kde];
  };

  # --- Wayland env ---
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";
  };

  services.xserver.xkb = {
    layout = "au";
    variant = "";
  };

  services.printing.enable = true;

  # --- Audio: PipeWire ---
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.zsh.enable = true;

  users.users.${activeUser} = {
    isNormalUser = true;
    description = activeUser;
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    packages = [];
  };

  programs.localsend.enable = true;
  programs.localsend.openFirewall = true;

  # --- System Packages ---
  environment.systemPackages = with pkgs; [
    git
    home-manager
    btop
    discord
    spotify
    bibata-cursors
    gparted
    (prismlauncher.override {jdks = [pkgs.jdk21];})
    opencode
    mesa-demos
    vulkan-tools
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
