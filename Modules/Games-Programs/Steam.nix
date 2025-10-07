{ config, pkgs, ... }:

{
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;

    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];

    extraPackages = with pkgs; [
      mangohud
      # protontricks  # Uncomment if needed
    ];
  };

  programs.gamemode.enable = true;

  hardware.graphics.enable = true;  # updated here

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia.modesetting.enable = true;

  environment.systemPackages = with pkgs; [
    steam-run
    vulkan-loader
    vulkan-tools
    vulkan-validation-layers
  ];

  networking.firewall.allowedTCPPorts = [
    27014 27015 27036 27037 27038 27039 27040 27041
    27042 27043 27044 27045 27046 27047
  ];

  networking.firewall.allowedUDPPorts = [
    27000 27001 27002 27003 27004 27005
    27020 27021 27022 27023 27024 27025
    27026 27027 27028 27029 27030
  ];
}
