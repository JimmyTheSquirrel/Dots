{ config, pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;

    # HM 25.05+: settings/extensions live under a profile
    profiles.default = {
      # Extensions to install
      extensions = with pkgs.vscode-extensions; [
        jdinhlife.gruvbox
        zhuangtongfa.material-theme
        arrterian.nix-env-selector
        bbenoist.nix                # Nix syntax highlighting / language basics
        jnoortheen.nix-ide          # (optional) nicer Nix IDE features
      ];

      # Editor settings
      userSettings = {
        # Make sure *.nix is detected as Nix (declaratively)
        "files.associations" = { "*.nix" = "nix"; };

        "workbench.colorTheme" = "Gruvbox Dark Medium";
        "security.workspace.trust.enabled" = false;
        "editor.minimap.enabled" = false;

        # Optional: nicer Nix editing/formatting if using nix-ide + alejandra
        "editor.formatOnSave" = true;
        "[nix]" = {
          "editor.defaultFormatter" = "jnoortheen.nix-ide";
        };
        "nix.formatterPath" = "alejandra";
      };
    };
  };

  # Tools used by nix-ide / formatter (safe to keep here)
  home.packages = with pkgs; [
    alejandra       # Nix formatter used above
    nil nixd        # Nix language servers (nix-ide can use either)
  ];
}
