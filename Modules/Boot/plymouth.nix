{ ... }: {
  flake.nixosModules.plymouth = { config, lib, ... }: {
    options.my.plymouth.initrdGpuModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "amdgpu" ];
      example = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
      description = ''
        GPU kernel modules to load in the initrd, so Plymouth gets a real
        framebuffer from the start instead of a tiny text-mode splash.

        This is an option rather than a `lib.mkDefault` list on
        `boot.initrd.kernelModules` on purpose: every host's `hardwareConfig`
        block sets `boot.initrd.kernelModules = [ ]` at normal priority, which
        would silently discard a lower-priority default and take the splash with
        it — with no error to explain why.
      '';
    };

    config = {
      boot.initrd.kernelModules = config.my.plymouth.initrdGpuModules;

      boot.plymouth = {
        enable = true;
        theme = "spinner";
      };

      # quiet   — suppress kernel log spam during boot
      # splash  — tell Plymouth to show the splash screen
      # loglevel=3 + rd.udev.log_level=3 — keep initrd quiet too
      boot.kernelParams = [ "quiet" "splash" "loglevel=3" "rd.udev.log_level=3" ];
    };
  };
}
