{ ... }: {
  flake.nixosModules.rpcs3 = { pkgs, lib, activeUser, ... }: {
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
        ryubing = {
          name = "Ryubing";
          exec = "ryubing %f";
          icon = "ryubing";
          comment = "Nintendo Switch Emulator";
          categories = [ "Game" "Emulator" ];
        };
      };

      home.activation.rpcs3Config = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if [ ! -f "$HOME/.config/rpcs3/config.yml" ]; then
          mkdir -p "$HOME/.config/rpcs3"
          cat > "$HOME/.config/rpcs3/config.yml" << 'EOF'
Core:
  PPU Decoder: LLVM Recompiler
  SPU Decoder: LLVM Recompiler
  Thread Scheduler: RPCS3 Scheduler
  SPU loop detection: true
  SPU Block Size: Safe
  Preferred SPU Threads: 0
  PPU LLVM Precompilation: true

Video:
  Renderer: Vulkan
  Resolution: 1920x1080
  Aspect ratio: 16:9
  Frame limit: Auto
  Shader Mode: Async Shader Recompiler
  VSync: false
  Resolution Scale: 100

Audio:
  Renderer: Cubeb
  Master Volume: 100
EOF
        fi
      '';
    };
  };
}
