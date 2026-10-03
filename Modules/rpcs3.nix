{ ... }: {
  flake.nixosModules.rpcs3 = { pkgs, inputs, activeUser, ... }: {
    environment.systemPackages = with pkgs; [
      rpcs3
      ryubing
    ];

    home-manager.users.${activeUser} = {
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

      home.activation.rpcs3Config = inputs.home-manager.lib.hm.dag.entryAfter ["writeBoundary"] ''
        if [ ! -f "$HOME/.config/rpcs3/config.yml" ]; then
          mkdir -p "$HOME/.config/rpcs3"
          cat > "$HOME/.config/rpcs3/config.yml" << 'EOF'
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
EOF
        fi
      '';
    };
  };
}
