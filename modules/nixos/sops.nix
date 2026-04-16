{ inputs, ... }: {
  flake.nixosModules.sops = { config, pkgs, ... }: {
    imports = [
      inputs.sops-nix.nixosModules.sops
    ];

    environment.systemPackages = with pkgs; [
      sops
      age
    ];

    sops = {
      defaultSopsFile = ../../secrets/secrets.yaml;
      age.keyFile = "/home/rock/.config/sops/age/keys.txt";

      # Example secrets - uncomment and modify as needed:
      # secrets.example-api-key = { };
      # secrets.another-secret = {
      #   owner = "rock";  # set owner if a user service needs it
      # };
    };
  };
}
