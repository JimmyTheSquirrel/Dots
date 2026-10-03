{inputs, ...}: {
  flake.nixosModules.sops = {
    config,
    pkgs,
    activeUser,
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
      age.keyFile = "/home/${activeUser}/.config/sops/age/keys.txt";
      secrets.tailscale-auth-key = { };
      secrets.anthropic-api-key = {
        owner = activeUser;
      };
      secrets.user-password-hash = {
        neededForUsers = true;
      };
    };
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
  # than a hand-copied age key (which is what Modules/Core/sops.nix above still needs
  # on every new machine). nixos-anywhere --extra-files plants that host key during
  # the install, so sops-nix can decrypt on the very first activation — no
  # install-then-reinstall, and nothing to copy by hand.
  flake.nixosModules.sops-kitkat = { pkgs, ... }: {
    imports = [
      inputs.sops-nix.nixosModules.sops
    ];

    environment.systemPackages = with pkgs; [
      sops
      age
    ];

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
