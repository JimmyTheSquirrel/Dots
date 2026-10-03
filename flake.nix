{
  description = "NixOS system + Home Manager (flake-parts)";

  inputs = {
    # --- Nixpkgs ---
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # --- Flake Parts ---
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    # --- Home Manager ---
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Desktop Shell ---
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # --- SKWD Wallpaper Selector (v1 — QuickShell; Elektra, Odysseus) ---
    # Pinned to an exact rev, not a branch. The repo's default branch is now v2,
    # so a bare `github:liixini/skwd-wall` resolves to the v2 flake and a routine
    # `nix flake update` would silently swap v1 out from under two hosts.
    skwd-wall.url = "github:liixini/skwd-wall/8799dacb8d32b15bd7bb50b72c416159d1a9d763";

    # --- SKWD Wallpaper Selector (v2 — Rust rewrite; Sisyphus) ---
    # Upstream's official NixOS support. Ships prebuilt release binaries plus
    # nixosModules.default; consumed by Modules/Skwd.nix.
    #
    # Deliberately no `inputs.nixpkgs.follows`: the binaries are autoPatchelf'd
    # against upstream's pinned nixpkgs, and matching it is what makes our
    # derivations hash-identical to the store paths upstream publishes in
    # channel.json. Overriding it turns every build into a local rebuild.
    skwd-wall-v2.url = "github:liixini/skwd-wall/nix";

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

    # --- Qylock (NieR: Automata SDDM greeter — Sisyphus) ---
    qylock = {
      url = "github:Darkkal44/qylock";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Spicetify ---
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Helium Browser ---
    helium.url = "github:amaanq/helium-flake";

    # --- Millennium (Steam client CSS/JS injector — Steam theming) ---
    # Deliberately no `inputs.nixpkgs.follows`: upstream pins an exact nixpkgs
    # commit because the Bun dependency FOD hash is sensitive to version drift.
    # Overriding it changes the bun version and breaks the fixed-output hash.
    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";

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
