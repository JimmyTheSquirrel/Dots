{ self, inputs, ... }: {
  flake.nixosModules.helium = { pkgs, activeUser, ... }: {
    home-manager.users.${activeUser} = {
      home.packages = [
        inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };
  };
}
