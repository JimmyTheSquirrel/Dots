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
// broken the config once (see Modules/marsbar.nix).
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

  var SELECTOR = "[data-ha-entity],[data-ha-toggle]";
  var PENDING_MS = 5000;   // give up on an unconfirmed optimistic flip after this
  var STALE_MS = 40000;    // the bridge pings every 15s; this much silence = dead stream
  var PARK_MS = 60000;     // close the stream after this long hidden (a pocketed phone)

  var confirmed = {};      // entity -> last state the bridge reported
  var pending = {};        // entity -> { state, timer } — optimistic, unconfirmed
  var es = null;           // the EventSource, when one is open or opening
  var everOpen = false;
  var haLink = "connecting";   // the bridge's own view of its HA link
  var lastSeen = 0;
  var retryTimer = null, retryDelay = 1000;
  var parkTimer = null, watchTimer = null;

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

  document.addEventListener("click", function (e) {
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

  // Only pages that actually carry a light get a stream. Glance fetches widget
  // markup after DOMContentLoaded and inserts it in one go, then marks #page
  // `content-ready` — so watch until either a light appears (start) or the page
  // finishes without one (stand down for good).
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
