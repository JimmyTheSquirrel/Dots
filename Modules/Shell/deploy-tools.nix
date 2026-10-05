# Rock's deploy / admin commands — the control panel for this repo.
#
# Split out of Modules/Shell/navi.nix, where these scripts were ~520 of its 708
# lines and so reached every host that wanted the navi cheatsheet UI.
#
# Two tiers, picked by `my.deploy-tools.admin`:
#   admin = true  (Sisyphus, the machine you deploy FROM): everything below.
#   admin = false (Kit-Kat): only system-rebuild, git-sync and nix-gc. Run on
#     her machine, system-rebuild rebuilds it IN PLACE (it matches the hostname)
#     and builds github:JimmyTheSquirrel/Dots when there is no ~/Dots there.
#     The Apollo commands stay off it: they decrypt with rock's sops key and
#     ssh in as rock, and its Apollo section only appears where they exist.
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
# Resources/Scripts/lib/ui.sh is the shared look (palette, header, boxes, gum
# prompts, spinners). It is PREPENDED to a script's text (`ui = true` below)
# rather than sourced at runtime, so shellcheck checks library + script as one
# file and there is no path to get wrong.
#
# ── The app ───────────────────────────────────────────────────────────────────
# `system-rebuild` with no arguments opens a full-screen app (Resources/Rebuild,
# Python + Textual — see its rebuild/app.py header): the same menus and jobs,
# animated, with the build drawn live from nix's own JSON log. The bash script
# hands off to it (`exec system-rebuild-tui`) and keeps everything else: the
# command line (`system-rebuild rock Asgard --boot`), `system-rebuild help`,
# and the old inline menus as `system-rebuild --classic`.
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
  flake.nixosModules.deploy-tools = { config, lib, pkgs, activeUser, ... }:
  let
    admin = config.my.deploy-tools.admin;

    uiLib = builtins.readFile ../../Resources/Scripts/lib/ui.sh;
    uiInputs = [ pkgs.gum pkgs.ncurses pkgs.coreutils ];

    scriptWith = { ui ? false }: name: runtimeInputs: pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = runtimeInputs ++ pkgs.lib.optionals ui uiInputs;
      text = pkgs.lib.optionalString ui (uiLib + "\n")
        + builtins.readFile ../../Resources/Scripts/${name}.sh;
    };
    script = scriptWith { };
    uiScript = scriptWith { ui = true; };

    apollo-resolve = script "apollo-resolve" [ pkgs.jq ];

    apollo-deploy = script "apollo-deploy" [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.openssh
      pkgs.nixos-anywhere
      apollo-resolve
    ];

    git-sync = uiScript "git-sync" [ pkgs.git ];
    nix-gc = uiScript "nix-gc" [ ];
    apollo-iso = script "apollo-iso" [ pkgs.coreutils pkgs.util-linux ];
    apollo-key = script "apollo-key" [ pkgs.coreutils pkgs.util-linux pkgs.sops ];
    apollo-connect = script "apollo-connect" [ pkgs.coreutils pkgs.openssh apollo-resolve ];

    apollo = [ apollo-iso apollo-key apollo-connect apollo-deploy ];

    # The full-screen app. Only dix, git, ssh and findmnt come from here, in
    # front of the inherited PATH like a writeShellApplication's inputs, so
    # sudo, nix, nixos-rebuild and tailscale still resolve to the system's own
    # (see the header). git-sync and nix-gc are its jobs; the apollo-* tools
    # are found on PATH, so its Apollo section only shows where they exist.
    rebuild-tui = pkgs.stdenvNoCC.mkDerivation {
      pname = "system-rebuild-tui";
      version = "1";
      src = ../../Resources/Rebuild;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = let
        python = pkgs.python3.withPackages (ps: [ ps.textual ]);
      in ''
        mkdir -p $out/share/system-rebuild $out/bin
        cp -r rebuild $out/share/system-rebuild/
        ${python}/bin/python -m compileall -q $out/share/system-rebuild
        makeWrapper ${python}/bin/python $out/bin/system-rebuild-tui \
          --add-flags "-m rebuild" \
          --prefix PYTHONPATH : $out/share/system-rebuild \
          --prefix PATH : ${lib.makeBinPath [ pkgs.dix pkgs.git pkgs.openssh pkgs.util-linux git-sync nix-gc ]}
      '';
    };

    # The home screen + menus. nom draws the live build tree, dix the package
    # diff; tailscale, nix and nixos-rebuild deliberately come from the system
    # PATH (see the header) so they match the daemons they talk to. Its Apollo
    # section shows only when apollo-deploy is on its PATH, i.e. with admin.
    system-rebuild = uiScript "system-rebuild" ([
      pkgs.jq
      pkgs.gawk
      pkgs.gnused
      pkgs.git
      pkgs.openssh
      pkgs.util-linux        # findmnt: is the Apollo stick mounted
      pkgs.nix-output-monitor
      pkgs.dix
      git-sync
      nix-gc
      rebuild-tui
    ] ++ lib.optionals admin apollo);

    commands = [ system-rebuild git-sync nix-gc ] ++ lib.optionals admin apollo;
  in {
    options.my.deploy-tools.admin = lib.mkEnableOption ''
      rock's deployer extras: the Apollo USB commands (rock's sops key, his ssh
      user) and the navi cheats for them, sops and his ssh aliases. Off, the
      host still gets system-rebuild (which then rebuilds it in place),
      git-sync and nix-gc
    '' // { default = true; };

    config.home-manager.users.${activeUser} = {
      home.packages = commands;

      # A second cheat file next to anything Modules/Shell/navi.nix ships: navi
      # reads every *.cheat under its cheats path. The first four drive the
      # commands every importer gets; the rest use rock's sops key and ssh
      # aliases, so they come with admin.
      home.file.".config/navi/cheats/dots.cheat".text = ''
        % Dots
        # Everything: rebuild this machine, deploy the others, repo + store, Apollo USB
        system-rebuild

        % Dots
        # What every system-rebuild menu item does, printed
        system-rebuild help

        % Dots
        # Full cleanup now (delete old generations, optimise store, docker prune)
        nix-gc

        % Dots
        # Commit, pull --rebase, push
        git-sync "chore: sync"
      '' + lib.optionalString admin ''

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
