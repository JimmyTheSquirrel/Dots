{ pkgs, lib, ... }:

{
  programs.hyprpanel.enable = true;
  systemd.user.services.hyprpanel.Install.WantedBy = lib.mkForce [ ];

  home.packages = with pkgs; [
    nerd-fonts.caskaydia-cove
    nerd-fonts.fantasque-sans-mono
  ];

  home.activation.fixHyprpanelFiles = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    dir="$HOME/.config/hyprpanel"
    mkdir -p "$dir"
    for f in config.json hyprpanel_theme.json modules.json modules.scss; do
      p="$dir/$f"
      if [ -L "$p" ]; then
        tgt="$(readlink -f "$p" || true)"; [ ! -e "$tgt" ] || [ "$tgt" = "$p" ] && rm -f "$p"
      fi
    done
  '';

  # USE THE MODULES FORMAT:
  xdg.configFile."hyprpanel/modules.json" = { source = ./modules.json; force = true; };
  xdg.configFile."hyprpanel/modules.scss" = { source = ./modules.scss; force = true; };

  # (comment these so there’s no confusion)
  # xdg.configFile."hyprpanel/config.json".source = ./config.json;
  # xdg.configFile."hyprpanel/hyprpanel_theme.json".source = ./hyprpanel_theme.json;
}
