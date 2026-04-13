{ ... }: {
  flake.homeModules.git = { ... }: {
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
}
