{ pkgs, lib, ... }:

{
  # Enable Hyprpanel
  programs.hyprpanel.enable = true;

  # Don’t let systemd autostart override us
  systemd.user.services.hyprpanel.Install.WantedBy = lib.mkForce [ ];

  # Fonts for Nerd icons etc
  home.packages = with pkgs; [
    nerd-fonts.caskaydia-cove
    nerd-fonts.fantasque-sans-mono
  ];

  # Always clear broken symlinks before linking
  home.activation.fixHyprpanelFiles = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    dir="$HOME/.config/hyprpanel"
    mkdir -p "$dir"
    for f in config.json hyprpanel_theme.json modules.json modules.scss; do
      p="$dir/$f"
      if [ -L "$p" ]; then
        tgt="$(readlink -f "$p" || true)"
        [ ! -e "$tgt" ] || [ "$tgt" = "$p" ] && rm -f "$p"
      fi
    done
  '';

  # Declaratively manage all four config files
  xdg.configFile."hyprpanel/config.json".source = ./config.json;
  xdg.configFile."hyprpanel/hyprpanel_theme.json".source = ./hyprpanel_theme.json;
  xdg.configFile."hyprpanel/modules.json".source = ./modules.json;
  xdg.configFile."hyprpanel/modules.scss".source = ./modules.scss;
}
