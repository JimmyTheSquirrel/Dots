# Elektra — her machine (she is Kit-Kat; the user is kitkat). A separate physical box on the tailnet: NVIDIA (RTX 3070),
# Hyprland + noctalia + skwd, GRUB with the Celeste theme.
#
# The name has history: "Elektra" was first a KDE boot profile on Sisyphus's own
# disk; this box then took that slot as "Kit-Kat", and on 2026-10-09 got the name
# Elektra back (the machine — her user is still kitkat). It is real hardware,
# which is why:
#   - Modules/Boot/grub.nix is NOT imported: it hardcodes Sisyphus's root UUID and
#     emits Sisyphus's profile entries. She gets Modules/Boot/grub-celeste.nix.
#   - the disks come from disko (./_disko.nix), not hand-written fileSystems.
#   - the rest of the hardware comes from nixos-facter (./_hardware.nix +
#     ./facter.json), generated over SSH during the install (see `apollo-deploy`).
#
# Deploy:    apollo-deploy kitkat-Elektra        (first install — ERASES the disk)
# Rebuild:   system-rebuild kitkat Elektra       (from Sisyphus: pushes over the
#            tailnet; on Elektra itself: rebuilds in place — same command)
{ self, ... }: {
  flake.nixosConfigurations.kitkat-Elektra = self.lib.mkHost {
    activeUser = "kitkat";
    hostName = "Elektra";
    stateVersion = "26.05";

    modules = [
      ./_hardware.nix
      ./_disko.nix

      self.nixosModules.base
      self.nixosModules.desktop
      self.nixosModules.polkit
      self.nixosModules.nvidia
      self.nixosModules.grub-celeste
      self.nixosModules.plymouth
      self.nixosModules.sddm
      self.nixosModules.hyprland
      self.nixosModules.noctalia
      self.nixosModules.skwd
      self.nixosModules.thunar
      self.nixosModules.steam
      self.nixosModules.audio
      self.nixosModules.locale
      self.nixosModules.sops-kitkat
      self.nixosModules.zsh
      self.nixosModules.starship
      self.nixosModules.kitty
      self.nixosModules.brave
      self.nixosModules.helium
      self.nixosModules.git
      self.nixosModules.fastfetch
      self.nixosModules.btop
      self.nixosModules.vscodium
      self.nixosModules.screenshot
      self.nixosModules.navi
      self.nixosModules.deploy-tools   # admin = false in elektra-apps.nix
      self.nixosModules.spicetify
      self.nixosModules.discord
      self.nixosModules.tailscale

      # ── Hers ──────────────────────────────────────────────────────────────
      #
      # Everything specific to THIS machine lives in Hosts/Elektra/elektra-*.nix,
      # one file per topic, so it is obvious at a glance what is hers and what is
      # shared. The `elektra-` prefix is on the filenames deliberately: an editor
      # tab reading "fastfetch.nix" tells you nothing about whose it is.
      self.nixosModules.elektra-account
      self.nixosModules.elektra-apps
      self.nixosModules.elektra-boot
      self.nixosModules.elektra-fastfetch
      self.nixosModules.elektra-gaming
      self.nixosModules.elektra-hyprland
      self.nixosModules.elektra-noctalia
      self.nixosModules.elektra-peripherals

      # Deliberately NOT imported, and why:
      #   grub      — Sisyphus's multi-profile loader; she uses grub-celeste
      #   sops      — that module is keyed to rock's hand-copied age key
      #   wolf      — Docker + a render node hardcoded to Sisyphus's RX 9060 XT
      #   sunshine  — pins output_name=HDMI-A-1 and grabs the desktop cursor
      #   rpcs3     — large, needs firmware she may never want
    ];
  };
}
