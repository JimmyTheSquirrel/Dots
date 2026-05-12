{ ... }: {
  flake.nixosModules.plymouth = { pkgs, ... }: {
    # Early KMS for AMD GPU — Plymouth gets a real framebuffer from the start
    # Without this you get a tiny low-res text-mode splash
    boot.initrd.kernelModules = [ "amdgpu" ];

    boot.plymouth = {
      enable = true;
      theme = "spinner";
    };

    # quiet   — suppress kernel log spam during boot
    # splash  — tell Plymouth to show the splash screen
    # loglevel=3 + rd.udev.log_level=3 — keep initrd quiet too
    boot.kernelParams = [ "quiet" "splash" "loglevel=3" "rd.udev.log_level=3" ];
  };
}
