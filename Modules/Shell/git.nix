{ ... }:
let
  # Committer identity is per-person, not per-host, so it keys off activeUser
  # rather than hostName — every host rock logs into (Sisyphus, Asgard, the
  # Apollo stick) shares one identity, while a second person's machine
  # (Kit-Kat) must not commit under someone else's name.
  #
  # NOTE: `email = "Rock"` is not a valid address and never has been; it is kept
  # verbatim so existing commit attribution on this repo doesn't change. Set a
  # real address here when you want to.
  identities = {
    rock = {
      name = "Rock";
      email = "Rock";
    };
    kitkat = {
      name = "Kit Kat";
      email = "kitkat@elektra.local";
    };
  };
in {
  flake.nixosModules.git = { activeUser, ... }:
  let
    me =
      identities.${activeUser}
      or {
        name = activeUser;
        email = "${activeUser}@localhost";
      };
  in {
    home-manager.users.${activeUser} = {
      programs.git = {
        enable = true;
        settings = {
          user.name = me.name;
          user.email = me.email;
          init.defaultBranch = "main";
          push.autoSetupRemote = true;
          pull.rebase = false;
        };
      };
    };
  };
}
