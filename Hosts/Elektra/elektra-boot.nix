# Elektra — boot and greeter. Hers only; see Hosts/Elektra/system.nix.
{ ... }: {
  flake.nixosModules.elektra-boot = { ... }: {
    # Plymouth's initrd GPU module. Wired here rather than in Modules/Core/nvidia.nix
    # because the option is declared by Modules/Boot/plymouth.nix, and nvidia.nix
    # must stay importable on a host that has no plymouth.
    my.plymouth.initrdGpuModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

    # "Women · Umbrella" (Totoro) greeter — Modules/Boot/sddm.nix. rock's
    # Sisyphus runs nier-automata from the same module.
    my.sddm.theme = "women-umbrella";
  };
}
