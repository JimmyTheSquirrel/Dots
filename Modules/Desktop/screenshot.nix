{ ... }: {
  flake.nixosModules.screenshot = { pkgs, activeUser, ... }: {
    home-manager.users.${activeUser} = {
      home.packages = with pkgs; [
        grim
        slurp
        wl-clipboard
        jq
      ];

      # The binds that use these (Mod+Shift+S region, Mod+Print screen,
      # Mod+Ctrl+S window) live in Modules/Desktop/hyprland.nix's `keybinds`,
      # with every other Hyprland bind, so the Mod+B cheatsheet lists them too.
    };
  };
}
