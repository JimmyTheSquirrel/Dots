{inputs, ...}: let
  # What both modules below share: the sops-nix module itself and the CLI
  # (`sops` to edit a file, `age` for keys). Written once here; each module
  # imports it and adds only its own file, key source and secrets.
  sopsCommon = {pkgs, ...}: {
    imports = [
      inputs.sops-nix.nixosModules.sops
    ];

    environment.systemPackages = with pkgs; [
      sops
      age
    ];
  };
in {
  flake.nixosModules.sops = {
    config,
    activeUser,
    ...
  }: {
    imports = [sopsCommon];

    sops = {
      defaultSopsFile = ../../Secrets/secrets.yaml;
      age.keyFile = "/home/${activeUser}/.config/sops/age/keys.txt";
      # Consumed only on Asgard, by the second tailscaled that is the marsbar
      # node (Modules/Server/marsbar.nix). Modules/Core/tailscale.nix does not
      # read it — every other machine joins with `sudo tailscale up` by hand.
      secrets.tailscale-auth-key = { };
      # Not referenced by anything in this repo; decrypted to
      # /run/secrets/anthropic-api-key, readable by the user, for use by hand.
      secrets.anthropic-api-key = {
        owner = activeUser;
      };
      # neededForUsers: materialised in the pre-user activation stage, which is
      # what lets hashedPasswordFile below reference it.
      secrets.user-password-hash = {
        neededForUsers = true;
      };
    };

    # The login password from Secrets/secrets.yaml. Read nixpkgs'
    # update-users-groups.pl before assuming what this does, because with
    # users.mutableUsers at its default (true — no host here changes it) it is
    # much less than "the password is now declarative":
    #
    #   - The hash is applied ONLY when the account is created. For a user
    #     already in /etc/shadow, the script keeps the existing hash field
    #     (it overwrites it only when mutableUsers = false). So on Sisyphus and
    #     Asgard, which already have `rock`, this changes nothing at all:
    #     the current password stays, and `passwd` keeps working and survives
    #     rebuilds. Changing the secret does NOT change an existing password.
    #   - Its job is the fresh install: the account is born with this password
    #     instead of a locked one ("!"), provided the age key is already at
    #     age.keyFile by first activation. If it is not, sops cannot decrypt,
    #     the script warns that the file does not exist, and the account falls
    #     back to whatever else is set (nothing, i.e. a locked password, on
    #     Sisyphus).
    #
    # nixpkgs warns at eval time when a user has more than one password option,
    # so a host must not also set initialPassword — Hosts/Asgard/system.nix's
    # `initialPassword = "asgard"` has to go alongside this. hashedPasswordFile
    # would win the precedence anyway; the only thing initialPassword added was
    # a fallback for a first boot without the age key, which Asgard's ssh-key
    # login and passwordless sudo already cover.
    users.users.${activeUser}.hashedPasswordFile = config.sops.secrets.user-password-hash.path;
  };

  # Kit-Kat's secrets, in their own file encrypted to their own key.
  #
  # NOT a second recipient on Secrets/secrets.yaml: sops encrypts a whole file to
  # every recipient, so adding her machine there would hand it
  # mullvad-wg-private-key, cloudflare-tunnel, eclipse-ssh-key, anthropic-api-key
  # and tailscale-api-key — the last being an ADMIN key that can rewrite tailnet
  # ACLs and mint auth keys. A separate file keeps the blast radius to her own
  # password hash.
  #
  # Her identity is derived from the machine's ssh host key with ssh-to-age rather
  # than a hand-copied age key (which is what the `sops` module above still needs
  # on every new machine). nixos-anywhere --extra-files plants that host key during
  # the install, so sops-nix can decrypt on the very first activation — no
  # install-then-reinstall, and nothing to copy by hand.
  flake.nixosModules.sops-kitkat = { ... }: {
    imports = [ sopsCommon ];

    sops = {
      defaultSopsFile = ../../Secrets/kit-kat.yaml;
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

      # neededForUsers: materialised in the pre-user activation stage, which is
      # what lets users.users.<her>.hashedPasswordFile reference it.
      secrets.user-password-hash = {
        neededForUsers = true;
      };
    };
  };
}
