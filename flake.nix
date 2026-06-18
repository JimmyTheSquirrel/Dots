{
  description = "NixOS system + Home Manager (flake-parts)";

  inputs = {
    # --- Nixpkgs ---
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # --- Flake Parts ---
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    # --- Home Manager ---
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Desktop Shell ---
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell/v4.7.1";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # --- SKWD Wallpaper Selector ---
    skwd-wall.url = "github:liixini/skwd-wall";

    # --- KDE Plasma Manager ---
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # --- Niri ---
    niri.url = "github:sodiboo/niri-flake";

    # --- Wrapper Modules ---
    wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";

# --- SDDM Theme ---
    silentSDDM = {
      url = "github:uiriansan/SilentSDDM";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Spicetify ---
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Helium Browser ---
    helium.url = "github:amaanq/helium-flake";

    # --- Secrets Management ---
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Disko (declarative disk partitioning for nixos-anywhere) ---
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Nixflix (declarative media server — arr stack + Jellyfin auto-wiring) ---
    nixflix = {
      url = "github:kiriwalawren/nixflix/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake
    { inherit inputs; }
    {
      systems = [ "x86_64-linux" ];

      imports = [
        (inputs.import-tree ./Hosts)
        (inputs.import-tree ./Modules)
      ];
    };
}
