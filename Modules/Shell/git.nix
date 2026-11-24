{ ... }:
let
  # Committer identity is per-person, not per-host, so it keys off activeUser
  # rather than hostName — every host rock logs into (Sisyphus, Asgard, the
  # Apollo stick) shares one identity, while a second person's machine
  # (Kit-Kat) must not commit under someone else's name.
  #
  # ⚠ Keep `~/.gitconfig` deleted. Git reads $XDG_CONFIG_HOME/git/config FIRST
  # and ~/.gitconfig SECOND, so the later one wins — a hand-made ~/.gitconfig
  # from 2026-03-24 silently shadowed this module for eight months and every
  # commit in this repo was authored `JimmyTheSquirrel <jimmy>`, which is not a
  # valid address. The old `email = "Rock"` here was kept "so attribution
  # doesn't change", but it had never once been in effect. The values below are
  # what the history actually uses, with a real address; the stale file is gone.
  # Check with `git config --show-origin --get-all user.email` if it ever looks
  # wrong — two lines of output means something is shadowing this again.
  identities = {
    rock = {
      name = "JimmyTheSquirrel";
      email = "emailrhysgeddes@gmail.com";
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
