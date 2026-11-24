# Elektra — her user account and the ssh/nix settings a push needs.
# Hers only; see Hosts/Elektra/system.nix.
{ ... }: {
  flake.nixosModules.elektra-account = { config, activeUser, ... }: {
    # Her account. Both keys must live in ONE block: two separate
    # `users.users.${activeUser}.x = …` statements are duplicate *dynamic*
    # attribute keys, which Nix refuses to merge the way it merges static ones.
    users.users.${activeUser} = {
      # base.nix sets description = activeUser, i.e. "kitkat". This is the name
      # the SDDM greeter shows her, so give it the real spelling.
      description = "Kit Kat";

      # Her login password, from Secrets/kit-kat.yaml (NOT Secrets/secrets.yaml —
      # see Modules/Core/sops.nix). This is what gives her a working password on the
      # very first boot; without it a fresh install has none at all.
      #
      # With users.mutableUsers at its default (true) the hash is applied only
      # when the account is CREATED: after the first install `passwd` works and
      # survives rebuilds, and editing the secret no longer changes anything.
      # See the comment on hashedPasswordFile in Modules/Core/sops.nix.
      hashedPasswordFile = config.sops.secrets.user-password-hash.path;
    };

    # Remote deploys push store paths over SSH, and the receiving nix daemon
    # refuses paths from a user that is not trusted:
    #   error: cannot add path ... because it lacks a signature by a trusted key
    # Asgard already carries the same line for the same reason. Easy to miss
    # because the failure only appears on the FIRST push, after the install has
    # already succeeded — and at that point fixing it needs a rebuild, which is
    # the very thing that is broken. Bootstrap out by rebuilding once ON her
    # machine from a copy of this repo.
    nix.settings.trusted-users = [ activeUser ];

    # Needed for `system-rebuild kitkat Elektra --target` to reach her. Your
    # pubkey arrives via Modules/Core/base.nix.
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };
  };
}
