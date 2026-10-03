# Sisyphus — rock's main desktop. AMD, Niri, local GRUB profile "sisyphus".
# Hardware: ./_hardware.nix.
{ self, ... }: {
  flake.nixosConfigurations.rock-Sisyphus = self.lib.mkHost {
    activeUser = "rock";
    hostName = "Sisyphus";
    stateVersion = "25.05";

    modules = [
      ./_hardware.nix

      self.nixosModules.base
      self.nixosModules.grub
      self.nixosModules.plymouth
      self.nixosModules.sddm-nier
      self.nixosModules.polkit
      self.nixosModules.thunar
      self.nixosModules.niri
      self.nixosModules.audio
      self.nixosModules.locale
      self.nixosModules.steam
      self.nixosModules.sops
      self.nixosModules.zsh
      self.nixosModules.starship
      self.nixosModules.kitty
      self.nixosModules.helium
      self.nixosModules.git
      self.nixosModules.fastfetch
      self.nixosModules.btop
      self.nixosModules.vscodium
      self.nixosModules.noctalia
      self.nixosModules.skwd
      self.nixosModules.navi
      self.nixosModules.spicetify
      self.nixosModules.discord
      self.nixosModules.tailscale
      self.nixosModules.sunshine
      # Wolf is the live Moonlight host and autostarts. Sunshine stays installed
      # with autoStart = false — the two bind the same Moonlight ports, so at most
      # one may run. See Modules/Gaming/wolf.nix.
      self.nixosModules.wolf
      self.nixosModules.rpcs3
    ];
  };
}
