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
        # Modules/Desktop/hyprland.nix. Hyprland silently keeps only ONE bind
        # per key combination, so leaving a fullscreen-screenshot here would
        # make switching screens randomly take a screenshot instead.
        # Mod+Print covers fullscreen; Mod+Shift+S (region) is the useful one.
        "${mainMod}, Print, exec, grim - | wl-copy"

        # Active window screenshot -> clipboard
        #
        # grim's geometry is `X,Y WxH` — a SPACE between position and size, the
        # same shape slurp prints. This used to emit `X,Y+WxH`, which grim
        # rejects, so the bind never produced a screenshot. One hyprctl call
        # rather than four also means the window cannot move between reads.
        "${mainMod} CTRL, S, exec, grim -g \"$(hyprctl activewindow -j | jq -r '\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"')\" - | wl-copy"
      ];
    };
  };
}
