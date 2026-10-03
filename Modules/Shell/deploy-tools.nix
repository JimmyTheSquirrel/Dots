# Rock's deploy / admin commands — the control panel for this repo.
#
# Split out of Modules/Shell/navi.nix, where these scripts were ~520 of its 708
# lines and so reached every host that wanted the navi cheatsheet UI — Kit-Kat
# included, where they `cd ~/Dots` (which does not exist there), decrypt with
# rock's sops key and ssh in as rock. Import this only on the machine you deploy
# FROM (Sisyphus).
#
# Every command is a pkgs.writeShellApplication rather than writeShellScriptBin:
#   - shellcheck runs at BUILD time, so a finding fails the rebuild instead of
#     surfacing as a half-run deploy;
#   - errexit/nounset/pipefail are set for you;
#   - runtimeInputs are PREPENDED to PATH, and the inherited PATH stays behind
#     them. That is load-bearing: /run/wrappers/bin/sudo (setuid, cannot come
#     from the store) and the system's own nix, nixos-rebuild and tailscale —
#     which should match the daemons they talk to — still resolve from there.
#
# The bodies live in Resources/Scripts/*.sh as plain bash: no `''${` escaping,
# editor syntax highlighting, and `shellcheck Resources/Scripts/foo.sh` works
# directly. import-tree never sees them (not .nix); builtins.readFile embeds the
# text in each script's derivation. They interpolate nothing from Nix.
#
# ── Apollo: the deployer USB ───────────────────────────────────────────────────
# Hosts/Apollo/system.nix builds the ISO. These four commands are the whole
# workflow from this side; nothing is ever initiated by the stick itself.
#
#   apollo-iso      build the ISO and copy it onto the Ventoy stick
#   apollo-key      put the tailnet auth key on the stick (from sops)
#   apollo-connect  wait for the booted stick to appear, then SSH in
#   apollo-deploy   install a host onto the booted machine (WIPES ITS DISK)
#
# plus apollo-resolve, the "which tailnet node is the live stick" lookup that
# apollo-connect and apollo-deploy share. It is only their runtime input, not a
# command on PATH.
{ ... }: {
  flake.nixosModules.deploy-tools = { pkgs, activeUser, ... }:
  let
    script = name: runtimeInputs: pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile ../../Resources/Scripts/${name}.sh;
    };

    apollo-resolve = script "apollo-resolve" [ pkgs.jq ];

    apollo-deploy = script "apollo-deploy" [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.openssh
      pkgs.nixos-anywhere
      apollo-resolve
    ];

    commands = [
      (script "system-rebuild" [ pkgs.coreutils apollo-deploy ])
      (script "git-sync" [ pkgs.git pkgs.coreutils ])
      (script "nix-gc" [ ])
      (script "apollo-iso" [ pkgs.coreutils pkgs.util-linux ])
      (script "apollo-key" [ pkgs.coreutils pkgs.util-linux pkgs.sops ])
      (script "apollo-connect" [ pkgs.coreutils pkgs.openssh apollo-resolve ])
      apollo-deploy
    ];
  in {
    home-manager.users.${activeUser} = {
      home.packages = commands;

      # A second cheat file next to anything Modules/Shell/navi.nix ships: navi
      # reads every *.cheat under its cheats path. All of these are rock-only —
      # they drive the commands above, his ~/Dots, his sops key and his ssh
      # aliases — which is why they moved here with the scripts.
      home.file.".config/navi/cheats/dots.cheat".text = ''
        % Dots
        # Everything: rebuild a system, deploy new hardware, Apollo USB
        system-rebuild

        % Dots
        # Full cleanup now (delete old generations, optimise store, docker prune)
        nix-gc

        % Dots
        # Commit, pull --rebase, push
        git-sync "chore: sync"

        % Dots
        # Open encrypted secrets (decrypts in editor, re-encrypts on save)
        sops ~/Dots/Secrets/secrets.yaml

        % SSH
        # Asgard — media server
        ssh asgard

        % SSH
        # Apollo — the booted deployer USB (waits for it to appear)
        apollo-connect

        % SSH
        # Kit-Kat — her machine
        ssh kitkat@kit-kat
      '';
    };
  };
}
