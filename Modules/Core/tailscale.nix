{ ... }: {
  flake.nixosModules.tailscale = { ... }: {
    services.tailscale = {
      enable = true;
      # Opens services.tailscale.port (UDP 41641) — verified in nixpkgs'
      # tailscale module, so no separate allowedUDPPorts entry is needed.
      openFirewall = true;

      # ⛔ Do NOT add extraSetFlags = [ "--hostname=..." ] here.
      #
      # It was added 2026-11-23 to stop a repeat of Elektra (registered as
      # "kit-kat", renamed to Elektra in 2026-10-09's f29ec6e, so the host
      # tables asked the tailnet for "elektra" — which did not exist — and
      # every push to her failed for six weeks). It is the wrong tool:
      # extraSetFlags builds a `tailscaled-set` unit wantedBy multi-user.target,
      # which runs `tailscale set` on every boot and every activation against an
      # ALREADY-REGISTERED node. The same line in Modules/Server/network.nix
      # renamed Asgard to "asgard-1" the day it shipped — see the ⛔ note there.
      #
      # Neither host that imports this module sets authKeyFile, so they are
      # authenticated by hand and extraUpFlags (the safe form) would be a
      # silent no-op. Tailscale already names a new node after its system
      # hostname, so nothing is lost. A rename of a LIVE node is a deliberate
      # act: do it in the admin console, which also pins the name against any
      # later client-side hostname change.
    };

    # Trust the tailscale interface so traffic isn't blocked
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
  };
}
