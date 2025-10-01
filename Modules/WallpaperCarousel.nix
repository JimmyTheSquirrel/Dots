# Modules/WallpaperCarousel.nix
{ config, pkgs, lib, ... }:

let
  wpDir = "${config.home.homeDirectory}/Pictures/wallpapers";
in
{
  home.packages = with pkgs; [
    ags
    swww
  ];

  # --- AGS app (JS + CSS) ---
  xdg.configFile."ags/apps/wallcarousel.js".text = ''
    // ~/.config/ags/apps/wallcarousel.js
    const { execAsync } = await import('resource:///com/github/Aylur/ags/utils.js');
    const Widget = await import('resource:///com/github/Aylur/ags/widget.js');
    const App    = await import('resource:///com/github/Aylur/ags/app.js');
    const GLib   = imports.gi.GLib;

    const WALLPAPER_DIR = '${wpDir}';
    const IMG_GLOB = "\\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.avif' \\)";

    const CSS = `
    window#wallpaper-carousel {
      background: rgba(24, 26, 32, 0.92);
      border-radius: 24px;
      border: 1px solid rgba(255,255,255,0.06);
      box-shadow: 0 20px 80px rgba(0,0,0,0.45);
      padding: 22px;
    }
    .header {
      margin-bottom: 16px;
    }
    .title {
      font-size: 18px;
      font-weight: 700;
      color: #dbe2ff;
      letter-spacing: 0.2px;
    }
    .track-container {
      border-radius: 18px;
      border: 1px solid rgba(255,255,255,0.06);
      background: rgba(255,255,255,0.03);
      padding: 14px;
    }
    .row {
      /* horizontally scrollable row */
      gap: 16px;
      padding: 4px;
    }
    .thumb {
      min-width: 160px;
      min-height: 280px;
      max-width: 160px;
      max-height: 280px;
      border-radius: 18px;
      overflow: hidden;
      background: rgba(0,0,0,0.25);
      border: 1px solid rgba(255,255,255,0.06);
      transition: transform 140ms ease, border-color 140ms ease, background 140ms ease;
    }
    .thumb:hover {
      transform: translateY(-2px) scale(1.02);
      background: rgba(255,255,255,0.06);
      border-color: rgba(255,255,255,0.18);
    }
    .thumb image {
      /* make image cover */
      -gtk-icon-shadow: none;
    }
    .controls {
      margin-top: 14px;
    }
    .navbtn {
      min-width: 48px;
      min-height: 38px;
      border-radius: 12px;
      background: rgba(255,255,255,0.05);
      border: 1px solid rgba(255,255,255,0.08);
      transition: background 120ms ease, transform 120ms ease;
    }
    .navbtn:hover { background: rgba(255,255,255,0.12); transform: translateY(-1px); }
    `;

    async function listWallpapers() {
      try {
        const out = await execAsync(`bash -lc 'shopt -s nullglob; find "${WALLPAPER_DIR}" -maxdepth 2 -type f ${IMG_GLOB} | sort'`);
        return out.trim() ? out.trim().split('\\n') : [];
      } catch (e) { return []; }
    }

    async function ensureDaemon() {
      try { await execAsync('pgrep -x swww-daemon'); }
      catch (_){ await execAsync('${pkgs.swww}/bin/swww-daemon & sleep 0.3'); }
    }

    async function applyWallpaper(path) {
      await ensureDaemon();
      await execAsync(`${pkgs.swww}/bin/swww img "${path}" --transition-type grow --transition-fps 60 --transition-duration 0.9`);
    }

    function Thumb(path) {
      return Widget.Button({
        class_name: 'thumb',
        tooltip_text: path,
        on_clicked: () => applyWallpaper(path),
        child: Widget.Image({
          file: path,
          hexpand: true,
          vexpand: true,
          keep_aspect_ratio: true,
        }),
      });
    }

    // horizontal scrollable row
    async function Carousel() {
      const files = await listWallpapers();
      const row = Widget.Box({ class_name: 'row', hexpand: true });
      row.children = files.map(Thumb);

      const scroll = Widget.Scrollable({
        hscroll: 'automatic',
        vscroll: 'never',
        hexpand: true,
        child: row,
      });

      function nudge(px) {
        const adj = scroll.vscrollbar ? scroll.vscrollbar.get_adjustment() : scroll.hscrollbar.get_adjustment();
        // ^ AGS maps to GtkScrolledWindow; we want horizontal adj
        const hadj = scroll.hscrollbar.get_adjustment();
        hadj.set_value(Math.max(0, Math.min(hadj.get_upper(), hadj.get_value() + px)));
      }

      const prev = Widget.Button({ class_name: 'navbtn', child: Widget.Label({ label: '‹' }), on_clicked: () => nudge(-340) });
      const next = Widget.Button({ class_name: 'navbtn', child: Widget.Label({ label: '›' }), on_clicked: () => nudge(+340) });

      return Widget.Box({
        vertical: true,
        children: [
          Widget.Box({ class_name: 'track-container', hexpand: true, child: scroll }),
          Widget.Box({ class_name: 'controls', halign: 'center', hpack: 'center', spacing: 12, children: [ prev, next ] }),
        ],
      });
    }

    const Header = Widget.Box({
      class_name: 'header',
      children: [ Widget.Label({ label: 'Wallpaper', class_name: 'title' }) ],
    });

    const Main = Widget.Box({
      vertical: true,
      hexpand: true,
      vexpand: true,
      spacing: 10,
      children: [
        Header,
        await Carousel(),
      ],
    });

    App.config({
      style: CSS,
      windows: [
        Widget.Window({
          name: 'wallpaper-carousel',
          anchor: ['center'],
          layer: 'top',
          width: 1280,
          height: 720,
          child: Main,
        }),
      ],
    });

    App.run();
  '';

  # small launcher
  home.file.".local/bin/wallpaper-picker".text = ''
    #!/usr/bin/env bash
    mkdir -p "${wpDir}"
    ${pkgs.ags}/bin/ags -c "$HOME/.config/ags/apps/wallcarousel.js"
  '';
  home.file.".local/bin/wallpaper-picker".executable = true;

  # optional: start swww-daemon for the session
  systemd.user.services."swww-daemon" = {
    Unit = { Description = "swww wallpaper daemon"; After = [ "graphical-session.target" ]; };
    Service = { Type = "simple"; ExecStart = "${pkgs.swww}/bin/swww-daemon"; Restart = "on-failure"; };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  # optional Hyprland keybind
  wayland.windowManager.hyprland.settings.bind = [
    "SUPER, W, exec, ~/.local/bin/wallpaper-picker"
  ];
}
