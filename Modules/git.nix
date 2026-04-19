{ ... }: {
  flake.nixosModules.git = { activeUser, ... }: {
    home-manager.users.${activeUser} = {
      programs.git = {
        enable = true;
        settings = {
          user.name = "Rock";
          user.email = "Rock";
          init.defaultBranch = "main";
          push.autoSetupRemote = true;
          pull.rebase = false;
        };
      };
    };
  };
}
