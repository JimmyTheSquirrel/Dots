{ inputs, activeUser, pkgs, ... }: {
  flake.nixosModules.pi5-base = { pkgs, activeUser, ... }: {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    nixpkgs.config.allowUnfree = true;

    networking.networkmanager.enable = true;

    services.printing.enable = true;
    programs.dconf.enable = true;
    programs.ssh.startAgent = true;

    users.users.${activeUser} = {
      isNormalUser = true;
      description = activeUser;
      extraGroups = [ "networkmanager" "wheel" "video" "render" "input" ];
      shell = pkgs.zsh;
      packages = [];
    };

    programs.zsh.enable = true;

    environment.systemPackages = with pkgs; [
      git
      home-manager
      btop
      grim
      slurp
      wl-clipboard
      bibata-cursors
      moonlight-qt
    ];

    fonts = {
      fontconfig.enable = true;
      packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        nerd-fonts.fantasque-sans-mono
      ];
    };

    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc
        zlib
        openssl
        curl
      ];
    };

    boot.kernel.sysctl = {
      "vm.max_map_count" = 16777216;
    };
  };
}
