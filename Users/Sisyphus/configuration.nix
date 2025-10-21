{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../Modules/Config-Manager-Modules/Polkit.nix
    ../../Modules/Config-Manager-Modules/Grub.nix
    ../../Modules/Config-Manager-Modules/Steam.nix
    ../../Modules/Config-Manager-Modules/Thunar.nix
    #../../Modules/Config-Manager-Modules/Sddm.nix
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nixpkgs.config.allowUnfree = true;

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

  # ---- Graphics (AMD) ----
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # for 32-bit Vulkan/Steam etc.
  };

  # Display stack: SDDM on X (stable), Hyprland Wayland session
  services.xserver.enable = true;
  services.xserver.videoDrivers = ["amdgpu"];

  services.displayManager.sddm.enable = true;
  # services.displayManager.sddm.wayland.enable = true;
  services.displayManager.defaultSession = "hyprland";

  # Hyprland compositor available & default
  programs.hyprland.enable = true;
  programs.xwayland.enable = true;

  # Portals + system-level MIME defaults
  xdg = {
    portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-hyprland
      ];
      # xdgOpenUsePortal = true; # optional
    };

    # Make Codium the default for text files system-wide
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

  # Wayland-friendly env (keep minimal)
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # Keymap (affects SDDM/X)
  services.xserver.xkb = {
    layout = "au";
    variant = "";
  };

  # Printing
  services.printing.enable = true;

  # Audio: PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Shell: Zsh
  programs.zsh.enable = true;

  users.users.rock = {
    isNormalUser = true;
    description = "Rock";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    packages = with pkgs; [];
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
    #teamspeak3
    #wlogout
  ];

  # SSH agent convenience
  programs.ssh.startAgent = true;

  # Optional services
  # services.openssh.enable = true;

  system.stateVersion = "25.05";
}
