{ config, pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;

    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        jdinhlife.gruvbox            # Gruvbox (Dark Soft/Medium/Hard)
        zhuangtongfa.material-theme  # One Dark Pro (backup option)
        arrterian.nix-env-selector
      ];

      userSettings = {
        # Theme — close to your screenshot
        "workbench.colorTheme" = "Gruvbox Dark Medium";

        # Disable Restricted Mode prompts
        "security.workspace.trust.enabled" = false;

        # UI polish
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
  };

  # Wayland-friendly Electron
  home.sessionVariables = { NIXOS_OZONE_WL = "1"; };

  # Make VSCodium the default editor
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
