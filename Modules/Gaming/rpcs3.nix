{ ... }: {
  flake.nixosModules.rpcs3 = { pkgs, activeUser, ... }: {
    environment.systemPackages = with pkgs; [
      rpcs3
      ryubing
    ];

    # `lib` here is Home Manager's (it carries lib.hm.dag). This used to reach
    # for inputs.home-manager.lib.hm.dag instead, which works but bypasses the
    # lib the module system already hands every HM module.
    home-manager.users.${activeUser} = { lib, ... }:
    let
      # First-run defaults only — written when there is no config yet, never
      # over one, so anything changed in RPCS3's own settings UI sticks. A store
      # file so it can be installed through `run` (Home Manager's dry-run-aware
      # wrapper), which cannot wrap the heredoc redirect this used to be.
      seed = pkgs.writeText "rpcs3-config.yml" ''
Core:
  PPU Decoder: Recompiler (LLVM)
  SPU Decoder: Recompiler (LLVM)
  Thread Scheduler: RPCS3 Scheduler
  SPU loop detection: true
  SPU Block Size: Safe
  Preferred SPU Threads: 0
  PPU LLVM Precompilation: true

Video:
  Renderer: Vulkan
  Shader Mode: Async Shader Recompiler
  VSync: false

Audio:
  Renderer: Cubeb
  Master Volume: 100
      '';
    in {
      xdg.desktopEntries = {
        rpcs3 = {
          name = "RPCS3";
          exec = "rpcs3 %f";
          icon = "rpcs3";
          comment = "PlayStation 3 Emulator";
          categories = [ "Game" "Emulator" ];
        };
        # ⚠️ No entry for the Switch emulator. There used to be one with
        # `exec = "ryubing %f"`, which could never have worked — the package's
        # binaries are `Ryujinx`, `ryujinx` and `Ryujinx.sh`; there is no
        # `ryubing` executable. It is redundant as well: the package already
        # ships share/applications/Ryujinx.desktop (Exec=Ryujinx.sh %f,
        # StartupWMClass=Ryujinx, with the NX mime types).
      };

      home.activation.rpcs3Config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "$HOME/.config/rpcs3/config.yml" ]; then
          run mkdir -p "$HOME/.config/rpcs3"
          run install -m 0644 ${seed} "$HOME/.config/rpcs3/config.yml"
        fi
      '';
    };
  };
}
