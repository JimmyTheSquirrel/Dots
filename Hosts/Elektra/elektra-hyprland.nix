# Elektra — her Hyprland layout and look. Hers only; see Hosts/Elektra/system.nix.
# The compositor itself is Modules/Desktop/hyprland.nix, shared.
{ ... }: {
  flake.nixosModules.elektra-hyprland = { ... }: {
    # Square corners everywhere she can see them: Hyprland windows, the
    # noctalia bar, and the lockscreen widgets each have their own radius.
    my.hyprland.rounding = 0;

    # Blur and shadows off — the cheapest per-frame GPU saving on a 60 Hz
    # NVIDIA setup with a rotated output, and she wanted the plainer look.
    my.hyprland.effects = false;

    my.hyprland = {
      # Real connector names, read from `hyprctl monitors` on the machine itself.
      # NOTE these differ from what nouveau reported on the installer ISO (DP-3 /
      # DP-4) — the proprietary nvidia driver enumerates them differently. Always
      # take these from the installed system, not from the live ISO.
      #   DP-3 = Dell U2421HE   (left)
      #   DP-2 = Philips 272V8  (right)
      monitors = [
        # transform,3 = 270 deg. The Dell is physically pivoted anticlockwise
        # (its top edge points left), so the output is counter-rotated to match.
        # Hyprland cannot detect a physical pivot — it always has to be told.
        "DP-3,1920x1080@60,0x0,1,transform,3"
        # Rotated, DP-3 occupies 1080 wide x 1920 tall — so the Philips starts at
        # x=1080, not 1920, or the mouse crosses an 840px dead gap. y=420 centres
        # the 1080-tall landscape panel against the 1920-tall portrait one.
        "DP-2,1920x1080@60,1080x420,1"
      ];

      # No window transparency at all, at her request (2026-11-23). She had
      # it dialled back once already — the shared default (0.60 / 0.75) was
      # far too see-through — and now wants every app window solid: Steam,
      # Spotify, Brave, Discord, codium, thunar.
      #
      # ⚠️ The ONLY transparent surface left on her desktop is the terminal,
      # and that does NOT come from here — it is kitty's own
      # `background_opacity = "0.70"` in Modules/Shell/kitty.nix. Raising
      # these to 1.0 therefore cannot make her terminal solid, and lowering
      # them again is the wrong lever if she ever wants see-through windows
      # back on one specific app.
      opacityLight = "1.0";
      opacityStrong = "1.0";
    };
  };
}
