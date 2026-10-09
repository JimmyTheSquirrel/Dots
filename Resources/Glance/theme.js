// theme.js — the UI colour, picked per browser, on BOTH dashboards.
//
// One script, two looks, chosen by data-profile on its <script> tag:
//
//   hud      (Asgard, the default) — the HUD ships in mint (asgard.css's
//            tokens; hud.py's artwork). A pick derives the whole palette: the
//            HUD's two lights and its bright, the six data slots, every glow
//            and line (all rgb(var(--hud-rgb) / …)), and redraws the three
//            pieces of artwork that carry colour (panel frame, Yggdrasil card,
//            logo) from the templates hud.py writes (tpl.js, data-tpl).
//   marsbar  (MarsBar) — her purple and the vine's green are two HUES in
//            marsbar.css (--mb-h, --mb-h2; every hsl() there is written
//            against them), so a pick sets those two, Glance's own background
//            hue and primary colour, and recolours the vine and blossom
//            artwork (data-art: vine.svg, bloom.svg — their purples turned to
//            the pick, their greens to the second colour of a two-tone pick).
//
// Either way, plus Cats: a ginger-and-pink theme that also puts cats all over
// the page (cats.css + cats.js, data-cats / data-cats-js — fetched only when
// someone picks it).
//
// It runs in <head>, before the page paints, so there's no flash of the
// default: the palette is computed from the stored pick, and redrawn artwork
// is kept in localStorage beside it (keyed to the build, so a new build
// redraws it once). Templates/artwork are fetched only when a colour is
// picked — a browser that keeps the default never downloads them.
//
// The choice lives in THIS browser (localStorage): a viewer's preference,
// nothing on the server changes, and Reset goes back to the default. If
// storage is off (a private window) the picker still works for the visit.
//
// The picker replaces Glance's own theme picker (its presets fight these
// stylesheets; cards.css hides it): a swatch button at the end of the
// navigation bar — or, where there is no bar (MarsBar on a desktop), a round
// button in the bottom-right corner — and a row in the phone's ☰ menu.
(function () {
  "use strict";

  var me = document.currentScript;
  function attr(k) { return (me && me.getAttribute(k)) || ""; }
  var MB = attr("data-profile") === "marsbar";
  var DEFAULT = attr("data-default") || (MB ? "#ca99f5" : "#3be8a8");
  var BUILD = attr("data-hud") || attr("data-art-v");
  var TPL_URL = attr("data-tpl");
  var ART_URLS = attr("data-art").split(",").filter(Boolean);   // marsbar: vine, bloom
  var CATS_CSS = attr("data-cats");
  var CATS_JS = attr("data-cats-js");
  var FINE = !!(window.matchMedia && matchMedia("(hover: hover) and (pointer: fine)").matches);
  var KEY = MB ? "marsbar-colour" : "asgard-hud-colour";
  var ART = MB ? "marsbar-art" : "asgard-hud-art";
  // marsbar.css's own hues — what its artwork is drawn in.
  var MB_H = 272, MB_H2 = 150;

  // Light colours read best on the dark glass (rock, 2026-10-05: the first,
  // saturated set was "a lot"). A pick is "#rrggbb", "#rrggbb+#rrggbb" for a
  // two-tone theme (the first colour is the main one, the second its other
  // light: alternate cards and the second series on Asgard, the vine's leaves
  // on MarsBar), or "cats".
  var PRESETS = MB ? [
    ["Lavender — her own", DEFAULT], ["Rose", "#ffa6c9"], ["Coral", "#ffa697"], ["Peach", "#ffbf8f"],
    ["Butter", "#ffdc85"], ["Pistachio", "#c6e891"], ["Mint", "#7eecc0"], ["Aqua", "#7ee0e6"],
    ["Sky", "#8cc8ff"], ["Periwinkle", "#a4b0ff"], ["Orchid", "#e3a8f5"], ["Berry", "#f28cb8"],
  ] : [
    ["Mint", "#3be8a8"], ["Aqua", "#7ee0e6"], ["Sky", "#8cc8ff"], ["Periwinkle", "#a4b0ff"],
    ["Lavender", "#bfa8ff"], ["Orchid", "#e3a8f5"], ["Rose", "#ffa6c9"], ["Coral", "#ffa697"],
    ["Peach", "#ffbf8f"], ["Butter", "#ffdc85"], ["Pistachio", "#c6e891"], ["Frost", "#cfd9e6"],
  ];
  var DUOS = [
    ["Aurora — northern lights", "#7ff0c0+#b7a3ff"], ["Bifröst — the rainbow bridge", "#8fd0ff+#ffadd2"],
    ["Fjord", "#86e3e0+#9db4ff"], ["Muspel — the realm of fire", "#ffbf8f+#ff9fb1"],
    ["Midgard — meadow and wheat", "#b9e89a+#ffd98a"], ["Niflheim — mist and ice", "#cfe6ff+#c8b6ff"],
  ];
  var CATS = "#ffb36b+#ff9ec4";      // ginger and a pink nose
  var VALID = /^(cats|#[0-9a-f]{6}(\+#[0-9a-f]{6})?)$/;
  var PROPS = MB
    ? ["--mb-h", "--mb-h2", "--bgh", "--color-primary", "--color-positive", "--mb-vine", "--mb-bloom"]
    : ["--hud", "--hud2", "--hud-hot", "--hud-deep", "--hud-rgb", "--hud2-rgb",
       "--s1", "--s2", "--s3", "--s4", "--s5", "--s6", "--h-frame", "--h-ygg"];
  var root = document.documentElement;
  if (MB) root.setAttribute("data-dash", "marsbar");

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
  function hueOf(hex) { return toHsl(rgb(hex))[0]; }

  // HUD. Lightness is held in a LIGHT band (0.6–0.84) and saturation capped,
  // so even a custom pick comes out soft on the glass — and a near-black one
  // doesn't vanish. One colour: the second light and the other series are
  // its neighbours a fair way round the wheel (+30, +48, and a paler −34),
  // light enough that none reads as an error. Two-tone: the second colour is
  // the second light and the second series; the third sits between the two.
  function tone(hex) {
    var p = toHsl(rgb(hex));
    return [p[0], Math.min(p[1], 0.9), clamp(p[2], 0.6, 0.84)];
  }
  function between(a, b) { var d = ((b - a + 540) % 360) - 180; return a + d / 2; }
  function hudPalette(colours) {
    var parts = colours.split("+"), A = tone(parts[0]), H = A[0], S = A[1], L = A[2];
    var B = parts[1] ? tone(parts[1]) : [H + 30, S, L * 0.95];
    return {
      "--hud": hsl(H, S, L),
      "--hud2": hsl(B[0], B[1], B[2]),
      "--hud-hot": hsl(H, S, Math.min(0.92, L + 0.14)),
      "--hud-deep": hsl(H, S * 0.6, 0.14),
      "--s1": hsl(H, S, L),
      "--s2": parts[1] ? hsl(B[0], B[1], B[2]) : hsl(H + 48, S, L),
      "--s3": parts[1] ? hsl(between(H, B[0]), (S + B[1]) / 2, Math.min(0.86, (L + B[2]) / 2 + 0.06))
                       : hsl(H - 34, S * 0.8, Math.min(0.86, L + 0.08)),
      "--s4": hsl(H - 12, S * 0.45, L * 0.7),
      "--s5": hsl(H, S, Math.min(0.9, L + 0.14)),
      "--s6": hsl(B[0], B[1], L * 0.62),
    };
  }
  // MarsBar. Only HUES move: her lightness and saturation were tuned by eye
  // for the purple and stay as they are, so every pick sits as softly as hers.
  // The second hue is the vine's green unless a two-tone pick gives one.
  function mbPalette(colours) {
    var parts = colours.split("+"), h = hueOf(parts[0]), h2 = parts[1] ? hueOf(parts[1]) : MB_H2;
    return {
      "--mb-h": h.toFixed(1), "--mb-h2": h2.toFixed(1), "--bgh": (h - 4).toFixed(1),
      "--color-primary": "hsl(" + h.toFixed(1) + ", 82%, 78%)",
      "--color-positive": "hsl(" + h.toFixed(1) + ", 62%, 68%)",
      _h: h, _h2: h2,
    };
  }

  // ── the artwork ─────────────────────────────────────────────────────────────
  function dataUrl(svg) { return "data:image/svg+xml," + encodeURIComponent(svg); }
  function stored(pick) {
    try {
      var a = JSON.parse(get(ART) || "null");
      return a && a.b === BUILD && a.c === pick ? a : null;
    } catch (e) { return null; }
  }
  // HUD: hud.py's templates, colours left as __A__/__H__/__B__/__D__.
  function fill(t, p) {
    return t.replace(/__A__/g, p["--hud"]).replace(/__H__/g, p["--hud-hot"])
      .replace(/__B__/g, p["--hud2"]).replace(/__D__/g, "#14181c");
  }
  function drawHud(pick, p) {
    var T = window.HUD_TPL;
    if (!T) return null;
    var art = { b: BUILD, c: pick, frame: dataUrl(fill(T.frame, p)), ygg: dataUrl(fill(T.ygg, p)), logo: dataUrl(fill(T.logo, p)) };
    set(ART, JSON.stringify(art));
    return art;
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
  // MarsBar: the real vine.svg and bloom.svg, every purple turned by the pick's
  // hue and every green by the second colour's. Gold (the blossoms' hearts)
  // and near-greys stay as they are.
  function shiftSvg(t, dA, dB) {
    return t.replace(/#[0-9a-fA-F]{6}\b/g, function (m) {
      var c = toHsl(rgb(m)), h = c[0];
      if (c[1] < 0.15) return m;
      if (h >= 240 && h <= 345) return hsl(h + dA, c[1], c[2]);
      if (h >= 110 && h <= 175 && dB) return hsl(h + dB, c[1], c[2]);
      return m;
    });
  }
  function drawMb(pick, p, done) {
    if (!ART_URLS.length || !window.fetch) return;
    Promise.all(ART_URLS.map(function (u) { return fetch(u).then(function (r) { return r.text(); }); }))
      .then(function (texts) {
        var art = { b: BUILD, c: pick };
        texts.forEach(function (t, i) { art["a" + i] = dataUrl(shiftSvg(t, p._h - MB_H, p._h2 - MB_H2)); });
        set(ART, JSON.stringify(art));
        done(art);
      })
      .catch(function () { /* the stylesheet's own artwork stays */ });
  }

  // ── the cats ────────────────────────────────────────────────────────────────
  // A face for Asgard's logo (and the Cats swatch, in cards.css).
  var FACE = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 56"><path fill="__C__" fill-rule="evenodd" d="M12 52C6 46 5 36 8 28L6 6L20 15C24 13.6 28 13 32 13C36 13 40 13.6 44 15L58 6L56 28C59 36 58 46 52 52C46 56 18 56 12 52ZM22 31a3.4 4.6 0 1 0 0.01 0ZM42 31a3.4 4.6 0 1 0 0.01 0ZM29.6 41h4.8L32 44Z"/></svg>';
  // Picking Cats loads cats.css and cats.js (data-cats, data-cats-js) — the
  // cats themselves, what they do and everything they react to live there;
  // this only switches them on and off.
  var catsOn = false;
  function loadCats() {
    if (CATS_CSS && !document.querySelector("link[data-cats-css]")) {
      var l = document.createElement("link");
      l.rel = "stylesheet"; l.href = CATS_CSS; l.setAttribute("data-cats-css", "");
      document.head.appendChild(l);
    }
    if (window.Cats) { window.Cats.on(); return; }
    // (A marker of its own: this very <script> tag carries data-cats-js.)
    if (!CATS_JS || document.querySelector("script[data-cats-loaded]")) return;   // already on its way
    var s = document.createElement("script");
    s.src = CATS_JS; s.setAttribute("data-cats-loaded", "");
    s.onload = function () { if (catsOn && window.Cats) window.Cats.on(); };
    document.head.appendChild(s);
  }
  function cats(on) {
    if (on === catsOn) return;
    catsOn = on;
    if (on) { root.setAttribute("data-cats", ""); loadCats(); }
    else { root.removeAttribute("data-cats"); if (window.Cats) window.Cats.off(); }
  }

  // ── applying it ─────────────────────────────────────────────────────────────
  var current = DEFAULT.toLowerCase(), logoArt = null;
  function useArt(a) {
    if (MB) {
      if (a.a0) root.style.setProperty("--mb-vine", 'url("' + a.a0 + '")');
      if (a.a1) root.style.setProperty("--mb-bloom", 'url("' + a.a1 + '")');
      return;
    }
    root.style.setProperty("--h-frame", 'url("' + a.frame + '")');
    root.style.setProperty("--h-ygg", 'url("' + a.ygg + '")');
    logoArt = catsOn ? logoArt : a.logo;
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
    if (!VALID.test(pick)) pick = DEFAULT.toLowerCase();       // an old or mangled value
    current = pick;
    PROPS.forEach(function (k) { root.style.removeProperty(k); });
    logoArt = null;
    cats(pick === "cats");
    if (pick === DEFAULT.toLowerCase()) { paintLogo(); return; }   // the stylesheet's own palette
    var colours = pick === "cats" ? CATS : pick;
    var p = MB ? mbPalette(colours) : hudPalette(colours);
    Object.keys(p).forEach(function (k) { if (k.charAt(0) !== "_") root.style.setProperty(k, p[k]); });
    if (!MB) {
      root.style.setProperty("--hud-rgb", rgb(p["--hud"]).join(" "));
      root.style.setProperty("--hud2-rgb", rgb(p["--hud2"]).join(" "));
      if (catsOn) { logoArt = dataUrl(FACE.replace("__C__", p["--hud"])); paintLogo(); }
    }
    var a = stored(pick);
    if (a) { useArt(a); return; }
    if (MB) drawMb(pick, p, function (d) { if (current === pick) useArt(d); });
    else withTemplates(function () { if (current === pick) { var d = drawHud(pick, p); if (d) useArt(d); } });
  }
  function choose(pick) {
    var keep = pick && pick.toLowerCase() !== DEFAULT.toLowerCase();
    set(KEY, keep ? pick.toLowerCase() : null);
    if (!keep) set(ART, null);                                   // back to the stylesheet's own artwork
    apply(pick);
    sync();
  }

  apply(get(KEY));   // now, in <head>: before the page paints

  // ── the picker ──────────────────────────────────────────────────────────────
  var pop = null, button = null;
  var PAL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.8-.8 1.8-1.8 0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.2 0-1 .8-1.8 1.8-1.8H17a4 4 0 0 0 4-4c0-4.4-4-8-9-8z"/>' +
    '<circle cx="7.5" cy="11" r="1.2"/><circle cx="10.5" cy="7" r="1.2"/><circle cx="15" cy="7.5" r="1.2"/></svg>';

  function swatches(list) {
    return '<div class="hud-sws">' + list.map(function (p) {
      var c = p[1] === "cats" ? CATS.split("+") : p[1].split("+");
      return '<button type="button" class="hud-sw' + (p[1] === "cats" ? " cats" : c[1] ? " duo" : "") + '" data-hud-colour="' + p[1] +
        '" title="' + p[0] + '" aria-label="' + p[0] + '" style="--sw:' + c[0] + (c[1] ? ";--sw2:" + c[1] : "") + '"></button>';
    }).join("") + '</div>';
  }
  // MarsBar's living garden (garden.js) is three switches, not colours —
  // the blossoms that open and close, the butterflies, the fireflies — each
  // on unless she turns it off, kept in this browser as marsbar-<part> =
  // "off". garden.js reads the same keys when it starts, and window.Garden
  // switches a part live.
  var GARDEN = [["blossoms", "Blossoms", "open and close on every card"],
                ["butterflies", "Butterflies", "land on the vine · tap one"],
                ["fireflies", "Fireflies", "at night, or lights off"]];
  function gardenOn(part) { return get("marsbar-" + part) !== "off"; }
  function garden(part, on) {
    set("marsbar-" + part, on ? null : "off");
    if (window.Garden && window.Garden.set) window.Garden.set(part, on);
    sync();
  }
  function allSwatches() {
    return swatches(PRESETS) + '<div class="hud-sub">Two-tone</div>' + swatches(DUOS) +
      '<div class="hud-sub">Just for fun</div>' + swatches([["Cats — cats everywhere", "cats"]]) +
      (MB ? GARDEN.map(function (g) {
              return '<button type="button" class="hud-tg" data-hud-toggle="' + g[0] + '" aria-pressed="true">' +
                '<span>' + g[1] + '<small>' + g[2] + '</small></span><i></i></button>';
            }).join("") : "") +
      '<div class="hud-tip">Tap a cat' + (MB ? " — or a butterfly" : "") + '.' +
      (FINE ? " Double-click an empty bit of page for a laser pointer." : "") + '</div>';
  }
  function sync() {
    document.querySelectorAll(".hud-sw").forEach(function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-hud-colour").toLowerCase() === current ? "true" : "false");
    });
    var c = (current === "cats" ? CATS : current).split("+")[0];
    document.querySelectorAll(".hud-custom").forEach(function (i) { i.value = c; });
    document.querySelectorAll(".hud-tg[data-hud-toggle]").forEach(function (b) {
      b.setAttribute("aria-pressed", gardenOn(b.getAttribute("data-hud-toggle")) ? "true" : "false");
    });
  }
  function wire(el) {
    el.addEventListener("click", function (e) {
      var sw = e.target.closest(".hud-sw");
      if (sw) choose(sw.getAttribute("data-hud-colour"));
      if (e.target.closest(".hud-reset")) choose(null);
      var tg = e.target.closest(".hud-tg[data-hud-toggle]");
      if (tg) { var part = tg.getAttribute("data-hud-toggle"); garden(part, !gardenOn(part)); }
    });
    el.querySelectorAll(".hud-custom").forEach(function (i) {
      i.addEventListener("input", function () { apply(i.value); sync(); });   // live while dragging
      i.addEventListener("change", function () { choose(i.value); });
    });
  }
  // Under the button — or above it, for the corner button.
  function place() {
    if (!pop || !button) return;
    var r = button.getBoundingClientRect();
    pop.style.right = Math.round(Math.max(8, window.innerWidth - r.right)) + "px";
    if (r.top > window.innerHeight / 2) { pop.style.top = "auto"; pop.style.bottom = Math.round(window.innerHeight - r.top + 10) + "px"; }
    else { pop.style.bottom = "auto"; pop.style.top = Math.round(r.bottom + 10) + "px"; }
  }
  function toggle(open) {
    if (!pop) return;
    open = open == null ? pop.hidden : open;
    pop.hidden = !open;
    button.setAttribute("aria-expanded", open ? "true" : "false");
    if (open) place();
  }
  // No visible nav bar (MarsBar hides Glance's on a desktop): the corner
  // button shows. A phone has the ☰ row instead.
  function corner() {
    if (!button || !button.classList.contains("fab")) return;
    var nav = document.querySelector(".mobile-navigation");
    root.classList.toggle("hud-fab", !(nav && getComputedStyle(nav).display !== "none"));
  }
  function build() {
    paintLogo();
    var header = document.querySelector(".header");
    if (!document.querySelector(".hud-pick")) {
      button = document.createElement("button");
      button.type = "button";
      button.className = "hud-pick" + (header ? "" : " fab");
      button.setAttribute("aria-label", "UI colour");
      button.setAttribute("aria-haspopup", "true");
      button.setAttribute("aria-expanded", "false");
      button.innerHTML = PAL + "<i></i>";
      (header || document.body).appendChild(button);
      pop = document.createElement("div");
      pop.className = "hud-pop";
      pop.hidden = true;
      pop.setAttribute("role", "dialog");
      pop.setAttribute("aria-label", "UI colour");
      pop.innerHTML = '<div class="hud-pop-h">UI colour</div>' + allSwatches() +
        '<div class="hud-pop-f"><label>Custom <input type="color" class="hud-custom"></label>' +
        '<button type="button" class="hud-reset">Reset</button></div>';
      document.body.appendChild(pop);
      wire(pop);
      button.addEventListener("click", function (e) { e.stopPropagation(); toggle(); });
      document.addEventListener("click", function (e) { if (!pop.hidden && !pop.contains(e.target)) toggle(false); });
      document.addEventListener("keydown", function (e) { if (e.key === "Escape") toggle(false); });
      window.addEventListener("resize", function () { place(); corner(); });
      corner();
    }
    var mob = document.querySelector(".mobile-navigation-actions");
    if (mob && !mob.querySelector(".hud-row")) {
      var row = document.createElement("div");
      row.className = "hud-row";
      row.innerHTML = '<div class="hud-row-h"><span>UI colour</span><input type="color" class="hud-custom" aria-label="Custom colour">' +
        '<button type="button" class="hud-reset">Reset</button></div>' + allSwatches();
      mob.insertBefore(row, mob.firstChild);
      wire(row);
    }
    sync();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", build);
  else build();
})();
