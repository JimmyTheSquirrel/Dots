{ ... }: {
  flake.nixosModules.tailscale = { ... }: {
    services.tailscale = {
      enable = true;
      # Opens services.tailscale.port (UDP 41641) — verified in nixpkgs'
      # tailscale module, so no separate allowedUDPPorts entry is needed.
      openFirewall = true;
    };

    # Trust the tailscale interface so traffic isn't blocked
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
  };
}
