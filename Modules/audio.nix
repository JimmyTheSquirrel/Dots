{ ... }: {
  flake.nixosModules.audio = { pkgs, ... }: {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;

    # ── Audio routing toolkit ────────────────────────────────────────────────
    # For building things like a "mic + music" virtual input: prototype the
    # graph with these, then commit the working result to Nix.
    environment.systemPackages = with pkgs; [
      # Visual patchbay — drag cables between apps and devices. It only
      # *connects* existing ports; it cannot mint a virtual device. To get one
      # to wire up, run a loopback by hand first, e.g.
      #   pw-loopback -n mic_mix --capture-props='media.class=Audio/Sink' \
      #               --playback-props='media.class=Audio/Source/Virtual'
      # then drag cables into it in qpwgraph.
      # Its saved patchbay files under ~/.config/rncbc.org are imperative state.
      qpwgraph
      # Per-app volume and routing, without the graph. pavucontrol's successor.
      pwvucontrol
      # Low-level inspector: every node's raw properties. Use it when a
      # pulse.rules / stream.rules match isn't firing and you need to see the
      # exact prop values a node was created with.
      coppwr
    ];

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.extraConfig."10-disable-bluez" = {
        "wireplumber.profiles".main = {
          "monitor.bluez" = "disabled";
          "monitor.bluez.midi" = "disabled";
        };
      };
    };
  };
}
