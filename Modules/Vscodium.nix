{ config, pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium; # or pkgs.vscode if you want MS build

    extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      arrterian.nix-env-selector
      mkhl.direnv
      catppuccin.catppuccin-vsc
    ];

    userSettings = {
      "workbench.colorTheme" = "Catppuccin Mocha";
      "window.titleBarStyle" = "custom";
      "workbench.iconTheme" = "material-icon-theme";
      "editor.cursorSmoothCaretAnimation" = "on";
      "editor.smoothScrolling" = true;
      "editor.minimap.enabled" = false;
      "workbench.list.smoothScrolling" = true;
      "workbench.tree.indent" = 14;
      "editor.roundedSelection" = true;

      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nil";
      "nix.formatterPath" = "nixfmt";
      "editor.defaultFormatter" = "jnoortheen.nix-ide";
      "[nix]" = { "editor.formatOnSave" = true; };

      "files.trimTrailingWhitespace" = true;
      "explorer.compactFolders" = false;
      "terminal.integrated.defaultProfile.linux" = "zsh";
    };
  };

  home.packages = with pkgs; [
    nil
    nixfmt-rfc-style
  ];

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };
}
