# ============================================================================
# Luciole — the file manager on Sisyphus (replaced Thunar, 2026-11-20)
# ============================================================================
#
# noctalia-dev's own file manager, from the same family as the shell: C++23
# drawing straight onto Wayland + GLES, with no Qt, no GTK, no Quickshell and
# no QML underneath it. Grid / list / Miller-column views, tabs, split view,
# side preview.
#
# ⚠️ It is version 0.1.0 and upstream's README says in as many words that
# settings, shortcuts and behaviour may change between releases. Expect the
# `settings` block below to need revisiting after a `nix flake update`: unknown
# keys only warn and are ignored (they do not block startup), but a key whose
# *type* or accepted values changed is a hard error that fails the build-time
# `luciole config validate` in upstream's Home-Manager module. That is the
# failure mode to expect, and it fails loudly at build time rather than at
# runtime, which is why checkConfig is left on.
#
# ⚠️ Not in nixpkgs — this is a from-source meson build, and
# upstream's nix/package.nix also rebuilds gdk-pixbuf (pinned to 2.44.6 for the
# Glycin 2.1 API) and librsvg on top of it. The first build is long and there is
# no binary cache for it. See the input comment in flake.nix for why that input
# deliberately carries no `nixpkgs.follows`.
#
# ── Config ownership ───────────────────────────────────────────────────────────
# Luciole reads, in increasing precedence:
#   1. built-in defaults
#   2. ~/.config/luciole/config.toml   ← NIX OWNS THIS (the `settings` below)
#   3. ~/.config/luciole/settings.toml ← the GUI writes here, and stays writable
#
# So unlike noctalia (Claude/noctalia.md — Nix force-writes its settings.toml
# and a rebuild reverts any GUI change), Luciole has a *designed* seam for this:
# it never writes through config.toml. A GUI tweak wins over the value below and
# survives rebuilds; "Reset" in Settings drops the override and the Nix value
# applies again. Edit this file for the declarative baseline, and don't fight
# the GUI — nothing here is clobbered either way.
#
# ── Why `file-manager` and not `luciole` in the keybind ───────────────────────
# Mod+E is baked into the wrapped niri package at `perSystem` (see the header of
# Modules/Desktop/niri.nix — the baked store config is the ONLY keybind file the
# compositor reads), and that one package is shared by Sisyphus AND Apollo. A
# `lib.getExe pkgs.luciole` in there would put Luciole in the rescue ISO's
# closure and make `apollo-iso` compile a C++ file manager and a Rust librsvg it
# has no use for. So niri spawns a bare `file-manager`, and each host that
# imports niri says what that is: this module on Sisyphus, Thunar on Apollo.
# ============================================================================
{ inputs, ... }:
let
  # ── Folder shape: the icon theme, ranked by MEASURED corner radius ──────────
  # Luciole draws file and folder artwork from the desktop icon theme, which it
  # reads from GSettings `org.gnome.desktop.interface icon-theme` (its wrapper
  # carries dconf + gsettings-desktop-schemas for exactly this), falling back to
  # the icon theme named in gtk-3.0/settings.ini. This repo sets neither, which
  # is why it had been drawing the Adwaita it carries in its own wrapper.
  #
  # `radius` below is each theme's own `places/folder` SVG: the `rx` on the
  # folder body, or the arc radius in its path data, over the icon's viewBox
  # size — so the figures compare across themes drawn at different sizes.
  # Measured 2026-11-20. Lower = sharper, squarer corners.
  #
  # `follows` = the theme declares `FollowsColorScheme=true` in its
  # index.theme, so Luciole recolours its folders from the primary colour in
  # colors.toml — i.e. folders track the skwd wallpaper palette like the rest of
  # the desktop. The ones that don't keep their own hue.
  #
  # ⚠️ `numix-icon-theme-square` is NOT in this list on purpose. Its own
  # index.theme says "square APPS icons design" and it `Inherits=Numix` for
  # everything else, so its folders are plain Numix at 10.2% — SOFTER than
  # Adwaita. The name is actively misleading for this job.
  iconThemes = {
    zafiro     = { pkg = p: p.zafiro-icons;          theme = "Zafiro-icons-Dark";     radius = "1.6%"; follows = false; };
    flat-remix = { pkg = p: p.flat-remix-icon-theme; theme = "Flat-Remix-Blue-Dark";  radius = "2.8%"; follows = true;  };
    papirus    = { pkg = p: p.papirus-icon-theme;    theme = "Papirus-Dark";          radius = "4.4%"; follows = true;  };
    colloid    = { pkg = p: p.colloid-icon-theme;    theme = "Colloid-Dark";          radius = "6.8%"; follows = true;  };
    adwaita    = { pkg = p: p.adwaita-icon-theme;    theme = "Adwaita";               radius = "7.8%"; follows = false; };
    kora       = { pkg = p: p.kora-icon-theme;       theme = "kora";                  radius = "7.8%"; follows = true;  };
  };

  # Our Noctalia colour template (see its own header). Kept in the repo and
  # not taken from the package, so the chrome stays neutral while the accents
  # follow the wallpaper. Read and substituted below rather than used as a
  # path, because `my.luciole.chromeOpacity` has to reach it.
  colorsTemplateSrc = ../../Resources/Luciole/colors.toml;

  # A 0–1 opacity as the two hex digits of an #RRGGBBAA colour. Nix has no hex
  # formatter, hence the long way round. Rounds half up, clamps to the range.
  toHex2 = f:
    let
      digits = "0123456789abcdef";
      c = if f < 0.0 then 0.0 else if f > 1.0 then 1.0 else f;
      n = builtins.floor (c * 255.0 + 0.5);
    in builtins.substring (n / 16) 1 digits
     + builtins.substring (builtins.bitAnd n 15) 1 digits;

  lucioleOptions = { lib, ... }: {
    options.my.luciole.iconTheme = lib.mkOption {
      type = lib.types.enum (builtins.attrNames iconThemes);
      default = "papirus";
      description = ''
        Desktop icon theme, chosen for its FOLDER SHAPE — see the measured
        corner radii in the iconThemes table in Modules/Desktop/luciole.nix.
        Sharpest to softest: zafiro, flat-remix, papirus, colloid, adwaita, kora.

        Changing this is a one-word edit plus a rebuild and a re-login.

        ⚠️ This is not Luciole-only. It writes GNOME's `icon-theme` dconf key,
        which EVERY GTK app on the host reads. It lives in this module because
        Luciole is the reason it is set and because this module is Sisyphus-only
        — Modules/Desktop/desktop.nix would have taken Elektra with it.
      '';
    };

    options.my.luciole.chromeOpacity = lib.mkOption {
      type = lib.types.numbers.between 0.0 1.0;
      default = 0.40;
      example = 1.0;
      description = ''
        Opacity of the SEARCH FIELD and the BREADCRUMB PILL in the toolbar —
        the two controls that were the only fully opaque things in an
        otherwise translucent window (flat #2b2b2b slabs over a #0f1518 bar).
        1.0 restores upstream's look.

        Rendered into Resources/Luciole/colors.toml as the alpha pair of an
        #RRGGBBAA value for `surface_container_high`, so it reaches Luciole
        through the normal palette render — no extra reload path. Changing it
        needs a rebuild and then `noctalia-apply-palette`, because the
        TEMPLATE changes and not just the palette.

        ⚠️ That role also fills CONTEXT MENUS (no opaque plate under them),
        the status-bar pill and the row-hover highlight. Below roughly 0.6 the
        file grid starts reading through an open menu — the default IS below
        that, chosen by rock off the comparison page on 2026-11-21 with the
        trade-off known. If a menu ever reads as muddy over a busy folder, this
        is the knob, not a Luciole bug.

        This is separate from `programs.luciole.settings.browser
        .background_opacity`, which fades the window background and the file
        area. ⚠️ That one is GUI-owned and currently 0.54 on this machine —
        see Claude/luciole.md.
      '';
    };
  };
in
{
  flake.nixosModules.luciole = { pkgs, lib, config, activeUser, ... }:
  let
    luciole = inputs.luciole.packages.${pkgs.stdenv.hostPlatform.system}.default;
    icons = iconThemes.${config.my.luciole.iconTheme};

    # The template with my.luciole.chromeOpacity baked in. writeText rather
    # than the raw path so the one placeholder can be filled; it stays a store
    # path either way, so the lockedSettingsExtra rule below is unchanged.
    colorsTemplate = pkgs.writeText "luciole-colors.toml" (
      builtins.replaceStrings
        [ "@chromeAlpha@" ]
        [ (toHex2 config.my.luciole.chromeOpacity) ]
        (builtins.readFile colorsTemplateSrc)
    );
  in {
    imports = [ lucioleOptions ];

    # Trash, plus sftp:// / smb:// / dav:// in the location bar, need GVfs —
    # upstream's installation guide calls this out because its own modules
    # deliberately do not enable it. Not repeated here: Modules/Core/polkit.nix
    # already sets services.gvfs.enable unconditionally, and every host that
    # imports this module imports that one too.

    environment.systemPackages = [
      # The indirection niri's baked Mod+E resolves against. See the header.
      (pkgs.writeShellScriptBin "file-manager" ''
        exec ${lib.getExe luciole} "$@"
      '')
      # The icon theme picked by my.luciole.iconTheme. Must be a real package on
      # the system, not just a name in dconf: a name pointing at an absent theme
      # falls back silently, which is the single most likely way this looks like
      # "the setting did nothing".
      #
      # Adwaita is listed in Modules/Desktop/desktop.nix too; a duplicate entry
      # in systemPackages is harmless (same derivation, deduped), and naming it
      # here keeps the table honest rather than special-casing one value.
      (icons.pkg pkgs)
    ];

    # /etc/xdg/mimeapps.list. Replaces the thunar.desktop entry that
    # Modules/Desktop/thunar.nix sets — that module is no longer imported by
    # Sisyphus, so the two never both apply here, but note it still does on
    # Elektra, which kept Thunar.
    # ── Colours: it joins the existing pipeline, no new machinery ──────────────
    # skwd generates, noctalia fans out (Claude/noctalia.md, Modules/Desktop/skwd.nix).
    # Luciole plugs into the *second* half of that natively: it reads a
    # `colors.toml` written in noctalia's own `{{ }}` token syntax and reloads
    # it live. So this is the whole integration — one template entry, no reload
    # hook, no matugen template to keep in sync.
    #
    # (It ships a ready-made template of its own in share/luciole/templates/.
    # We use OURS instead — see input_path below for why.)
    #
    # ⚠️ Set here and NOT in Modules/Desktop/noctalia.nix's shared lockedSettings,
    # which is the whole reason `my.noctalia.lockedSettingsExtra` exists: that
    # module is imported by Elektra and Apollo, and neither has Luciole, so a
    # Luciole template in the shared lock is at best dead weight in her
    # settings.toml. It mattered more when input_path pointed INTO the Luciole
    # package — that would have dragged the whole from-source build into her
    # closure and the rescue ISO's, exactly the Mod+E trap above. It now points
    # at our own small TOML, so the closure risk is gone, but the rule stands:
    # a per-host template belongs in lockedSettingsExtra.
    #
    # ⚠️ Nix must NOT also manage ~/.config/luciole/colors.toml. noctalia writes
    # that file, and an `xdg.configFile` entry for it would put a read-only store
    # symlink in the way and make every render fail. config.toml (ours) and
    # colors.toml (noctalia's) are separate files on purpose — nothing overlaps.
    #
    # ⭐ `templates-apply` alone will NOT produce the first render — see the long
    # comment on `noctalia-apply-palette` in Modules/Desktop/noctalia.nix. Run
    # `noctalia-apply-palette` (or change the wallpaper) once after the switch;
    # re-selecting the already-selected palette is what forces the fan-out.
    #
    # Verified 2026-11-20 before committing to this: rendering the template
    # against the live ~/.config/noctalia/palettes/skwd-wall.json with
    # `noctalia theme --theme-json … -r <template>:<out>` resolved all 30 tokens
    # to the desktop's current amber palette, no placeholders left behind. Worth
    # repeating that way after a noctalia bump rather than trusting the output
    # file to look healthy — it has a static fallback like every other consumer
    # in this pipeline.
    my.noctalia.lockedSettingsExtra.theme.templates.user.luciole = {
      # ⚠️ OUR template, not the one Luciole ships. Upstream's takes every token
      # straight from the palette, surfaces included, which painted the toolbar,
      # the search field and the file area the same olive as the wallpaper
      # (#131408 on 2026-11-21). rock's call on the monitor: colour belongs in
      # the SIDEBAR, not washed over the chrome. Ours runs the surface family
      # through noctalia's `grayscale` filter — lightness kept, hue removed, so
      # the depth ramp survives — and leaves the accents alone. The header of
      # Resources/Luciole/colors.toml has the full reasoning and how to revert.
      #
      # It also carries `my.luciole.chromeOpacity` as the alpha on
      # surface_container_high, which is the second pass over the same
      # screenshot: with the tint gone, the breadcrumb pill and the search
      # field were left as the only fully opaque things in a translucent
      # window. See that option's description.
      input_path = "${colorsTemplate}";
      # noctalia expands a leading $XDG_CONFIG_HOME itself (and falls back to
      # ~/.config per the basedir spec), so this is better than hardcoding.
      output_path = "$XDG_CONFIG_HOME/luciole/colors.toml";
    };

    xdg.mime.defaultApplications = {
      "inode/directory" = [ "dev.noctalia.luciole.desktop" ];
      "application/x-directory" = [ "dev.noctalia.luciole.desktop" ];
    };

    home-manager.users.${activeUser} = {

      # ── Folder shape ────────────────────────────────────────────────────────
      # THE setting that changes how folders look. Luciole reads
      # `org.gnome.desktop.interface icon-theme` through GSettings; without it
      # it draws the Adwaita bundled in its own wrapper, whose folder corners
      # are 7.8% of the icon — the soft look this replaces.
      #
      # Merges with the `color-scheme` key the same group gets in
      # Modules/Desktop/desktop.nix; two modules writing different keys of one
      # dconf group is a plain attrset merge.
      #
      # ⚠️ Every GTK app on the host reads this key, not just Luciole. That is
      # why it is Sisyphus-only (this module) and not in desktop.nix, which
      # would have taken Elektra with it. A full adw-gtk3-dark + Papirus pass
      # over the desktop was REJECTED ON TASTE on 2026-09-25 (Claude/misc.md) —
      # this is only the icon theme, no widget theme, but if the look is wrong
      # it is this line and the enum above, not a reason to rebuild that.
      #
      # ⚠️ Takes effect on the NEXT LOGIN for already-running apps. Luciole
      # itself refreshes on a theme change while open.
      dconf.settings."org/gnome/desktop/interface".icon-theme = icons.theme;
      imports = [ inputs.luciole.homeModules.default ];

      programs.luciole = {
        enable = true;
        package = luciole;

        # Validates `settings` at build time by running the package's own
        # `luciole config validate` over the generated TOML. Keep it on: it is
        # the only thing that catches a schema change after a flake update, and
        # `validate` is strict about unknown keys where the running app is not.
        checkConfig = true;

        # Carried across from the Thunar setup this replaced
        # (Modules/Desktop/thunar.nix's thunar.xml), key for key where there is
        # an equivalent, so the swap isn't also a behaviour change:
        #   ThunarIconView            -> view_mode = "grid"
        #   misc-show-hidden-files    -> show_hidden = true
        #   misc-show-free-space      -> always_show_status_bar = true
        #   misc-folders-first        -> directories_first (already the default)
        #   misc-single-click = false -> activation_mode (already the default)
        #   misc-thumbnail-max-file-size = 0 (unlimited) -> the 1024 MiB ceiling,
        #                                the largest this accepts
        settings = {
          schema_version = 1;

          browser = {
            view_mode = "grid";
            show_hidden = true;
            always_show_status_bar = true;

            # Thumbnails: "local" skips network shares and diskless FUSE mounts
            # (rclone, sshfs). The /data mergerfs pool on Asgard is reached over
            # the network from here, so if you want thumbnails there this is the
            # knob — "all" permits any path with a filesystem presence.
            thumbnail_policy = "local";
            thumbnail_max_file_mib = 1024;

            # Explicit, never discovered. Empty means Luciole tries
            # xdg-terminal-exec, then x-terminal-emulator, then a hardcoded list
            # starting at Foot — and it cannot infer a favourite from the fact
            # that several are installed. Sisyphus uses kitty
            # (Modules/Shell/kitty.nix), so say so.
            terminal_command = "kitty";

            # Matches the 0.90 the niri window-rule used to give Thunar, but
            # done properly: this is a CLIENT-side background alpha, so only the
            # background fades. niri's `opacity` is uniform and fades the text
            # with it, which is why that rule read as "dim" rather than glassy
            # (the long comment on it in Modules/Desktop/niri.nix). There is
            # deliberately no niri opacity rule for ^dev\.noctalia\.luciole$.
            # Set this to 1.0 for a fully opaque window.
            background_opacity = 0.9;
          };
        };
      };

      # Claim org.freedesktop.FileManager1 so "Show in folder" / "Reveal in file
      # explorer" from other apps (VSCodium, browsers) opens Luciole.
      #
      # The package ships this service file under its own name,
      # dev.noctalia.luciole.FileManager1.service, exactly as Dolphin does, so
      # that it never collides with the generic file that Nautilus ships. The
      # bus keys off the `Name=` inside (which IS org.freedesktop.FileManager1),
      # not the filename, and ~/.local/share wins over every system directory —
      # so dropping it in here is upstream's documented way to pick a winner
      # (PACKAGING.md -> D-Bus activation).
      xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".source =
        "${luciole}/share/dbus-1/services/dev.noctalia.luciole.FileManager1.service";
    };
  };
}
