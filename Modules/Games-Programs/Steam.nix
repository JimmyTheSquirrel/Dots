{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;

    # ← this installs Proton GE into Steam's compat tools
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];

    # optional quality-of-life tools bundled into Steam's FHS env
    extraPackages = with pkgs; [
      mangohud
      # protontricks # if you use it
    ];
  };

  programs.gamemode.enable = true;
}
