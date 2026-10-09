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
// Every pick is a TWO-tone (a main light and its partner) or one of the "Just
// for fun" themes — a two-tone of its own that also puts something living on
// the page: Cats (cats.css + cats.js, data-cats / data-cats-js), or Snow,
// Sakura, Starry night, Spooky and Ocean (fx.css + fx.js, data-fx /
// data-fx-js). Those files are fetched only when someone picks one.
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
  var FX_CSS = attr("data-fx");
  var FX_JS = attr("data-fx-js");
  var FINE = !!(window.matchMedia && matchMedia("(hover: hover) and (pointer: fine)").matches);
  var KEY = MB ? "marsbar-colour" : "asgard-hud-colour";
  var ART = MB ? "marsbar-art" : "asgard-hud-art";
  // marsbar.css's own hues — what its artwork is drawn in.
  var MB_H = 272, MB_H2 = 150;

  // Light colours read best on the dark glass (rock, 2026-10-05: the first,
  // saturated set was "a lot"). Every theme is TWO colours (2026-10-09: the
  // single colours went — "I really like those" two-tones): "#rrggbb+#rrggbb",
  // the first the main light, the second its partner (alternate cards and the
  // second series on Asgard, the vine's leaves on MarsBar). A one-colour pick
  // from before still works (the HUD derives a partner for it); the picker
  // just doesn't offer them any more. Or a fun theme's name (FUN, below).
  //
  // The house colours come first, as a swatch of their own: Asgard's mint and
  // teal (asgard.css), her lavender and the vine's green (marsbar.css). It
  // picks DEFAULT — the stylesheet's own palette and artwork, untouched.
  var HOUSE = MB ? ["Lavender — her own, with the vine's green", "#ca99f5+#8fd6b0"]
                 : ["Asgard — mint and teal, as it ships", "#3be8a8+#1fc8c4"];
  // Asgard's are named for the Nine Realms and their people; hers are softer.
  // Sorted by their main colour, so the grid runs round the wheel.
  //
  // Asgard's pairs are built to CONTRAST (2026-10-09: "they're all the same
  // somehow"): the two halves sit far apart on the wheel, and the partner may
  // be deeper and richer than the main light (Fjord's deep blue, Muspelheim's
  // red fire, Skaði's pine) — two pastels side by side read as one colour. And
  // each pair now tints the ground, the glass and the light falling on the page
  // (hudPalette), so it changes the whole room, not just the outlines.
  var DUOS = MB ? [
    ["Plum and gold", "#d79cf0+#ffd27a"], ["Twilight — violet and rose gold", "#b7a3ff+#ffb8a0"],
    ["Bluebell — blue and new leaves", "#a4b0ff+#9fe3a8"], ["Moonlight — silver blue and lilac", "#b9d4ff+#d8b8ff"],
    ["Lagoon — aqua and lilac", "#7ee0e6+#c8a8ff"],
    ["Mermaid — teal and orchid", "#6fe0c8+#e3a8f5"], ["Seafoam and coral", "#8ff0d0+#ffa697"],
    ["Meadow — grass and buttercups", "#b9e89a+#ffd98a"], ["Honeydew — melon and mint", "#c6e891+#8ff0c8"],
    ["Lemonade — lemon and pink", "#fff08a+#ffadd2"], ["Peaches and cream", "#ffbf8f+#ffe3a8"],
    ["Tangerine and teal", "#ffb07a+#7ee0d6"], ["Sorbet — mango and raspberry", "#ffc27a+#ff8fb8"],
    ["Sunset — coral and violet", "#ffa697+#b9a3ff"], ["Strawberries and mint", "#ff9fb1+#8ff0c8"],
    ["Cherry blossom — pink and new leaves", "#ffa6c9+#b5e6a0"], ["Cotton candy — pink and sky", "#ffadd2+#9fd0ff"],
  ] : [
    ["Aurora — northern lights over the snow", "#7ff0c0+#a98bff"], ["Vanaheim — sea-green and coral", "#7ee8d0+#ff8f7a"],
    ["Fjord — glacier water and the deep", "#8ae6e6+#5f8bff"], ["Jötunheim — frost giants and their amber", "#a8e6ff+#e8a865"],
    ["Bifröst — the rainbow bridge", "#8fd0ff+#ff8fc8"],
    ["Skaði — snow and pine", "#e8f4ff+#4fd18b"], ["Niflheim — mist, and the dark below it", "#cfe6ff+#8a7dff"],
    ["Loki — mischief, lime and orchid", "#c6f08a+#c77dff"], ["Midgard — meadow and harvest", "#b9e89a+#ffb35c"],
    ["Álfheim — the light elves, gold and jade", "#fff0a0+#4fe0b0"], ["Sól and Máni — the sun and the moon", "#ffd27a+#8f9fff"],
    ["Mead — honey and plum", "#ffcf7a+#c27df0"], ["Svartálfheim — the forge, ember and steel", "#ffb36b+#7fb0e0"],
    ["Muspelheim — the realm of fire", "#ffc36b+#ff5f57"], ["Ragnarök — ember and ash", "#ff8a65+#a9a3b8"],
    ["Iðunn — apples and leaves", "#ff8f8f+#b5e67a"], ["Freyja — rose and the falcon's green", "#ffa6c9+#5ee8b0"],
  ];
  // The fun themes: a two-tone of their own, and something living on the page.
  // Cats is cats.css + cats.js; the rest are fx.css + fx.js (data-fx,
  // data-fx-js) — each pair fetched only when one of its themes is picked.
  var FUN = [
    ["cats", "Cats — cats everywhere", "#ffb36b+#ff9ec4"],             // ginger and a pink nose
    ["snow", "Snow — a quiet snowfall", "#e3f1ff+#9fc8ff"],
    ["sakura", "Sakura — blossom petals on the wind", "#ffb7d5+#b5e6a0"],
    ["stars", "Starry night — a moon, stars, the odd shooting star", "#a99bff+#ffe08a"],   // night, and starlight
    ["spooky", "Spooky — bats at dusk, and a spider", "#ffa95c+#b99cff"],
    ["ocean", "Ocean — bubbles, light through the water, fish", "#7fe3e8+#ffa697"],
  ];
  var FUNS = {};
  FUN.forEach(function (f) { FUNS[f[0]] = f[2]; });
  var VALID = new RegExp("^(" + Object.keys(FUNS).join("|") + "|#[0-9a-f]{6}(\\+#[0-9a-f]{6})?)$");
  var PROPS = (MB
    ? ["--mb-h", "--mb-h2", "--bgh", "--color-primary", "--color-positive", "--mb-vine", "--mb-bloom"]
    : ["--hud", "--hud2", "--hud-hot", "--hud-deep", "--hud-rgb", "--hud2-rgb",
       "--s1", "--s2", "--s3", "--s4", "--s5", "--s6", "--h-frame", "--h-ygg",
       "--ag-page", "--ag-ground", "--ag-surface", "--ag-pop"]).concat(["--fx-a", "--fx-b", "--fx-ic"]);
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
  // The partner may go a step deeper (0.55) — the contrast that keeps a pair
  // reading as two colours, not one.
  function tone(hex, lo) {
    var p = toHsl(rgb(hex));
    return [p[0], Math.min(p[1], 0.9), clamp(p[2], lo || 0.6, 0.84)];
  }
  // The room a pair lights: the page's ground, its top, the glass of a panel
  // and a pop-up, each the main colour's hue at a low, dark saturation. Near
  // white (Skaði's snow) has no real hue, so its partner's is used instead.
  function ground(A, B) {
    var h = A[2] > 0.88 || A[1] < 0.12 ? B[0] : A[0];
    function rgbs(s, l) { return rgb(hsl(h, s, l)).join(" "); }
    return {
      "--ag-page": hsl(h, 0.3, 0.068),
      "--ag-ground": hsl(h, 0.32, 0.1),
      "--ag-surface": hsl(h, 0.22, 0.095),
      "--ag-pop": "rgb(" + rgbs(0.24, 0.085) + " / 0.97)",
    };
  }
  function between(a, b) { var d = ((b - a + 540) % 360) - 180; return a + d / 2; }
  function hudPalette(colours) {
    var parts = colours.split("+"), A = tone(parts[0]), H = A[0], S = A[1], L = A[2];
    var B = parts[1] ? tone(parts[1], 0.55) : [H + 30, S, L * 0.95];
    var g = ground(toHsl(rgb(parts[0])), B);
    return {
      "--ag-page": g["--ag-page"], "--ag-ground": g["--ag-ground"], "--ag-surface": g["--ag-surface"], "--ag-pop": g["--ag-pop"],
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

  // ── the fun themes ──────────────────────────────────────────────────────────
  // Each has a mark: drawn on its swatch, as Asgard's logo (in the theme's
  // light), and — through --fx-ic — on section headings and MarsBar's crowns
  // (fx.css; Cats keeps its paws and kitten faces, cats.css). __C__ is the colour.
  function svg(box, body) { return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="' + box + '">' + body + '</svg>'; }
  function turns(k, g) {
    for (var i = 0, s = ""; i < k; i++) s += '<g transform="rotate(' + i * 360 / k + ' 12 12)">' + g + '</g>';
    return s;
  }
  var MARK = {
    cats: svg("0 0 64 56", '<path fill="__C__" fill-rule="evenodd" d="M12 52C6 46 5 36 8 28L6 6L20 15C24 13.6 28 13 32 13C36 13 40 13.6 44 15L58 6L56 28C59 36 58 46 52 52C46 56 18 56 12 52ZM22 31a3.4 4.6 0 1 0 0.01 0ZM42 31a3.4 4.6 0 1 0 0.01 0ZM29.6 41h4.8L32 44Z"/>'),
    snow: svg("0 0 24 24", '<g fill="none" stroke="__C__" stroke-width="1.9" stroke-linecap="round">' +
      turns(6, '<path d="M12 12V2.2M12 6L9.3 3.6M12 6l2.7-2.4"/>') + '</g>'),
    sakura: svg("0 0 24 24", '<g fill="__C__">' + turns(5, '<path d="M12 11.3C9.3 9.6 8.4 5.4 10.3 2.4L12 4l1.7-1.6c1.9 3 1 7.2-1.7 8.9Z"/>') + '</g>'),
    stars: svg("0 0 24 24", '<path fill="__C__" d="M12.8 3.1A9 9 0 1 0 20.9 15A7.2 7.2 0 0 1 12.8 3.1ZM19 1.6l.9 2.1 2.1.9-2.1.9-.9 2.1-.9-2.1-2.1-.9 2.1-.9Z"/>'),
    spooky: svg("0 0 24 24", '<path fill="__C__" d="M12 9.2C11.6 8.2 11.1 7.6 10.6 7.4L10.8 8.9C8.6 8.6 5.6 8.6 1.2 6.4C2.6 8.4 3 10.6 2.5 12.8C3.7 11.9 5.3 11.9 6.3 13.1C7 12 8.5 11.6 9.7 12.2C10.4 13.2 11.1 14.8 12 16.4C12.9 14.8 13.6 13.2 14.3 12.2C15.5 11.6 17 12 17.7 13.1C18.7 11.9 20.3 11.9 21.5 12.8C21 10.6 21.4 8.4 22.8 6.4C18.4 8.6 15.4 8.6 13.2 8.9L13.4 7.4C12.9 7.6 12.4 8.2 12 9.2Z"/>'),
    ocean: svg("0 0 24 24", '<path fill="__C__" fill-rule="evenodd" d="M1.6 12C4.6 7.2 10.6 6.2 15 9.6L20.6 6C19.4 9.6 19.4 14.4 20.6 18L15 14.4C10.6 17.8 4.6 16.8 1.6 12ZM6.6 10.4a1.25 1.25 0 1 0 .01 0Z"/>'),
  };
  function mark(kind, colour) { return dataUrl(MARK[kind].replace(/__C__/g, colour)); }

  // A fun theme loads its pair of files the first time it is picked (Cats:
  // data-cats / data-cats-js; the rest: data-fx / data-fx-js) — what lives on
  // the page and everything it does is there; this only switches it on and
  // off. Nobody who never picks one ever downloads them.
  function load(css, js, mark, ready) {
    if (css && !document.querySelector("link[" + mark + "]")) {
      var l = document.createElement("link");
      l.rel = "stylesheet"; l.href = css; l.setAttribute(mark, "");
      document.head.appendChild(l);
    }
    if (ready()) return;
    // (A marker of its own: this very <script> tag carries data-cats-js / data-fx-js.)
    if (!js || document.querySelector("script[" + mark + "-js]")) return;   // already on its way
    var s = document.createElement("script");
    s.src = js; s.setAttribute(mark + "-js", "");
    s.onload = ready;
    document.head.appendChild(s);
  }
  var catsOn = false, fxOn = null;
  function cats(on) {
    if (on === catsOn) return;
    catsOn = on;
    if (on) {
      root.setAttribute("data-cats", "");
      load(CATS_CSS, CATS_JS, "data-cats-loaded", function () { if (catsOn && window.Cats) { window.Cats.on(); return true; } return !!window.Cats; });
    } else { root.removeAttribute("data-cats"); if (window.Cats) window.Cats.off(); }
  }
  function fx(kind) {
    if (kind === fxOn) return;
    if (fxOn && window.Fx) window.Fx.off();
    fxOn = kind;
    if (kind) {
      root.setAttribute("data-fx", kind);
      load(FX_CSS, FX_JS, "data-fx-loaded", function () { if (fxOn && window.Fx) { window.Fx.on(fxOn); return true; } return !!window.Fx; });
    } else root.removeAttribute("data-fx");
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
    logoArt = FUNS[current] ? logoArt : a.logo;          // a fun theme's mark stays the logo
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
    var fun = FUNS[pick];
    cats(pick === "cats");
    fx(fun && pick !== "cats" ? pick : null);
    if (pick === DEFAULT.toLowerCase()) { paintLogo(); return; }   // the stylesheet's own palette
    var colours = fun || pick;
    var p = MB ? mbPalette(colours) : hudPalette(colours);
    Object.keys(p).forEach(function (k) { if (k.charAt(0) !== "_") root.style.setProperty(k, p[k]); });
    if (fun) {
      root.style.setProperty("--fx-a", colours.split("+")[0]);
      root.style.setProperty("--fx-b", colours.split("+")[1]);
      root.style.setProperty("--fx-ic", 'url("' + mark(pick, "#000") + '")');
    }
    if (!MB) {
      root.style.setProperty("--hud-rgb", rgb(p["--hud"]).join(" "));
      root.style.setProperty("--hud2-rgb", rgb(p["--hud2"]).join(" "));
      if (fun) { logoArt = mark(pick, p[pick === "stars" ? "--hud2" : "--hud"]); paintLogo(); }   // a gold moon
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

  // [title, pick, "#a+#b" as shown, fun-theme mark?]
  function swatches(list) {
    return '<div class="hud-sws">' + list.map(function (p) {
      var c = p[2].split("+");
      return '<button type="button" class="hud-sw duo' + (p[3] ? " fun" : "") + '" data-hud-colour="' + p[1] +
        '" title="' + p[0] + '" aria-label="' + p[0] + '" style="--sw:' + c[0] + ";--sw2:" + c[1] +
        (p[3] ? ";--ic:url('" + mark(p[3], "#000") + "')" : "") + '"></button>';
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
    return swatches([[HOUSE[0], DEFAULT, HOUSE[1]]].concat(DUOS.map(function (d) { return [d[0], d[1], d[1]]; }))) +
      '<div class="hud-sub">Just for fun</div>' + swatches(FUN.map(function (f) { return [f[1], f[0], f[2], f[0]]; })) +
      (MB ? GARDEN.map(function (g) {
              return '<button type="button" class="hud-tg" data-hud-toggle="' + g[0] + '" aria-pressed="true">' +
                '<span>' + g[1] + '<small>' + g[2] + '</small></span><i></i></button>';
            }).join("") : "") +
      '<div class="hud-tip"></div>';
  }
  // A line under the fun themes about the one that's on: what it does if you
  // tap it. (MarsBar's butterflies take a tap whatever the theme.)
  var TIP = {
    cats: "Tap a cat." + (FINE ? " Double-click an empty bit of page for a laser pointer." : ""),
    stars: "Tap an empty bit of sky for a shooting star.",
    spooky: "Tap a bat — or the spider.",
    ocean: "Tap a fish.",
  };
  function tip() {
    var t = TIP[current] || "";
    if (MB && gardenOn("butterflies")) t += (t ? " " : "") + "Butterflies like a tap too.";
    return t;
  }
  // The custom pair: two colour wells, the main light and its partner. They
  // show whatever is on (the house colours, a theme's two, an old one-colour
  // pick and the partner the HUD gave it), so a tweak starts from there.
  function pair() {
    if (current === DEFAULT.toLowerCase()) return HOUSE[1].split("+");
    var c = (FUNS[current] || current).split("+");
    if (!c[1]) c[1] = MB ? HOUSE[1].split("+")[1] : hudPalette(c[0])["--hud2"];
    return c;
  }
  function sync() {
    document.querySelectorAll(".hud-sw").forEach(function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-hud-colour").toLowerCase() === current ? "true" : "false");
    });
    var c = pair();
    document.querySelectorAll(".hud-custom").forEach(function (i) { i.value = c[+i.getAttribute("data-i")]; });
    document.querySelectorAll(".hud-tg[data-hud-toggle]").forEach(function (b) {
      b.setAttribute("aria-pressed", gardenOn(b.getAttribute("data-hud-toggle")) ? "true" : "false");
    });
    var t = tip();
    document.querySelectorAll(".hud-tip").forEach(function (e) { e.textContent = t; e.hidden = !t; });
  }
  function wire(el) {
    el.addEventListener("click", function (e) {
      var sw = e.target.closest(".hud-sw");
      if (sw) choose(sw.getAttribute("data-hud-colour"));
      if (e.target.closest(".hud-reset")) choose(null);
      var tg = e.target.closest(".hud-tg[data-hud-toggle]");
      if (tg) { var part = tg.getAttribute("data-hud-toggle"); garden(part, !gardenOn(part)); }
    });
    var wells = el.querySelectorAll(".hud-custom");
    function both() { return wells[0].value.toLowerCase() + "+" + wells[1].value.toLowerCase(); }
    wells.forEach(function (i) {
      i.addEventListener("input", function () { apply(both()); sync(); });   // live while dragging
      i.addEventListener("change", function () { choose(both()); });
    });
  }
  var WELLS = '<span class="hud-wells"><input type="color" class="hud-custom" data-i="0" aria-label="Custom main colour">' +
    '<input type="color" class="hud-custom" data-i="1" aria-label="Custom second colour"></span>';
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
        '<div class="hud-pop-f"><span class="hud-own">Your own' + WELLS + '</span>' +
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
      row.innerHTML = '<div class="hud-row-h"><span>UI colour</span>' + WELLS +
        '<button type="button" class="hud-reset">Reset</button></div>' + allSwatches();
      mob.insertBefore(row, mob.firstChild);
      wire(row);
    }
    sync();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", build);
  else build();
})();
