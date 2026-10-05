// theme.js — the HUD's colour, picked per browser.
//
// The dashboard ships in mint (asgard.css's tokens; hud.py's artwork). Pick
// another colour and this derives the whole palette from it — the HUD's two
// lights and its bright, the six data slots, every glow and line (they are
// all rgb(var(--hud-rgb) / …)) — and redraws the three pieces of artwork
// that carry colour (the panel frame, Yggdrasil, the logo) from the
// templates hud.py writes (tpl.js).
//
// It runs in <head>, before the page paints, so there's no flash of mint:
// the palette is computed from the stored colour, and the redrawn artwork
// is kept in localStorage beside it (keyed to the HUD's build, so a new
// build redraws it once). tpl.js is fetched only when a colour is picked —
// a browser that keeps the default never downloads it.
//
// The choice lives in THIS browser (localStorage): a viewer's preference,
// nothing on the server changes, and Reset goes back to the default. If
// storage is off (a private window) the picker still works for the visit.
//
// The picker replaces Glance's own theme picker (its presets fight
// asgard.css; asgard.css hides it): a swatch button at the end of the
// navigation bar, and a row in the phone's menu.
(function () {
  "use strict";

  var me = document.currentScript;
  var DEFAULT = (me && me.getAttribute("data-default")) || "#3be8a8";
  var BUILD = (me && me.getAttribute("data-hud")) || "";
  var TPL_URL = me && me.getAttribute("data-tpl");
  var KEY = "asgard-hud-colour", ART = "asgard-hud-art";
  var PRESETS = [
    ["Mint", "#3be8a8"], ["Cyan", "#22d3ee"], ["Ice", "#6cb6ff"], ["Violet", "#a78bfa"],
    ["Magenta", "#f05ad8"], ["Red", "#ff4d5e"], ["Orange", "#ff8a3d"], ["Amber", "#ffc02e"],
    ["Lime", "#a3e635"], ["Steel", "#b8c4cf"],
  ];
  var PROPS = ["--hud", "--hud2", "--hud-hot", "--hud-deep", "--hud-rgb", "--hud2-rgb",
    "--s1", "--s2", "--s3", "--s4", "--s5", "--s6", "--h-frame", "--h-ygg"];
  var root = document.documentElement;

  function get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function set(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { /* private window */ } }

  // ── colour ──────────────────────────────────────────────────────────────────
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function rgb(hex) {
    var h = String(hex).replace("#", "");
    if (h.length === 3) h = h.replace(/./g, "$&$&");
    var n = parseInt(h, 16);
    return [n >> 16 & 255, n >> 8 & 255, n & 255];
  }
  function hex(c) {
    return "#" + c.map(function (v) { return ("0" + Math.round(clamp(v, 0, 255)).toString(16)).slice(-2); }).join("");
  }
  function toHsl(c) {
    var r = c[0] / 255, g = c[1] / 255, b = c[2] / 255;
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn, h = 0, s = 0;
    if (d) {
      s = d / (1 - Math.abs(2 * l - 1));
      h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
      h *= 60;
    }
    return [(h + 360) % 360, s, l];
  }
  function hsl(h, s, l) {
    h = ((h % 360) + 360) % 360; s = clamp(s, 0, 1); l = clamp(l, 0, 1);
    var c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = l - c / 2, r, g, b;
    if (h < 60) { r = c; g = x; b = 0; } else if (h < 120) { r = x; g = c; b = 0; } else if (h < 180) { r = 0; g = c; b = x; }
    else if (h < 240) { r = 0; g = x; b = c; } else if (h < 300) { r = x; g = 0; b = c; } else { r = c; g = 0; b = x; }
    return hex([(r + m) * 255, (g + m) * 255, (b + m) * 255]);
  }

  // The palette from one colour. Its lightness is held in a band that reads
  // on the dark panels (a near-black pick would vanish). The HUD's second
  // light sits a little round the wheel (hue +22); the other series are near
  // neighbours — +35, and a paler −18 — so a pick stays one family: orange
  // gets yellow and salmon, not the default's mint→lime jump of −74 (which
  // turns orange's second series magenta) or a red that reads as an error.
  function palette(pick) {
    var p = toHsl(rgb(pick)), H = p[0], S = p[1], L = clamp(p[2], 0.52, 0.74);
    return {
      "--hud": hsl(H, S, L),
      "--hud2": hsl(H + 22, S, L * 0.92),
      "--hud-hot": hsl(H, S, Math.min(0.9, L + 0.2)),
      "--hud-deep": hsl(H, S * 0.6, 0.14),
      "--s1": hsl(H, S, L),
      "--s2": hsl(H + 35, S, L),
      "--s3": hsl(H - 18, S * 0.8, Math.min(0.84, L + 0.12)),
      "--s4": hsl(H - 12, S * 0.45, L * 0.72),
      "--s5": hsl(H, S, Math.min(0.88, L + 0.22)),
      "--s6": hsl(H + 8, S, L * 0.6),
    };
  }

  // ── the artwork ─────────────────────────────────────────────────────────────
  function fill(t, p) {
    return t.replace(/__A__/g, p["--hud"]).replace(/__H__/g, p["--hud-hot"])
      .replace(/__B__/g, p["--hud2"]).replace(/__D__/g, "#14181c");
  }
  function dataUrl(svg) { return "data:image/svg+xml," + encodeURIComponent(svg); }
  function draw(pick, p) {
    var T = window.HUD_TPL;
    if (!T) return null;
    var art = { b: BUILD, c: pick, frame: dataUrl(fill(T.frame, p)), ygg: dataUrl(fill(T.ygg, p)), logo: dataUrl(fill(T.logo, p)) };
    set(ART, JSON.stringify(art));
    return art;
  }
  function stored(pick) {
    try {
      var a = JSON.parse(get(ART) || "null");
      return a && a.b === BUILD && a.c === pick ? a : null;
    } catch (e) { return null; }
  }
  var tplLoading = null;
  function withTemplates(fn) {
    if (window.HUD_TPL) return fn();
    if (!TPL_URL) return;
    if (!tplLoading) {
      tplLoading = [];
      var s = document.createElement("script");
      s.src = TPL_URL;
      s.onload = function () { var q = tplLoading; tplLoading = null; q.forEach(function (f) { f(); }); };
      document.head.appendChild(s);
    }
    tplLoading.push(fn);
  }

  // ── applying it ─────────────────────────────────────────────────────────────
  var current = DEFAULT, logoArt = null;
  function useArt(a) {
    root.style.setProperty("--h-frame", 'url("' + a.frame + '")');
    root.style.setProperty("--h-ygg", 'url("' + a.ygg + '")');
    logoArt = a.logo;
    paintLogo();
  }
  function paintLogo() {
    var img = document.querySelector(".logo img");
    if (!img) return;
    if (!img.hasAttribute("data-src")) img.setAttribute("data-src", img.getAttribute("src"));
    img.setAttribute("src", logoArt || img.getAttribute("data-src"));
  }
  function apply(pick) {
    pick = (pick || DEFAULT).toLowerCase();
    current = pick;
    PROPS.forEach(function (k) { root.style.removeProperty(k); });
    logoArt = null;
    if (pick === DEFAULT.toLowerCase()) { paintLogo(); return; }   // asgard.css's own palette
    var p = palette(pick);
    Object.keys(p).forEach(function (k) { root.style.setProperty(k, p[k]); });
    root.style.setProperty("--hud-rgb", rgb(p["--hud"]).join(" "));
    root.style.setProperty("--hud2-rgb", rgb(p["--hud2"]).join(" "));
    var a = stored(pick);
    if (a) useArt(a);
    else withTemplates(function () { if (current === pick) { var d = draw(pick, p); if (d) useArt(d); } });
  }
  function choose(pick) {
    set(KEY, pick && pick.toLowerCase() !== DEFAULT.toLowerCase() ? pick.toLowerCase() : null);
    apply(pick);
    sync();
  }

  apply(get(KEY));   // now, in <head>: before the page paints

  // ── the picker ──────────────────────────────────────────────────────────────
  var pop = null, button = null;
  var PAL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.8-.8 1.8-1.8 0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.2 0-1 .8-1.8 1.8-1.8H17a4 4 0 0 0 4-4c0-4.4-4-8-9-8z"/>' +
    '<circle cx="7.5" cy="11" r="1.2"/><circle cx="10.5" cy="7" r="1.2"/><circle cx="15" cy="7.5" r="1.2"/></svg>';

  function swatches() {
    return PRESETS.map(function (p) {
      return '<button type="button" class="hud-sw" data-hud-colour="' + p[1] + '" title="' + p[0] + '" aria-label="' + p[0] +
        '" style="--sw:' + p[1] + '"></button>';
    }).join("");
  }
  function sync() {
    document.querySelectorAll(".hud-sw").forEach(function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-hud-colour").toLowerCase() === current ? "true" : "false");
    });
    document.querySelectorAll(".hud-custom").forEach(function (i) { i.value = current; });
  }
  function wire(el) {
    el.addEventListener("click", function (e) {
      var sw = e.target.closest(".hud-sw");
      if (sw) choose(sw.getAttribute("data-hud-colour"));
      if (e.target.closest(".hud-reset")) choose(null);
    });
    el.querySelectorAll(".hud-custom").forEach(function (i) {
      i.addEventListener("input", function () { apply(i.value); sync(); });   // live while dragging
      i.addEventListener("change", function () { choose(i.value); });
    });
  }
  function place() {
    if (!pop || !button) return;
    var r = button.getBoundingClientRect();
    pop.style.top = Math.round(r.bottom + 10) + "px";
    pop.style.right = Math.round(Math.max(8, window.innerWidth - r.right)) + "px";
  }
  function toggle(open) {
    if (!pop) return;
    open = open == null ? pop.hidden : open;
    pop.hidden = !open;
    button.setAttribute("aria-expanded", open ? "true" : "false");
    if (open) place();
  }
  function build() {
    paintLogo();
    var header = document.querySelector(".header");
    if (header && !document.querySelector(".hud-pick")) {
      button = document.createElement("button");
      button.type = "button";
      button.className = "hud-pick";
      button.setAttribute("aria-label", "UI colour");
      button.setAttribute("aria-haspopup", "true");
      button.setAttribute("aria-expanded", "false");
      button.innerHTML = PAL + "<i></i>";
      header.appendChild(button);
      pop = document.createElement("div");
      pop.className = "hud-pop";
      pop.hidden = true;
      pop.setAttribute("role", "dialog");
      pop.setAttribute("aria-label", "UI colour");
      pop.innerHTML = '<div class="hud-pop-h">UI colour</div><div class="hud-sws">' + swatches() + '</div>' +
        '<div class="hud-pop-f"><label>Custom <input type="color" class="hud-custom"></label>' +
        '<button type="button" class="hud-reset">Reset</button></div>';
      document.body.appendChild(pop);
      wire(pop);
      button.addEventListener("click", function (e) { e.stopPropagation(); toggle(); });
      document.addEventListener("click", function (e) { if (!pop.hidden && !pop.contains(e.target)) toggle(false); });
      document.addEventListener("keydown", function (e) { if (e.key === "Escape") toggle(false); });
      window.addEventListener("resize", place);
    }
    var mob = document.querySelector(".mobile-navigation-actions");
    if (mob && !mob.querySelector(".hud-row")) {
      var row = document.createElement("div");
      row.className = "hud-row";
      row.innerHTML = '<div class="hud-row-h"><span>UI colour</span><input type="color" class="hud-custom" aria-label="Custom colour">' +
        '<button type="button" class="hud-reset">Reset</button></div><div class="hud-sws">' + swatches() + '</div>';
      mob.insertBefore(row, mob.firstChild);
      wire(row);
    }
    sync();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", build);
  else build();
})();
