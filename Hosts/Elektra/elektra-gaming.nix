# Elektra — frame caps for her RTX 3070. Hers only; see Hosts/Elektra/system.nix.
{ ... }: {
  flake.nixosModules.elektra-gaming = { activeUser, ... }: {
    # For genuine D3D->Vulkan (DXVK) titles, which is most of the rest of
    # Proton. ⚠️ It is a NO-OP for PEAK (native Vulkan, see below) — it was
    # tried first and changed nothing. Do not read it as the PEAK fix.
    environment.sessionVariables.DXVK_FRAME_RATE = "60";

    home-manager.users.${activeUser} = {
      # ── Frame cap for Vulkan games ────────────────────────────────────
      #
      # ⭐ VERIFIED 2026-10-04. Before: 232-260W of a 270W cap, 79-81C, fans
      # 89-100%, util 60-100%, sw_power_cap Active. After: 56-67W, 45-48C,
      # fan 57%, util 18-41%, power cap NotActive. ~75% less power, 34C
      # cooler, confirmed audibly quiet.
      #
      # The 18-41% utilisation is the point: PEAK really is trivial for a
      # 3070. It only looked demanding because nothing capped it, so it
      # rendered ~500fps into two 60Hz panels and burned ~183 extra watts on
      # frames nobody could see.
      #
      # The cause is the GAME, not her hardware or this config. PEAK has no
      # working frame limiter — its own vsync/FPS-cap options are documented
      # by its community as having no effect (hence zero vsync keys in its
      # Proton prefix: they never get written), its default max framerate is
      # reported ~500, and Windows users report the same fans. The devs
      # acknowledged it. Official advice is to cap FPS externally.
      #
      # ⚠️ Why no driver setting can do this. Steam launches it
      # `PEAK.exe -force-vulkan`, so it is a NATIVE Vulkan client, and in
      # Vulkan the application owns the present mode — ask for
      # MAILBOX/IMMEDIATE and nothing outside the process enforces vblank.
      # __GL_SYNC_TO_VBLANK and vblank_mode are OpenGL-only.
      # `allow_tearing = false` in hyprland.nix does not help either: the
      # compositor shows 60 while the GPU still renders hundreds. And unlike
      # Mesa, which honours MESA_VK_WSI_PRESENT_MODE=fifo to override an
      # app's present mode, the NVIDIA proprietary driver has NO equivalent.
      # That asymmetry — plus rock's 182W AMD ceiling vs her 270W — is why
      # the same game behaves on his machine and screams on hers.
      #
      # So the Vulkan layer is the only place left, which is what MangoHud
      # is: fps_limit works for native Vulkan, DXVK and vkd3d alike. It
      # reaches the game because mangohud is in programs.steam.extraPackages
      # (Modules/Gaming/steam.nix), putting the layer INSIDE Steam's
      # pressure-vessel container — which is also why mangohud is not on her
      # PATH. enableSessionWide sets MANGOHUD=1 so the implicit layer loads.
      #
      # no_display keeps the overlay off — this caps frames, it is not a HUD.
      # Shift_R+F12 toggles it if she ever wants the numbers.
      #
      # ⚠️ Needs a RE-LOGIN (session vars are set at login) and a game
      # relaunch. A plain switch cannot change a running session's env.
      # ⚠️ Revisit if she ever gets a higher-refresh monitor — this would then
      # cap her below what the panel can show.
      programs.mangohud = {
        enable = true;
        enableSessionWide = true;
        settings = {
          fps_limit = 60;
          no_display = true;
        };
      };
    };
  };
}
