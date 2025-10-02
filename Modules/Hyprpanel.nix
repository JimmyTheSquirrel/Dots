{ lib, ... }:

{
  # Clean up any bad self-referencing symlink first
  home.activation.fixHyprpanelConfig = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    CFG="$HOME/.config/hyprpanel/config.json"
    if [ -L "$CFG" ]; then
      tgt="$(readlink -f "$CFG" || true)"
      if [ ! -e "$tgt" ] || [ "$tgt" = "$CFG" ]; then rm -f "$CFG"; fi
    fi
  '';

  # Install your EXACT old files
  xdg.configFile."hyprpanel/config.json".source = ./config.json;
  xdg.configFile."hyprpanel/hyprpanel_theme.json".source = ./hyprpanel_theme.json;

  # Avoid Home-Manager’s hyprpanel service; launch it yourself (Hyprland exec-once)
  systemd.user.services.hyprpanel.Install.WantedBy = lib.mkForce [ ];
}
