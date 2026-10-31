// ════════════════════════════════════════════════════════════════════════════
// Live Home Assistant state for the dashboards — ONE client, shared by the main
// Glance (asgard:8888) and MarsBar (marsbar:1111).
//
// Both used to poll ha-bridge every 3s from every open page, hidden tabs and
// pages without a single light included. Now each page that actually HAS a light
// holds one EventSource on the bridge's /events stream: a full snapshot on
// connect, then one event per change from any source — this page, the other
// dashboard, the HA app, an automation, the button on the plug. Every open
// dashboard updates within a few hundred milliseconds of the relay moving.
//
// Loaded from document.head with
//   <script src="/assets/lights.js?v=…" data-api="/ha" defer></script>
//   <script src="/assets/lights.js?v=…" data-api-port="9556" defer></script>
// data-api is a base URL (MarsBar: /ha, proxied by tailscale serve on her own
// origin); data-api-port builds http://<this hostname>:<port> instead, which is
// what the main Glance needs so it keeps working when opened by IP. It must be a
// file in the assets dir, not inline: Glance injects widget markup with
// innerHTML, which never runs <script>, and inline JS in the YAML has already
// broken the config once (see Modules/Server/marsbar.nix).
//
// ── Markup contract ─────────────────────────────────────────────────────────
//   data-ha-entity="switch.x"   painted: gets data-ha-state="on|off|unavailable|
//                               unknown|<raw>", data-ha-pending while an
//                               optimistic flip is unconfirmed, data-ha-error
//                               briefly after a failed toggle, aria-pressed on
//                               buttons. Render the server-side state into
//                               data-ha-state too and nothing shifts on load.
//   data-ha-text                on (or inside) a painted element: textContent is
//                               set to the state ("on", "off", "offline", …)
//   data-ha-toggle[="switch.x"] click toggles that entity (or, empty, the
//                               element's own data-ha-entity)
//   data-ha-members="a b"       on a group's toggle: members flip optimistically
//                               with it (a group toggle moves them all)
//   data-ha-link-label          textContent is set to the connection status
//
// ── Colour-capable bulbs (the bedside lamps) ────────────────────────────────
// A bulb is a tile like any other — data-ha-entity + data-ha-toggle — wrapped
// in a container that adds the colour controls:
//
//   <div data-ha-light="light.x"
//        data-ha-preset-of="input_select.x_preset"
//        data-ha-bright-of="input_number.x_brightness">
//     <button data-ha-entity="light.x" data-ha-toggle>…</button>
//     <button data-ha-preset="Amber">…</button>   ← one per preset
//                                                 (.is-active = the chosen one)
//     <input type="range" data-ha-bright>
//     <b data-ha-bright-label></b>  <b data-ha-preset-label></b>
//
// "Mix your own" is ONE shared panel, not one per bulb — both bedside lamps
// take the same mix. Each row names its own input_number; moving any of them
// POSTs all five to /mix, which stores them and previews on whichever lamps
// are already showing Custom (it never switches a lamp on):
//
//   <div data-ha-mix>
//     <div data-ha-chan-of="input_number.bedroom_custom_red">
//       <input type="range" min="0" max="255" data-ha-chan>
//       <b data-ha-chan-label></b>
//     </div>   ← one per channel, in rgbww order
//   </div>
//   </div>
//
// Clicking a swatch POSTs {preset} and tapping/releasing the slider POSTs
// {brightness_pct} to the bridge's /light/<entity>, which sets the bulb AND
// remembers the choice in those two HA helper entities. Their states come down
// the same stream as everything else — an input_select's state is just a
// string — so the active swatch (data-ha-active) and the slider's position are
// painted from HA, not from local state, and both dashboards stay in step. The
// active swatch is marked with the CLASS `is-active`, which the server can also
// render directly for a correct first paint.
//
// Why the choice lives in HA at all: these are TOUCH LAMPS. The base cuts
// mains, so the bulb reboots and HA loses its colour attributes; the helpers
// are what survives, and an automation re-applies them when it comes back.
//
// <html data-ha-link="connecting|live|delayed|reconnecting|offline"> is set for
// CSS: "reconnecting" means the stream is down and what is on screen may be
// stale — style it that way instead of showing confident, possibly wrong lights.
// Every change is also dispatched as a `ha:state` CustomEvent on document.
// ════════════════════════════════════════════════════════════════════════════
(function () {
  "use strict";

  var cfg = (document.currentScript && document.currentScript.dataset) || {};
  var API = cfg.api ||
    (cfg.apiPort ? location.protocol + "//" + location.hostname + ":" + cfg.apiPort : "/ha");

  // The start gate, and ONLY the start gate — never used to pick elements to
  // paint. `data-ha-watch` is the opt-in for a page that needs HA state but
  // owns no light tile: the Asgard page draws the room temperature from the
  // `ha:state` events below, and without this the stream never opened there
  // and that ring sat at "–" forever.
  var SELECTOR = "[data-ha-entity],[data-ha-toggle],[data-ha-watch]";
  var PENDING_MS = 5000;   // give up on an unconfirmed optimistic flip after this
  var STALE_MS = 40000;    // the bridge pings every 15s; this much silence = dead stream
  var PARK_MS = 60000;     // close the stream after this long hidden (a pocketed phone)
  var HOLD_MS = 2500;      // keep an optimistic swatch/slider while HA catches up
  var BRIGHT_DEBOUNCE_MS = 180; // coalesce a repeating brightness change

  var confirmed = {};      // entity -> last state the bridge reported
  var pending = {};        // entity -> { state, timer } — optimistic, unconfirmed
  var es = null;           // the EventSource, when one is open or opening
  var everOpen = false;
  var haLink = "connecting";   // the bridge's own view of its HA link
  var lastSeen = 0;
  var retryTimer = null, retryDelay = 1000;
  var parkTimer = null, watchTimer = null;
  // helper entity (a bulb's input_select / input_number) -> ignore stream repaints
  // until this timestamp, so a tapped swatch does not flick back to the old one
  // in the moment between our POST and HA reporting the change.
  var hold = {};

  function shown(entity) {
    return pending[entity] ? pending[entity].state : confirmed[entity];
  }

  function label(state) {
    if (state === undefined) return "—";
    if (state === "unavailable") return "offline";
    return state;
  }

  function each(sel, fn) {
    var els = document.querySelectorAll(sel);
    for (var i = 0; i < els.length; i++) fn(els[i]);
  }

  function setFlag(el, name, on) {
    if (on) el.setAttribute(name, "");
    else el.removeAttribute(name);
  }

  // ── a bulb's colour controls ──────────────────────────────────────────────
  // Painted from the two HA helper entities rather than from the light itself:
  // a touch lamp's light is `unavailable` half the time, while the helpers are
  // always there and always hold the choice. Both are ordinary watched
  // entities, so this needs nothing the stream does not already carry.

  function holding(entity) {
    return hold[entity] !== undefined && Date.now() < hold[entity];
  }

  function paintPreset(entity, value) {
    each('[data-ha-preset-of="' + entity + '"]', function (box) {
      var btns = box.querySelectorAll("[data-ha-preset]");
      for (var i = 0; i < btns.length; i++) {
        var on = btns[i].getAttribute("data-ha-preset") === value;
        // A CLASS, not a data- flag: the server renders the remembered swatch
        // active on first paint, and Go's html/template will put a class into
        // an attribute VALUE but not emit a bare attribute NAME. One mechanism
        // for both, so there is nothing stale to clear.
        btns[i].classList.toggle("is-active", on);
        btns[i].setAttribute("aria-pressed", on ? "true" : "false");
      }
      var lab = box.querySelector("[data-ha-preset-label]");
      if (lab) lab.textContent = (value && value !== "unknown" && value !== "unavailable") ? value : "—";
    });
  }

  function paintBright(entity, value) {
    var n = parseFloat(value);
    each('[data-ha-bright-of="' + entity + '"]', function (box) {
      var r = box.querySelector("[data-ha-bright]");
      // Never move the slider out from under a thumb that is still on it.
      if (r && isFinite(n) && !r.hasAttribute("data-ha-dragging")) r.value = String(Math.round(n));
      var lab = box.querySelector("[data-ha-bright-label]");
      if (lab) lab.textContent = isFinite(n) ? Math.round(n) + "%" : "—";
    });
  }

  // Which of the two a state belongs to is decided by its domain, so paint()
  // does not have to run two querySelectorAll per plug sensor change.
  // A custom-mix channel. Same rules as the brightness slider: the stream never
  // moves a thumb that a finger is on, and never inside the debounce window
  // after a release (see `hold`).
  function paintChan(entity, value) {
    var n = parseFloat(value);
    each('[data-ha-chan-of="' + entity + '"]', function (box) {
      var r = box.querySelector("[data-ha-chan]");
      if (r && isFinite(n) && !r.hasAttribute("data-ha-dragging")) r.value = String(Math.round(n));
      var lab = box.querySelector("[data-ha-chan-label]");
      if (lab && isFinite(n)) lab.textContent = String(Math.round(n));
    });
  }

  function paintHelper(entity, st) {
    if (holding(entity)) return;
    if (entity.lastIndexOf("input_select.", 0) === 0) paintPreset(entity, st);
    else if (entity.lastIndexOf("input_number.bedroom_custom_", 0) === 0) paintChan(entity, st);
    else if (entity.lastIndexOf("input_number.", 0) === 0) paintBright(entity, st);
  }

  function paint(entity) {
    var st = shown(entity);
    var text = label(st);
    // Entity ids are [a-z0-9_.] only, so they are safe inside the selector.
    each('[data-ha-entity="' + entity + '"]', function (el) {
      el.setAttribute("data-ha-state", st === undefined ? "unknown" : st);
      setFlag(el, "data-ha-pending", !!pending[entity]);
      if (el.tagName === "BUTTON") el.setAttribute("aria-pressed", st === "on" ? "true" : "false");
      if (el.hasAttribute("data-ha-text")) el.textContent = text;
      var inner = el.querySelectorAll("[data-ha-text]");
      for (var i = 0; i < inner.length; i++) {
        if (inner[i].closest("[data-ha-entity]") === el) inner[i].textContent = text;
      }
    });
    paintHelper(entity, st);

    document.dispatchEvent(new CustomEvent("ha:state", { detail: { entity: entity, state: st } }));
  }

  function settle(entity) {
    var p = pending[entity];
    if (!p) return;
    clearTimeout(p.timer);
    delete pending[entity];
    paint(entity);
  }

  function predict(entity, state) {
    if (pending[entity]) clearTimeout(pending[entity].timer);
    pending[entity] = {
      state: state,
      // Never leave a guess on screen indefinitely: if nothing confirms it, fall
      // back to whatever the bridge last said.
      timer: setTimeout(function () { settle(entity); }, PENDING_MS)
    };
    paint(entity);
  }

  // A batch of truth (snapshot, /states, a toggle reply). Unlike a single
  // `state` event it may predate an in-flight toggle, so it only settles the
  // guesses it agrees with; the rest wait for their own event or the timeout.
  function merge(states) {
    Object.keys(states || {}).forEach(function (entity) {
      var changed = confirmed[entity] !== states[entity];
      confirmed[entity] = states[entity];
      if (pending[entity] && pending[entity].state === states[entity]) settle(entity);
      else if (changed && !pending[entity]) paint(entity);
    });
  }

  // ── connection status ─────────────────────────────────────────────────────
  function link() {
    if (!es || es.readyState !== 1) return everOpen ? "reconnecting" : "connecting";
    if (haLink === "live") return "live";
    if (haLink === "polling") return "delayed";
    if (haLink === "down") return "offline";
    return "connecting";
  }

  var LINK_TEXT = {
    connecting: "Connecting…",
    live: "Live",
    delayed: "Delayed",
    reconnecting: "Reconnecting…",
    offline: "Home Assistant offline"
  };

  function showLink() {
    var l = link();
    if (document.documentElement.getAttribute("data-ha-link") === l) return;
    document.documentElement.setAttribute("data-ha-link", l);
    each("[data-ha-link-label]", function (el) { el.textContent = LINK_TEXT[l]; });
  }

  // ── the stream ────────────────────────────────────────────────────────────
  function seen() { lastSeen = Date.now(); }

  function connect() {
    clearTimeout(retryTimer);
    retryTimer = null;
    if (es) es.close();
    seen();
    var src = es = new EventSource(API + "/events");

    src.addEventListener("snapshot", function (e) {
      var d = JSON.parse(e.data);
      seen();
      everOpen = true;
      retryDelay = 1000;
      haLink = d.ha;
      merge(d.states);
      showLink();
    });
    src.addEventListener("state", function (e) {
      var d = JSON.parse(e.data);
      seen();
      confirmed[d.entity] = d.state;
      // A real event for this entity is the truth, whatever was predicted.
      if (pending[d.entity]) settle(d.entity);
      else paint(d.entity);
    });
    src.addEventListener("link", function (e) {
      seen();
      haLink = JSON.parse(e.data).ha;
      showLink();
    });
    src.addEventListener("ping", function (e) {
      seen();
      var d = JSON.parse(e.data);
      if (d.ha && d.ha !== haLink) { haLink = d.ha; showLink(); }
    });
    src.onopen = function () { seen(); showLink(); };
    src.onerror = function () {
      showLink();
      // EventSource retries network errors by itself, but gives up for good on
      // an HTTP error — e.g. the serve proxy answering 502 while ha-bridge
      // restarts. Take over with a backoff in that case.
      if (src === es && src.readyState === 2) {
        es = null;
        showLink();
        if (!document.hidden && !retryTimer) {
          retryTimer = setTimeout(connect, retryDelay);
          retryDelay = Math.min(retryDelay * 2, 15000);
        }
      }
    };
    showLink();
    watch();
  }

  function disconnect() {
    clearTimeout(retryTimer);
    retryTimer = null;
    clearTimeout(watchTimer);
    watchTimer = null;
    if (es) { es.close(); es = null; }
  }

  // A phone that changed networks can leave the socket half-open: readyState
  // still says OPEN and nothing will ever arrive. The bridge pings every 15s,
  // so silence well past that means the stream is dead — start a new one.
  function watch() {
    clearTimeout(watchTimer);
    watchTimer = setTimeout(function () {
      watchTimer = null;
      if (document.hidden || !es) return;
      if (Date.now() - lastSeen > STALE_MS) connect();
      else watch();
    }, 5000);
  }

  // Cheap one-shot re-sync (the bridge answers from memory).
  function resync() {
    fetch(API + "/states", { cache: "no-store" })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (m) { if (m) { seen(); merge(m); } })
      .catch(function () { /* the stream's own reconnect handles it */ });
  }

  function wake() {
    clearTimeout(parkTimer);
    parkTimer = null;
    if (!es) connect();
    else {
      resync();
      if (Date.now() - lastSeen > STALE_MS) connect();
      else watch();
    }
  }

  // ── clicks ────────────────────────────────────────────────────────────────
  function toggle(entity, members, el) {
    // Flip NOW. HA toggles an off/unknown switch on, so anything not "on" goes on.
    var next = shown(entity) === "on" ? "off" : "on";
    var touched = [entity].concat(members);
    touched.forEach(function (e) { predict(e, next); });

    fetch(API + "/toggle/" + encodeURIComponent(entity), {
      method: "POST",
      cache: "no-store",
      // Required by the bridge. A custom header makes a cross-origin fetch
      // preflight, and only the dashboards pass the preflight — so no other web
      // page in a tailnet browser can flip a light.
      headers: { "X-Dash": "1" }
    })
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (!r.ok) throw new Error(d.error || ("HTTP " + r.status));
          return d;
        });
      })
      .then(function (d) {
        merge(d.states);
        // The bridge waited for this entity to report before answering, so
        // its state in the reply is the truth even if it disagrees.
        if (d.state !== undefined) confirmed[entity] = d.state;
        settle(entity);
      })
      .catch(function () {
        // Roll every guess back to what the bridge last confirmed, and say so.
        touched.forEach(settle);
        each('[data-ha-entity="' + entity + '"]', function (t) { setFlag(t, "data-ha-error", true); });
        setFlag(el, "data-ha-error", true);
        setTimeout(function () {
          each("[data-ha-error]", function (t) { setFlag(t, "data-ha-error", false); });
        }, 2500);
      });
  }

  // POST a colour or a brightness to one bulb. The chosen value is applied to
  // the control at once and HELD briefly, so a tap feels instant rather than
  // waiting on the round trip; the reply — or a failure — always settles it
  // back to whatever HA actually ended up with, which matters because HA
  // clamps brightness to the input_number's step.
  function sendLight(box, body, helper, optimistic, el) {
    var entity = box.getAttribute("data-ha-light");
    if (!entity) return;

    if (helper) {
      hold[helper] = Date.now() + HOLD_MS;
      if (helper.lastIndexOf("input_select.", 0) === 0) paintPreset(helper, optimistic);
      else paintBright(helper, optimistic);
    }
    // The bridge uses light.turn_on, so a swatch tapped on a dark lamp lights
    // it — predict the tile with it rather than letting it lag a beat behind.
    if (shown(entity) !== "on") predict(entity, "on");

    function settleHelper() {
      if (!helper) return;
      delete hold[helper];
      // Only hand the control back to the stream once the stream has actually
      // said something about this helper. A tap in the moment between page load
      // and the first snapshot would otherwise settle onto `undefined` and
      // blank every swatch for a frame.
      if (confirmed[helper] !== undefined) paintHelper(helper, confirmed[helper]);
    }

    fetch(API + "/light/" + encodeURIComponent(entity), {
      method: "POST",
      cache: "no-store",
      // X-Dash for the same reason as a toggle (see above); Content-Type is
      // what makes this a JSON body the bridge will parse.
      headers: { "X-Dash": "1", "Content-Type": "application/json" },
      body: JSON.stringify(body)
    })
      .then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          if (!r.ok) throw new Error(d.error || ("HTTP " + r.status));
          return d;
        });
      })
      .then(function (d) {
        merge(d.states);
        if (d.state !== undefined) confirmed[entity] = d.state;
        settle(entity);
        settleHelper();
      })
      .catch(function () {
        settleHelper();
        settle(entity);
        each('[data-ha-light="' + entity + '"]', function (t) { setFlag(t, "data-ha-error", true); });
        if (el) setFlag(el, "data-ha-error", true);
        setTimeout(function () {
          each("[data-ha-error]", function (t) { setFlag(t, "data-ha-error", false); });
        }, 2500);
      });
  }

  document.addEventListener("click", function (e) {
    // A swatch first: it sits BESIDE the tile, not inside it (a button cannot
    // nest), so this never competes with the tile's own toggle.
    var sw = e.target && e.target.closest ? e.target.closest("[data-ha-preset]") : null;
    if (sw) {
      e.preventDefault();
      e.stopPropagation();
      var box = sw.closest("[data-ha-light]");
      var name = sw.getAttribute("data-ha-preset");
      if (box && name) {
        sendLight(box, { preset: name }, box.getAttribute("data-ha-preset-of"), name, sw);
      }
      return;
    }
    var t = e.target && e.target.closest ? e.target.closest("[data-ha-toggle]") : null;
    if (!t) return;
    // The main Glance puts its toggles inside <summary>; without this the click
    // would also expand/collapse the card underneath.
    e.preventDefault();
    e.stopPropagation();
    if (t.disabled || t.getAttribute("aria-disabled") === "true") return;
    var entity = t.getAttribute("data-ha-toggle") || t.getAttribute("data-ha-entity");
    // One request per entity at a time — a double tap must not flip it back.
    if (!entity || pending[entity]) return;
    var members = (t.getAttribute("data-ha-members") || "").split(/\s+/).filter(Boolean);
    toggle(entity, members, t);
  });


  // ── the brightness slider ─────────────────────────────────────────────────
  // Dragging updates the label only; the POST waits for `change` (the release),
  // so a drag across the track is one request and not forty.
  function slider(e) {
    var r = e.target;
    if (!r || !r.hasAttribute || !r.hasAttribute("data-ha-bright")) return null;
    return r.closest("[data-ha-light]") ? r : null;
  }

  document.addEventListener("input", function (e) {
    var r = slider(e);
    if (!r) return;
    var lab = r.closest("[data-ha-light]").querySelector("[data-ha-bright-label]");
    if (lab) lab.textContent = Math.round(r.value) + "%";
  });

  // Releasing a drag fires `change` once, but an arrow key held down fires it
  // per repeat — so coalesce to the last value a moment after the input stops.
  var brightTimer = {};
  document.addEventListener("change", function (e) {
    var r = slider(e);
    if (!r) return;
    var box = r.closest("[data-ha-light]");
    var helper = box.getAttribute("data-ha-bright-of");
    var v = Math.round(parseFloat(r.value));
    if (!isFinite(v)) return;
    // Hold from the RELEASE, not from the deferred fetch: otherwise a stream
    // event landing inside the debounce window would snap the thumb back to the
    // old value for a fifth of a second.
    hold[helper] = Date.now() + HOLD_MS;
    clearTimeout(brightTimer[helper]);
    brightTimer[helper] = setTimeout(function () {
      delete brightTimer[helper];
      sendLight(box, { brightness_pct: v }, helper, v, r);
    }, BRIGHT_DEBOUNCE_MS);
  });

  // ── the custom-mix sliders ────────────────────────────────────────────────
  // Five channels, one shared mix. `input` moves the label only; `change` sends
  // all five together, because /mix takes a whole colour rather than one
  // channel — sending them singly would walk the lamp through four wrong
  // colours on the way to the right one.
  function chanSlider(e) {
    var r = e.target;
    if (!r || !r.hasAttribute || !r.hasAttribute("data-ha-chan")) return null;
    return r.closest("[data-ha-mix]") ? r : null;
  }

  function mixRows(panel) {
    return panel.querySelectorAll("[data-ha-chan-of]");
  }

  document.addEventListener("input", function (e) {
    var r = chanSlider(e);
    if (!r) return;
    var lab = r.closest("[data-ha-chan-of]").querySelector("[data-ha-chan-label]");
    if (lab) lab.textContent = String(Math.round(r.value));
  });

  var mixTimer = null;
  document.addEventListener("change", function (e) {
    var r = chanSlider(e);
    if (!r) return;
    var panel = r.closest("[data-ha-mix]");
    var rows = mixRows(panel), vals = [], i;
    for (i = 0; i < rows.length; i++) {
      var inp = rows[i].querySelector("[data-ha-chan]");
      var v = inp ? Math.round(parseFloat(inp.value)) : NaN;
      if (!isFinite(v)) return;
      vals.push(v);
      // Hold every channel, not just the one touched: the answer repaints all
      // five, and a stream event must not snap any thumb back mid-adjust.
      hold[rows[i].getAttribute("data-ha-chan-of")] = Date.now() + HOLD_MS;
    }
    clearTimeout(mixTimer);
    mixTimer = setTimeout(function () {
      mixTimer = null;
      sendMix(panel, vals);
    }, BRIGHT_DEBOUNCE_MS);
  });

  function sendMix(panel, vals) {
    setFlag(panel, "data-ha-error", false);
    fetch(API + "/mix", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Dash": "1" },
      body: JSON.stringify({ channels: vals })
    }).then(function (res) {
      if (!res.ok) throw new Error("http " + res.status);
      return res.json();
    }).then(function (d) {
      if (d && d.states) merge(d.states);
    })["catch"](function () {
      setFlag(panel, "data-ha-error", true);
    });
  }

  // While a thumb is down the slider belongs to the finger, not to the stream
  // (paintBright honours this flag). Cleared from the window, not the element,
  // because a pointer released off the track still ends the drag.
  document.addEventListener("pointerdown", function (e) {
    var r = slider(e) || chanSlider(e);
    if (r) r.setAttribute("data-ha-dragging", "");
  });
  function endDrag() {
    each("[data-ha-dragging]", function (r) { r.removeAttribute("data-ha-dragging"); });
  }
  window.addEventListener("pointerup", endDrag);
  window.addEventListener("pointercancel", endDrag);
  // ── lifecycle ─────────────────────────────────────────────────────────────
  function start() {
    // Seed from the server-rendered state so a tap before the snapshot lands
    // still predicts the right direction.
    each("[data-ha-entity]", function (el) {
      var s = el.getAttribute("data-ha-state");
      var e = el.getAttribute("data-ha-entity");
      if ((s === "on" || s === "off") && confirmed[e] === undefined) confirmed[e] = s;
    });
    connect();

    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) { wake(); return; }
      clearTimeout(parkTimer);
      parkTimer = setTimeout(function () {
        parkTimer = null;
        if (document.hidden) disconnect();
      }, PARK_MS);
    });
    // Back/forward cache restores the page without a reload — and with the
    // stream long dead.
    window.addEventListener("pageshow", function (e) { if (e.persisted) wake(); });
    window.addEventListener("online", function () { if (!document.hidden) wake(); });
  }

  // Only pages that actually want HA state get a stream — a light tile, or an
  // explicit `data-ha-watch`. Glance fetches widget markup after
  // DOMContentLoaded and inserts it in one go, then marks #page `content-ready`
  // — so watch until either one appears (start) or the page finishes without
  // one (stand down for good).
  function boot() {
    if (document.querySelector(SELECTOR)) { start(); return; }
    var page = document.getElementById("page");
    var obs = new MutationObserver(function () {
      if (document.querySelector(SELECTOR)) { obs.disconnect(); start(); }
      else if (page && page.classList.contains("content-ready")) obs.disconnect();
    });
    obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
