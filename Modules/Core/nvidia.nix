# NVIDIA graphics — Kit-Kat only.
#
# Every other machine in this repo is AMD, and two shared modules hardcode that:
# Modules/Desktop/niri.nix sets videoDrivers = ["amdgpu"], and
# Modules/Boot/plymouth.nix defaults its initrd GPU module to amdgpu. This module
# overrides the first; the host sets `my.plymouth.initrdGpuModules` for the
# second (deliberately host-side — see the note at the bottom).
#
# niri is wlroots-style and renders through GBM, which on the proprietary driver
# requires kernel modesetting. `hardware.nvidia.modesetting.enable` is what adds
# `nvidia-drm.modeset=1` (nixos/modules/hardware/video/nvidia.nix), so there is
# no need to repeat it in boot.kernelParams.
{ ... }: {
  flake.nixosModules.nvidia = { lib, ... }: {
    hardware.graphics = {
      enable = true;
      enable32Bit = true; # Steam / Proton
    };

    services.xserver.videoDrivers = lib.mkForce [ "nvidia" ];

    hardware.nvidia = {
      # Required for niri. Without it you get a black screen from the TTY.
      modesetting.enable = true;

      # Desktop, not a laptop: no runtime PM, and the finegrained variant needs
      # PRIME offload, which this host doesn't use.
      powerManagement.enable = false;
      powerManagement.finegrained = false;

      # NOT optional. On driver >= 560 this defaults to null and the nvidia
      # module *asserts* that you have made a choice.
      #
      # Her card is an RTX 3070 (GA104) — Ampere, so Turing-or-later, which is
      # where upstream recommends the open kernel modules. Read off the machine
      # itself over SSH from the booted Apollo stick, not guessed.
      open = true;
      nvidiaSettings = true;
    };

    # `branch` defaults to "stable", so hardware.nvidia.package is left alone —
    # upstream prefers setting the branch over pinning a package.

    # Wayland-on-NVIDIA environment. These are the settings Hyprland's own docs
    # call for on NVIDIA, and Hyprland is noticeably fussier about them than niri:
    # without GBM_BACKEND it commonly starts and renders nothing, or falls back to
    # software with the cursor as the only thing that moves.
    #
    # If the desktop misbehaves in a way that smells like GL, comment these out
    # first — they are the usual suspect, not the driver.
    environment.sessionVariables = {
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      LIBVA_DRIVER_NAME = "nvidia";
      NVD_BACKEND = "direct";
    };

  };
}
