# Modules/Home-Manager-Modules/Swaylock.nix
{pkgs, ...}: {
  home.packages = [pkgs.swaylock-effects];

  programs.swaylock = {
    enable = true;
    package = pkgs.swaylock-effects;
    settings = {
      # ── general ──────────────────────────────────────────────
      ignore-empty-password = true;
      show-failed-attempts = true;
      daemonize = true;
      screenshots = true;

      # ── effect — blur your current screen ────────────────────
      effect-blur = "7x5";
      effect-vignette = "0.5:0.5";

      # ── no clock, just date/time as text ─────────────────────
      clock = true;
      timestr = "%I:%M %p";
      datestr = "%A, %B %d";
      indicator = false;

      # ── colors — emerald theme ────────────────────────────────
      inside-color = "0d1f0dee";
      inside-clear-color = "0d1f0dee";
      inside-ver-color = "0d1f0dee";
      inside-wrong-color = "0d1f0dee";

      ring-color = "4a7c4a";
      ring-clear-color = "4a7c4a";
      ring-ver-color = "a8d8a8";
      ring-wrong-color = "c75e5e";

      line-color = "00000000";
      line-clear-color = "00000000";
      line-ver-color = "00000000";
      line-wrong-color = "00000000";

      key-hl-color = "a8d8a8";
      bs-hl-color = "c75e5e";

      text-color = "a8d8a8";
      text-clear-color = "a8d8a8";
      text-ver-color = "a8d8a8";
      text-wrong-color = "c75e5e";

      separator-color = "00000000";

      # ── layout ───────────────────────────────────────────────
      font = "JetBrainsMono Nerd Font";
      font-size = 24;
      indicator-radius = 80;
      indicator-thickness = 4;
    };
  };
}
