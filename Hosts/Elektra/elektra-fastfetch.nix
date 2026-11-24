# Elektra — her terminal panel. Hers only; see Hosts/Elektra/system.nix.
#
# This builds her whole config from the universal pieces in
# Modules/Shell/fastfetch.nix (`self.lib.fastfetch`), rather than poking knobs
# into the shared module. The shared module sets its text with lib.mkDefault,
# so assigning here simply wins — no mkForce needed.
{ self, ... }: {
  flake.nixosModules.elektra-fastfetch = { activeUser, ... }: {
    home-manager.users.${activeUser}.xdg.configFile."fastfetch/config.jsonc".text =
      self.lib.fastfetch.mkConfig {
        # Her fluffy cat (2026-11-23), her pick.
        #
        # ⚠ Two things went wrong the first time, both worth remembering:
        #
        #  1. It rendered nearly FULL-SCREEN. `kitty-direct` never decodes the
        #     image, so with only a height set fastfetch cannot infer the width
        #     and the 1536x1024 source came out at roughly native size. Set
        #     BOTH for a photo. This one is 3:2 and a cell is ~2x taller than
        #     wide, so the width must stay 3x the height — scale them together
        #     or the cat stretches.
        #  2. It is redrawn on EVERY new interactive kitty shell and again on
        #     every `clear`, so a big file is a per-terminal cost, not a
        #     one-off — the same complaint that got sleepy-cat removed.
        #     Downscaled 1536x1024/2.2 MB → 600x400/308 KB.
        logo = ../../Resources/Terminal-Images/fluffy-cat.png;
        logoHeight = 12;
        logoWidth = 36;

        # Just the two sections she cares about — Software and Session dropped
        # at her request (2026-11-23). Everything those rows showed (OS,
        # kernel, shell, WM, terminal, uptime) is still a command away; this is
        # the panel she sees dozens of times a day.
        order = [ "hardware" "graphics" ];

        colors = {
          # Hardware takes the cyan that Session used to wear.
          hardware = { c = "cyan"; b = "bright_cyan"; };

          # Graphics in light purple. These are ANSI 256 codes rather than
          # colour names because no named colour is a true lavender — magenta
          # reads pink. 183 is the light lilac she picked and it is what the
          # word "Graphics" itself is drawn in (the heading renders as
          # `{#c}▌{#b}Graphics`, so `b` is the title); 141 is a slightly deeper
          # purple for the bar glyph and the second-tier rows, keeping the
          # two-tone shape every other section has.
          graphics = { c = "38;5;141"; b = "38;5;183"; };
        };
      };
  };
}
