{ config, pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;

    extensions = with pkgs.vscode-extensions; [
      jdinhlife.gruvbox            # Gruvbox (Dark Soft/Medium/Hard)
      zhuangtongfa.material-theme  # One Dark Pro (backup option)
      arrterian.nix-env-selector
      mkhl.direnv
    ];

    userSettings = {
      # Theme — close to your screenshot
      "workbench.colorTheme" = "Gruvbox Dark Medium";  # try "Gruvbox Dark Soft" if you prefer

      # Disable Restricted Mode prompts
      "security.workspace.trust.enabled" = false;

      # Small UI/QoL
      "editor.minimap.enabled" = false;
      "editor.smoothScrolling" = true;
      "editor.cursorSmoothCaretAnimation" = "on";
      "workbench.list.smoothScrolling" = true;
      "workbench.tree.indent" = 14;
      "editor.roundedSelection" = true;
      "files.trimTrailingWhitespace" = true;
      "explorer.compactFolders" = false;
      "terminal.integrated.defaultProfile.linux" = "zsh";
    };
  };

  home.packages = with pkgs; [
    direnv
  ];

  home.sessionVariables = { NIXOS_OZONE_WL = "1"; };

  xdg = {
    enable = true;
    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/plain"         = [ "codium.desktop" ];
        "text/x-nix"         = [ "codium.desktop" ];
        "application/json"   = [ "codium.desktop" ];
        "text/markdown"      = [ "codium.desktop" ];
        "application/x-yaml" = [ "codium.desktop" ];
        "application/toml"   = [ "codium.desktop" ];
      };
    };
  };
}
