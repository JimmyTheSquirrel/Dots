{ ... }: {
  flake.nixosModules.steam = { pkgs, ... }: {
    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;

      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];

      extraPackages = with pkgs; [
        mangohud
      ];

      # Override Steam's bundled old audio libraries with host versions:
      # - libpulseaudio: Steam's scout runtime ships PA 1.1 which crashes talking to pipewire-pulse
      # - pipewire: Steam/CS2 bundles old libpipewire-0.3 (protocol v4) which desynchs from
      #   the system PipeWire server and causes audio to cut out mid-session
      package = pkgs.steam.override {
        extraLibraries = _pkgs: [ _pkgs.libpulseaudio _pkgs.pipewire ];
      };
    };

    programs.gamemode.enable = true;
    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true;

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
  };
}
