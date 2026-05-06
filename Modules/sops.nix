{inputs, ...}: {
  flake.nixosModules.sops = {
    config,
    pkgs,
    ...
  }: {
    imports = [
      inputs.sops-nix.nixosModules.sops
    ];

    environment.systemPackages = with pkgs; [
      sops
      age
    ];

    sops = {
      defaultSopsFile = ../../Secrets/secrets.yaml;
      age.keyFile = "/home/rock/.config/sops/age/keys.txt";
      secrets.tailscale-auth-key = { };
    };
  };
}
