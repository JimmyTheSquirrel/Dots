{ ... }: {
  flake.nixosModules.audio = { ... }: {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;

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
