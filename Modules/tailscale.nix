{ ... }: {
  flake.nixosModules.tailscale = { config, ... }: {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      extraUpFlags = [
        "--login-server" "https://hs.bifrost-vault.com"
      ];
    };

    # Trust the tailscale interface so traffic isn't blocked
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      # Allow tailscale UDP port (just in case openFirewall doesn't cover it)
      allowedUDPPorts = [ 41641 ];
    };
  };
}
