{
  config,
  pkgs,
  ...
}: let
  dotsDir = "${config.home.homeDirectory}/Dots";

  vscodiumWrapped = pkgs.symlinkJoin {
    # IMPORTANT: keep pname = vscodium so HM knows the config dir layout
    pname = pkgs.vscodium.pname;
    version = pkgs.vscodium.version;

    paths = [pkgs.vscodium];
    buildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/codium \
        --add-flags "${dotsDir}"
    '';
  };
in {
  programs.vscode = {
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
        "files.associations" = {"*.nix" = "nix";};

        "workbench.colorTheme" = "Gruvbox Dark Medium";
        "security.workspace.trust.enabled" = false;
        "editor.minimap.enabled" = false;

        "editor.formatOnSave" = true;
        "[nix]" = {"editor.defaultFormatter" = "jnoortheen.nix-ide";};
        "nix.formatterPath" = "alejandra";

        "window.restoreWindows" = "all";
      };
    };
  };

  home.packages = with pkgs; [
    alejandra
    nil
    nixd
  ];
}
