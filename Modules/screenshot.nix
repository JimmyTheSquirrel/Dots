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

        # Fullscreen screenshot -> clipboard
        "${mainMod}, S, exec, grim - | wl-copy"

        # Active window screenshot -> clipboard
        "${mainMod} CTRL, S, exec, grim -g \"$(hyprctl activewindow -j | jq -r '.at[0]'),$(hyprctl activewindow -j | jq -r '.at[1]')+$(hyprctl activewindow -j | jq -r '.size[0]')x$(hyprctl activewindow -j | jq -r '.size[1]')\" - | wl-copy"
      ];
    };
  };
}
