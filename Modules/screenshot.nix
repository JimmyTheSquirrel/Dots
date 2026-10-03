{ ... }: {
  flake.nixosModules.screenshot = { pkgs, activeUser, ... }:
  let
    mainMod = "SUPER";
  in {
    home-manager.users.${activeUser} = {
      home.packages = with pkgs; [
        grim
        slurp
        wl-clipboard
        jq
      ];

      wayland.windowManager.hyprland.settings.bind = [
        # Area screenshot -> clipboard
        "${mainMod} SHIFT, S, exec, grim -g \"$(slurp)\" - | wl-copy"

        # Mod+S is NOT bound here — it is focusmonitor in
        # Modules/Desktops/hyprland.nix. Hyprland silently keeps only ONE bind
        # per key combination, so leaving a fullscreen-screenshot here would
        # make switching screens randomly take a screenshot instead.
        # Mod+Print covers fullscreen; Mod+Shift+S (region) is the useful one.
        "${mainMod}, Print, exec, grim - | wl-copy"

        # Active window screenshot -> clipboard
        "${mainMod} CTRL, S, exec, grim -g \"$(hyprctl activewindow -j | jq -r '.at[0]'),$(hyprctl activewindow -j | jq -r '.at[1]')+$(hyprctl activewindow -j | jq -r '.size[0]')x$(hyprctl activewindow -j | jq -r '.size[1]')\" - | wl-copy"
      ];
    };
  };
}
