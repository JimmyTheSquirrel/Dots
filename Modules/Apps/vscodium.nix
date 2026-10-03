{ ... }: {
  flake.nixosModules.vscodium = { pkgs, activeUser, ... }: {
    # Text-ish files open in VSCodium. These belong to the editor, so they live
    # here — they used to be copy-pasted into both Modules/Desktop/niri.nix and
    # hyprland.nix, i.e. tied to the compositor rather than to whether VSCodium
    # is even installed. System-level (/etc/xdg/mimeapps.list) as before; the
    # per-user ~/.config/mimeapps.list that brave/helium write only claims the
    # browser types, and XDG falls through to this file for everything else.
    xdg.mime.defaultApplications = {
      "text/plain" = ["codium.desktop"];
      "text/x-nix" = ["codium.desktop"];
      "text/markdown" = ["codium.desktop"];
      "application/json" = ["codium.desktop"];
      "application/x-yaml" = ["codium.desktop"];
      "application/toml" = ["codium.desktop"];
      "text/yaml" = ["codium.desktop"];
    };

    home-manager.users.${activeUser} = { config, ... }:
    let
      dotsDir = "${config.home.homeDirectory}/Dots";

      # A BARE `codium` (the launcher entry, whose %F expands to nothing) opens
      # the Dots repo, which is what this editor is mostly for. Anything with
      # arguments is passed through untouched.
      #
      # This used to be an unconditional `--add-flags ~/Dots`, which hijacked
      # every call: `codium --wait <file>` as $EDITOR (git commit, sudoedit,
      # sops) opened the whole workspace next to the file, and on Kit-Kat —
      # where ~/Dots does not exist — every launch pointed at a missing folder.
      # Hence both conditions.
      vscodiumWrapped = pkgs.symlinkJoin {
        pname = pkgs.vscodium.pname;
        version = pkgs.vscodium.version;
        paths = [ pkgs.vscodium ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/codium \
            --run 'if [ "$#" -eq 0 ] && [ -d "${dotsDir}" ]; then set -- "${dotsDir}"; fi'
        '';
        meta.mainProgram = "codium";
      };
    in {
      # programs.vscodium, NOT programs.vscode with `package = vscodium`. Home
      # Manager's vscode module now ALWAYS writes Visual Studio Code's own
      # paths (~/.config/Code/User, ~/.vscode) whatever package it is handed —
      # and warned so on every build — so for as long as this used
      # programs.vscode, none of the settings or extensions below reached
      # VSCodium. programs.vscodium writes ~/.config/VSCodium/User and
      # ~/.vscode-oss/extensions.
      programs.vscodium = {
        enable = true;
        package = vscodiumWrapped;

        profiles.default = {
          extensions = with pkgs.vscode-extensions; [
            jdinhlife.gruvbox
            zhuangtongfa.material-theme
            arrterian.nix-env-selector
            bbenoist.nix
            jnoortheen.nix-ide
          ];

          userSettings = {
            "files.associations" = { "*.nix" = "nix"; };
            "workbench.colorTheme" = "Gruvbox Dark Medium";
            "security.workspace.trust.enabled" = false;
            "editor.minimap.enabled" = false;
            "editor.formatOnSave" = true;
            "[nix]" = { "editor.defaultFormatter" = "jnoortheen.nix-ide"; };
            "window.restoreWindows" = "all";

            # nix-ide → nixd. Both nil and nixd used to be installed with no
            # language server configured at all, so neither ever ran. nixd
            # rather than nil: it evaluates real Nix, so completion and hover
            # understand flakes, lib and option trees instead of just syntax.
            "nix.enableLanguageServer" = true;
            "nix.serverPath" = "nixd";
            # With the language server on, nix-ide routes format-on-save through
            # it and ignores `nix.formatterPath` — and nixd's own default is
            # nixfmt, which isn't installed. Keep alejandra by telling nixd.
            "nix.serverSettings" = {
              nixd.formatting.command = [ "alejandra" ];
            };
          };
        };
      };

      # Normal priority, beating zsh.nix's lib.mkDefault terminal editor on the
      # hosts that import this module. `--wait` so git/sudoedit/sops block until
      # the tab is closed; any argument also keeps the wrapper above from
      # opening ~/Dots alongside the file.
      home.sessionVariables = {
        EDITOR = "codium --wait";
        VISUAL = "codium --wait";
      };

      home.packages = with pkgs; [
        alejandra
        nixd
      ];
    };
  };
}
