// shopping.js — the shared shopping list and recipe book, on BOTH dashboards.
//
// ONE card (#sh-list — one card to run down in the shop), painted from
// shopping-list's /events stream (Resources/Shopping-List/shopping-list.py,
// :9558), with three tabs across its top (a swipe on a phone moves between
// them; the tab lasts for the browser tab, so a fresh look starts on List):
//
//   List         a "Shopping" heading with a trolley, and under it the
//                trolley bar (how far through the shop), an add box (a
//                comma adds several — "milk, eggs, 2 onions"), then the list
//                grouped by aisle in the order you walk a supermarket, ticked
//                things sinking into "In the trolley", ⋯ on a row for its
//                sheet, ⚑ on a row asked for twice, Undo after anything that
//                removes
//   Pantry       (#sh-usuals) the things you keep in, in groups you make, each
//                with its usual amount — + puts it on the list
//   Recipes      (#sh-recipes) a tile per meal: tap one, untick what you've
//                already got, "Add 7 to the list"; ingredients you usually
//                have (spices) start unticked
//
// Loaded from document.head with
//   <script src="/assets/shopping.js?v=…" data-api-port="9558" data-who="Rock" defer></script>     (admin)
//   <script src="/assets/shopping.js?v=…" data-api="/shop-api" data-who="Kit-Kat" defer></script>  (MarsBar)
// data-who is the name stamped on what this dashboard adds; the OTHER
// dashboard shows it on the row, so each of you can see what the other put on.
//
// ── Instant ─────────────────────────────────────────────────────────────────
// Every tap changes the screen first and asks the server second. The server's
// state (`srv`) is never edited; what is drawn is srv with the queue of not-
// yet-confirmed changes replayed on top (`current()`). A snapshot from the
// stream that predates a change therefore can't undo it on screen, and a
// change the server refused simply drops out of the queue and the row goes
// back. Changes are sent one at a time, in order (an add, then ticking that
// same item, must arrive in that order). If the network is gone — a phone in
// a supermarket — they wait and are retried with backoff, and the footer says
// so; the server's writes are idempotent (see its header) so a retry that
// had in fact arrived does nothing twice.
//
// ⚠ Glance replaces HTMLElement.prototype.animate (Claude/marsbar.md →
// The garden); the row animations call Element.prototype.animate.
(function () {
  "use strict";
  var D = window.Dash;
  if (!D) return;
  var esc = D.esc;
  var me = document.currentScript, cfg = (me && me.dataset) || {};
  var API = cfg.api || D.api(cfg.apiPort || "9558");
  var WHO = (cfg.who || "").slice(0, 20);
  var CALM = !!(window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches);

  // ── Aisles, in the order a shop is walked ─────────────────────────────────
  // The ids are what the server stores (it accepts any [a-z]{1,12}; an id this
  // file doesn't know is drawn under Other).
  var AISLES = [
    ["produce", "🥬", "Fruit & veg"],
    ["bakery", "🍞", "Bakery"],
    ["meat", "🥩", "Meat & fish"],
    ["dairy", "🧀", "Dairy & chilled"],
    ["pantry", "🥫", "Tins & dry goods"],   // id stays "pantry"; the label can't clash with the Pantry tab
    ["frozen", "🧊", "Frozen"],
    ["snacks", "🍫", "Snacks & treats"],
    ["drinks", "🥤", "Drinks"],
    ["household", "🧻", "Household"],
    ["personal", "🧴", "Health & beauty"],
    ["pets", "🐾", "Pets"],
    ["other", "🛒", "Other"]
  ];
  var AISLE = {};
  AISLES.forEach(function (a, i) { AISLE[a[0]] = { i: i, icon: a[1], label: a[2] }; });
  function aisleOf(cat) { return AISLE[cat] ? cat : "other"; }

  // Which aisle a name belongs in: the aisle it was last filed under (someone
  // may have moved it — that's remembered on the server), then a phrase, then
  // the LAST word that means something ("chicken stock" is stock, "frozen
  // peas" is frozen). Singular forms; plurals are folded before looking up.
  var WORDS = {
    produce: "apple banana orange mandarin lemon lime avocado tomato potato onion shallot garlic ginger carrot celery " +
      "capsicum pepper broccoli broccolini cauliflower cabbage lettuce spinach kale rocket cucumber zucchini eggplant " +
      "mushroom pumpkin corn bean pea chilli chili coriander cilantro parsley basil mint dill rosemary thyme sage chive " +
      "leek beetroot radish asparagus berry strawberry blueberry raspberry grape melon watermelon rockmelon pineapple " +
      "mango kiwi kiwifruit pear peach plum nectarine cherry apricot fig salad fruit veg vegetable veggie sprout choy " +
      "lemongrass fennel herb snowpea sweetcorn turnip parsnip silverbeet cob",
    bakery: "bread loaf roll bun wrap tortilla pita naan bagel croissant muffin crumpet baguette sourdough brioche cake " +
      "scroll donut doughnut focaccia ciabatta",
    meat: "chicken beef mince pork lamb steak sausage snag bacon ham salami prosciutto turkey fish salmon prawn shrimp " +
      "barramundi snapper cod fillet thigh breast drumstick wing chorizo meatball schnitzel rib roast duck veal brisket " +
      "patty kangaroo mussel calamari squid rissole",
    dairy: "milk cheese butter yoghurt yogurt cream egg feta parmesan parmigiano mozzarella cheddar ricotta haloumi " +
      "halloumi brie camembert custard margarine tofu hummus dip tzatziki gnocchi",
    pantry: "rice pasta spaghetti penne fettuccine linguine lasagne macaroni risoni noodle flour sugar oil salt spice cumin " +
      "paprika turmeric cinnamon oregano nutmeg stock broth sauce passata paste lentil chickpea cereal oat muesli granola " +
      "honey jam vegemite nutella mayo mayonnaise mustard vinegar ketchup curry cornflour powder yeast vanilla cocoa " +
      "breadcrumb panko couscous quinoa tuna sardine soup gravy seed sesame tahini salsa seasoning syrup sriracha pickle " +
      "olive caper peppercorn bicarb",
    frozen: "icecream gelato pizza dumpling nugget",
    snacks: "chip crisp chocolate choc lolly lollie biscuit cookie popcorn nut almond cashew peanut cracker bar pretzel " +
      "licorice tim",
    drinks: "water juice soda coke cola lemonade beer wine cider coffee tea kombucha cordial softdrink milo",
    household: "toilet tissue towel detergent dishwashing laundry foil sponge bleach spray cleaner battery bulb candle " +
      "napkin softener glad",
    personal: "shampoo conditioner soap toothpaste toothbrush deodorant razor tampon sunscreen moisturiser moisturizer " +
      "panadol paracetamol ibuprofen nurofen floss vitamin plaster bandaid lotion balm",
    pets: "cat dog kitty litter pet"
  };
  var PHRASES = [
    ["peanut butter", "pantry"], ["coconut milk", "pantry"], ["coconut cream", "pantry"], ["sour cream", "dairy"],
    ["cream cheese", "dairy"], ["ice cream", "frozen"], ["baked bean", "pantry"], ["kidney bean", "pantry"],
    ["black bean", "pantry"], ["butter bean", "pantry"], ["cannellini", "pantry"], ["chopped tomato", "pantry"],
    ["diced tomato", "pantry"], ["crushed tomato", "pantry"], ["tinned tomato", "pantry"], ["canned tomato", "pantry"],
    ["tomato paste", "pantry"], ["tomato puree", "pantry"], ["sun dried", "pantry"], ["black pepper", "pantry"],
    ["white pepper", "pantry"], ["chilli flake", "pantry"], ["chili flake", "pantry"], ["lemon juice", "pantry"],
    ["lime juice", "pantry"], ["rice paper", "pantry"], ["taco shell", "pantry"], ["stock cube", "pantry"],
    ["maple syrup", "pantry"], ["puff pastry", "frozen"], ["shortcrust", "frozen"], ["fish finger", "frozen"],
    ["hash brown", "frozen"], ["hot chip", "frozen"], ["garlic bread", "frozen"], ["frozen", "frozen"],
    ["toilet paper", "household"], ["paper towel", "household"], ["baking paper", "household"],
    ["cling wrap", "household"], ["glad wrap", "household"], ["bin bag", "household"], ["bin liner", "household"],
    ["tin foil", "household"], ["dishwasher", "household"], ["washing up", "household"],
    ["washing powder", "household"], ["hand wash", "personal"], ["body wash", "personal"], ["face wash", "personal"],
    ["cotton bud", "personal"], ["energy drink", "drinks"], ["soft drink", "drinks"], ["sparkling water", "drinks"],
    ["spring onion", "produce"], ["cat food", "pets"], ["dog food", "pets"]
  ];
  // The same as the server's key(): case, spacing and a plural ending don't
  // make a different thing. ⚠ Keep in step with shopping-list.py.
  function key(name) {
    var k = String(name || "").toLowerCase().replace(/\s+/g, " ").replace(/^[ .,;:!-]+|[ .,;:!-]+$/g, "");
    if (k.length > 4 && /ies$/.test(k)) return k.slice(0, -3) + "y";
    if (k.length > 4 && /oes$/.test(k)) return k.slice(0, -2);
    if (k.length > 3 && /s$/.test(k) && !/(ss|us|is)$/.test(k)) return k.slice(0, -1);
    return k;
  }
  var KW = {};
  Object.keys(WORDS).forEach(function (cat) { WORDS[cat].split(" ").forEach(function (w) { if (w) KW[key(w)] = cat; }); });

  var hist = {}; // key → { name, cat, n, at }, from the latest snapshot
  function categorise(name) {
    var k = key(name), h = hist[k];
    if (h && h.cat && h.cat !== "other") return h.cat;
    var padded = " " + k + " ";
    for (var i = 0; i < PHRASES.length; i++) if (padded.indexOf(" " + PHRASES[i][0]) >= 0) return PHRASES[i][1];
    var words = k.split(/[^a-z]+/).filter(Boolean);
    for (var j = words.length - 1; j >= 0; j--) { var c = KW[key(words[j])]; if (c) return c; }
    return "other";
  }

  // ── "500g beef mince", "2 onions", "milk x2", "eggs (dozen)", "Milk 2L" ───
  var UNIT = "kg|g|gm|grams?|mg|l|ml|litres?|liters?|lbs?|oz|tins?|cans?|cups?|tbsp|tsp|tablespoons?|teaspoons?|packs?|" +
    "packets?|pkts?|bunch(?:es)?|cloves?|heads?|bags?|bottles?|jars?|loaf|loaves|slices?|dozen|doz|pieces?|pcs|rolls?|" +
    "sticks?|sprigs?|handfuls?|pinch(?:es)?|punnets?|fillets?|cartons?|box(?:es)?|blocks?|sachets?|stalks?|tubs?|cobs?|" +
    "rashers?|sheets?";
  // A fraction first: tried after a plain number, "1/2" would stop at the "1".
  var NUM = "(?:\\d+\\/\\d+|\\d+(?:[.,]\\d+)?|[½¼¾⅓⅔])(?:\\s*(?:-|–|to)\\s*\\d+(?:[.,]\\d+)?)?";
  // The (?![a-z]) belongs to the unit: "4 grapes" is not 4 g of rapes. Outside
  // the group it would also veto "2 bananas" (no unit) and send it to the name.
  var LEAD = new RegExp("^(" + NUM + ")(\\s*)(?:(" + UNIT + ")(?![a-z]))?\\.?\\s*(?:x\\s+)?(?:of\\s+)?(.+)$", "i");
  var TRAIL = new RegExp("^(.+?)\\s*(?:[x×]\\s*(\\d+)|\\(([^()]{1,20})\\)|\\s(\\d+(?:[.,]\\d+)?\\s*(?:" + UNIT + ")))$", "i");
  function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }
  function parse(line) {
    line = String(line || "").replace(/^[\s•*·–-]+/, "").replace(/\s+/g, " ").trim();
    if (!line) return null;
    var qty = "", name = line, m = LEAD.exec(line);
    // "7up": a number glued to a word that isn't a unit is part of the name.
    if (m && (m[2] || m[3])) { qty = m[1] + (m[3] ? m[2].replace(/\s+/g, " ") + m[3] : ""); name = m[4]; }
    else if ((m = TRAIL.exec(line))) { name = m[1]; qty = m[2] || m[3] || m[4] || ""; }
    name = name.replace(/^[\s,;:-]+|[\s,;:-]+$/g, "");
    if (!name) return null;
    return { name: cap(name).slice(0, 80), qty: tidyQty(qty).slice(0, 24) };
  }
  // The add box takes several at once: "milk, eggs, 2 onions".
  function parseMany(text) { return String(text || "").split(/[,;\n]/).map(parse).filter(Boolean); }

  // ── Quantities: a number and a unit, so − and + know how to step them ─────
  // Metric is written the Australian-label way and tight — 300mL, 2L, 500g,
  // 1.5kg — and rolls over at 1000 (900mL + 100 = 1L; 1L − 0.5 = 500mL). Word
  // units take a space and a plural ("2 tins"). Anything else ("2 cloves",
  // "2-3", "a handful") is kept exactly as written.
  // ⚠ shopping-list.py's merge_qty knows the same metric units — keep in step.
  var METRIC = { g: "g", gm: "g", gms: "g", gram: "g", grams: "g", kg: "kg", kgs: "kg", kilo: "kg", kilos: "kg",
    ml: "mL", millilitre: "mL", millilitres: "mL", milliliter: "mL", milliliters: "mL",
    l: "L", lt: "L", ltr: "L", litre: "L", litres: "L", liter: "L", liters: "L" };
  var WORDU = {}, PLURAL = {};
  [["pack", "packs", "packet", "packets", "pkt", "pkts"], ["tin", "tins"], ["can", "cans"], ["bottle", "bottles"],
    ["bunch", "bunches"], ["jar", "jars"], ["bag", "bags"], ["punnet", "punnets"], ["carton", "cartons"], ["tub", "tubs"],
    ["box", "boxes"], ["block", "blocks"], ["loaf", "loaves"], ["dozen", "dozen"]].forEach(function (w) {
    w.forEach(function (f) { WORDU[f] = w[0]; });
    PLURAL[w[0]] = w[1];
  });
  // The unit chips in a row's editor (a unit already on the item that isn't
  // here — "cloves" — is shown as an extra chip).
  var UNITS = [["", "each"], ["g", "g"], ["kg", "kg"], ["mL", "mL"], ["L", "L"],
    ["pack", "pack"], ["tin", "tin"], ["bottle", "bottle"], ["jar", "jar"], ["bunch", "bunch"], ["dozen", "dozen"]];
  function frac(t) {
    return t === "½" ? 0.5 : t === "¼" ? 0.25 : t === "¾" ? 0.75 :
      t.indexOf("/") > 0 ? +t.split("/")[0] / +t.split("/")[1] : parseFloat(t.replace(",", "."));
  }
  function num(n) { return String(Math.round(n * 100) / 100); }
  function parseQty(q) {
    var s = String(q || "").trim(), m;
    if (!s) return { n: null, u: "" };
    m = /^(\d+(?:[.,]\d+)?|\d+\/\d+|[½¼¾])\s*([a-z]+)?\.?$/i.exec(s);
    if (!m) return { n: null, u: "", raw: s };
    var n = frac(m[1]), w = (m[2] || "").toLowerCase();
    if (!w) return { n: n, u: "" };
    if (METRIC[w]) return { n: n, u: METRIC[w] };
    if (WORDU[w]) return { n: n, u: WORDU[w] };
    return { n: n, u: m[2], other: true };
  }
  function fmtQty(n, u) {
    if (!u) return num(n);
    if (u === "g" || u === "kg" || u === "mL" || u === "L") return num(n) + u;
    if (PLURAL[u]) return num(n) + " " + (n === 1 ? u : PLURAL[u]);
    // a unit we don't know: "1 clove" / "2 cloves", by its last letter
    var one = u.length > 3 && /s$/i.test(u) ? u.slice(0, -1) : u;
    return num(n) + " " + (n === 1 ? one : /s$/i.test(u) ? u : u + "s");
  }
  // "300ml" → "300mL", "2 litres" → "2L", "3 tin" → "3 tins"; anything without
  // a leading number ("dozen", "a few") is left as it was typed.
  function tidyQty(q) {
    var p = parseQty(q);
    return p.n != null && !p.other ? fmtQty(p.n, p.u) : String(q || "").trim();
  }
  // One − or + step, or null when there's nowhere to go (the bottom, or a
  // quantity like "2-3" that isn't a number). Absolute values, never deltas:
  // the server's writes must stay idempotent (see its header).
  // Steps land on the step's own grid, so an odd amount comes back to round
  // numbers: 330mL + → 350mL, 950g + → 1kg, 1.2L + → 1.5L.
  function snap(n, step, dir) {
    var k = n / step, e = 1e-9;
    return (dir > 0 ? Math.floor(k + e) + 1 : Math.ceil(k - e) - 1) * step;
  }
  function stepQty(q, dir) {
    var p = parseQty(q), n = p.n, u = p.u, next;
    if (n == null) return p.raw ? null : dir > 0 ? "2" : null; // no quantity = one
    if (u === "g" || u === "mL") {
      next = snap(n, dir > 0 ? (n < 500 ? 50 : 100) : (n <= 500 ? 50 : 100), dir);
      if (next >= 1000) return fmtQty(next / 1000, u === "g" ? "kg" : "L");
      if (next < 50) return null;
      return fmtQty(next, u);
    }
    if (u === "kg" || u === "L") {
      next = snap(n, 0.5, dir);
      if (next < 1) return next <= 0 ? null : fmtQty(next * 1000, u === "kg" ? "g" : "mL");
      return fmtQty(next, u);
    }
    next = snap(n, 1, dir);
    return next < 1 ? null : fmtQty(next, u);
  }
  // Where a unit chip is first tapped on an item with no amount yet.
  function startQty(u) {
    return u === "g" || u === "mL" ? fmtQty(100, u) : u ? fmtQty(1, u) : "2";
  }

  // ── ids (the server accepts [a-z0-9]{6,16}; ours are 10) ─────────────────
  function rid() {
    var a = new Uint8Array(8), s = "";
    (window.crypto || window.msCrypto).getRandomValues(a);
    for (var i = 0; i < 8; i++) s += (a[i] % 36).toString(36);
    return s + ("0" + (Date.now() % 1296).toString(36)).slice(-2);
  }
  function now() { return Math.floor(Date.now() / 1000); }
  function byId(s, id) { for (var i = 0; i < s.items.length; i++) if (s.items[i].id === id) return s.items[i]; return null; }
  function onList(s, name) {
    var k = key(name);
    for (var i = 0; i < s.items.length; i++) if (!s.items[i].done && key(s.items[i].name) === k) return s.items[i];
    return null;
  }

  // ── state: the server's, plus our unconfirmed changes on top ─────────────
  var srv = null, queue = [], busy = false, retryT = null, backoff = 1000, offline = false, queued = false;
  var ui = { typed: "", find: "", got: true, clearArm: 0, step: null, stepT: null,
    tab: "list",                                                   // list | pantry | recipes
    uEdit: false, uGroup: "all", uPick: null, uAmt: "", uJust: {} }; // the pantry
  try {
    ui.got = localStorage.getItem("sh-got") !== "closed";
    ui.uGroup = localStorage.getItem("sh-usual-group") || "all";
    // The tab lasts for this browser tab only: a fresh look at the dashboard
    // (the one you open in the shop) always starts on the list.
    var t0 = sessionStorage.getItem("sh-tab");
    if (t0 === "pantry" || t0 === "recipes") ui.tab = t0;
  } catch (_) {}

  function take(s) {
    if (!s || !s.items) return;
    if (srv && s.sid === srv.sid && s.v < srv.v) return; // older than what we have
    srv = s;
    hist = {};
    (s.history || []).forEach(function (h) { hist[key(h[0])] = { name: h[0], cat: h[1], n: h[2], at: h[3] }; });
    refresh();
  }
  function current() {
    if (!srv) return null;
    var s = { sid: srv.sid, v: srv.v, recipes: srv.recipes, staples: srv.staples || [], history: srv.history,
      groups: (srv.groups || []).map(function (g) { return Object.assign({}, g); }),
      items: srv.items.map(function (i) { return Object.assign({}, i); }) };
    queue.forEach(function (o) { if (o.apply) { try { o.apply(s); } catch (_) { /* a stale change: skip it */ } } });
    return s;
  }

  function send(path, body, apply, done) {
    // A run of − / + taps on one item becomes ONE edit, not one each: an edit
    // still waiting in the queue (not the one already on the wire) for the
    // same item just takes the newer values.
    var last = queue[queue.length - 1];
    if (path === "items/edit" && last && last.path === path && last.body.id === body.id &&
        !(busy && last === queue[0]) && !last.done && !done) {
      Object.assign(last.body, body);
      var before = last.apply;
      last.apply = function (s) { before(s); apply(s); };
      refresh();
      return;
    }
    queue.push({ path: path, body: body, apply: apply, done: done });
    refresh();
    pump();
  }
  function pump() {
    if (busy || retryT || !queue.length) return;
    busy = true;
    var o = queue[0];
    fetch(API + "/" + o.path, {
      method: "POST",
      headers: { "X-Dash": "1", "Content-Type": "application/json" },
      body: JSON.stringify(o.body)
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) { j._status = r.status; return j; });
    }).then(function (j) {
      busy = false;
      // 5xx: the server (or the serve proxy in front of it) is down or
      // restarting — the change is still wanted, so it waits.
      if (j._status >= 500) { later(); return; }
      queue.shift();
      offline = false; backoff = 1000;
      if (j.state) take(j.state);
      if (!j.ok) say(j.error || "That didn't work", { bad: true });
      if (o.done) o.done(j);
      refresh();
      pump();
    }, function () { busy = false; later(); });
  }
  function later() {
    offline = true;
    refresh();
    retryT = setTimeout(function () { retryT = null; pump(); }, backoff);
    backoff = Math.min(backoff * 2, 15000);
  }
  function kick() { if (retryT) { clearTimeout(retryT); retryT = null; } pump(); }
  window.addEventListener("online", kick);

  // ── the changes ──────────────────────────────────────────────────────────
  function addItems(entries, extra) {
    extra = extra || {};
    var t = now();
    entries = entries.map(function (e) {
      return { id: rid(), name: e.name, qty: e.qty || "", cat: e.cat || categorise(e.name), from: extra.from || "" };
    });
    var s = current(), fresh = [], dup = [];
    entries.forEach(function (e) { var on = onList(s, e.name); if (on) dup.push(on.id); else fresh.push(e.id); });
    var body = { items: entries, by: WHO };
    if (extra.recipe) body.recipe = extra.recipe;
    send("items/add", body, function (st) {
      entries.forEach(function (e) {
        if (byId(st, e.id) || onList(st, e.name)) return; // there already: the server merges the quantity
        var k = key(e.name);
        for (var i = 0; i < st.items.length; i++) {
          var it = st.items[i];
          if (it.done && key(it.name) === k) { it.done = false; it.qty = e.qty; delete it.doneAt; return; }
        }
        st.items.push({ id: e.id, name: e.name, qty: e.qty, cat: e.cat, done: false, at: t, from: e.from, by: WHO });
      });
    }, function (j) { flash(j.merged); });
    flash(dup);
    return { fresh: fresh, dup: dup };
  }
  function toggle(id, done) {
    send("items/toggle", { id: id, done: done }, function (st) {
      var it = byId(st, id);
      if (it) { it.done = done; if (done) it.doneAt = now(); else delete it.doneAt; }
    });
  }
  function edit(id, changes) {
    var body = Object.assign({ id: id }, changes);
    send("items/edit", body, function (st) {
      var it = byId(st, id);
      if (!it) return;
      Object.assign(it, changes);
      if ("qty" in changes) it.settled = true; // an amount set by hand is the decision a flag asks for
    });
  }
  function restore(items) {
    send("items/restore", { items: items }, function (st) {
      items.forEach(function (it) { if (!byId(st, it.id)) st.items.push(Object.assign({}, it)); });
    });
  }
  function remove(ids, label) {
    var s = current(), gone = s.items.filter(function (it) { return ids.indexOf(it.id) >= 0; });
    if (!gone.length) return;
    send("items/remove", { ids: ids }, function (st) {
      st.items = st.items.filter(function (it) { return ids.indexOf(it.id) < 0; });
    });
    say(label || (gone.length === 1 ? "Removed " + gone[0].name : "Removed " + gone.length + " items"),
      { undo: function () { restore(gone); } });
  }
  function clear(which) {
    var s = current(), gone = s.items.filter(function (it) { return which === "all" || it.done; });
    if (!gone.length) return;
    send("items/clear", { which: which }, function (st) {
      st.items = st.items.filter(function (it) { return !(which === "all" || it.done); });
    });
    say(which === "all" ? "Cleared the list" : "Cleared " + gone.length + " from the trolley",
      { undo: function () { restore(gone); } });
  }
  function saveRecipe(rec, done) {
    send("recipes/save", rec, function (st) {
      st.recipes = st.recipes.filter(function (r) { return r.id !== rec.id; })
        .concat([Object.assign({ used: 0 }, rec)])
        .sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1; });
    }, done);
  }
  function deleteRecipe(rec) {
    send("recipes/delete", { id: rec.id }, function (st) {
      st.recipes = st.recipes.filter(function (r) { return r.id !== rec.id; });
    });
    say("Deleted " + rec.name, { undo: function () { saveRecipe(rec); } });
  }

  // The usuals (stored as "staples" — the server's name for them): one per
  // name — the server folds a save onto an existing one of the same name
  // (key()), keeping its picture and group unless the save names them; this
  // does the same, so the screen agrees before the answer comes back.
  function usualOf(s, name) {
    var k = key(name);
    for (var i = 0; i < s.staples.length; i++) if (key(s.staples[i].name) === k) return s.staples[i];
    return null;
  }
  function saveUsual(u) {
    send("staples/save", u, function (s) {
      var k = key(u.name), keep = null;
      s.staples = s.staples.filter(function (x) {
        if (x.id === u.id || key(x.name) === k) { keep = x; return false; }
        return true;
      }).concat([Object.assign({}, keep ? { icon: keep.icon || "", group: keep.group || "" } : {}, u, keep ? { id: keep.id } : {})]);
    });
  }
  function deleteUsual(u) {
    send("staples/delete", { id: u.id }, function (s) {
      s.staples = s.staples.filter(function (x) { return x.id !== u.id; });
    });
    say("Took " + u.name + " out of the pantry", { undo: function () { saveUsual(u); } });
  }
  function saveGroup(g) {
    send("groups/save", { id: g.id, name: g.name }, function (s) {
      var hit = s.groups.filter(function (x) { return x.id === g.id; })[0];
      if (hit) hit.name = g.name;
      else if (!s.groups.some(function (x) { return x.name.toLowerCase() === g.name.toLowerCase(); }))
        s.groups = s.groups.concat([{ id: g.id, name: g.name }]);
    });
  }
  function deleteGroup(g) {
    var members = current().staples.filter(function (x) { return x.group === g.id; });
    send("groups/delete", { id: g.id }, function (s) {
      s.groups = s.groups.filter(function (x) { return x.id !== g.id; });
      s.staples = s.staples.map(function (x) { return x.group === g.id ? Object.assign({}, x, { group: "" }) : x; });
    });
    say("Deleted the " + g.name + " group", { undo: function () {
      saveGroup(g);
      members.forEach(function (x) { saveUsual(Object.assign({}, x)); });
    } });
  }

  // ── icons ────────────────────────────────────────────────────────────────
  function svg(d, cls) {
    return '<svg class="' + (cls || "") + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + '</svg>';
  }
  var I = {
    plus: svg('<path d="M12 5v14M5 12h14"/>'),
    minus: svg('<path d="M5 12h14"/>'),
    dots: svg('<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>'),
    check: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
    x: svg('<path d="M6 6l12 12M18 6L6 18"/>'),
    chev: svg('<path d="M6 9l6 6 6-6"/>', "sh-chev"),
    cloud: svg('<path d="M7 18a4.5 4.5 0 0 1-.6-9 6 6 0 0 1 11.4 1.6A3.8 3.8 0 0 1 17.5 18z"/><path d="M4 4l16 16"/>'),
    search: svg('<circle cx="11" cy="11" r="6"/><path d="M20 20l-4.5-4.5"/>'),
    next: svg('<path d="M9 6l6 6-6 6"/>', "sh-next"),
    pencil: svg('<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>'),
    flag: svg('<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>'),
    tick: svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>')   // a plain tick (I.check is the animated one in .sh-box)
  };
  var EMOJI = ("🍝 🍛 🍜 🍲 🥘 🫕 🍳 🥗 🌮 🌯 🫔 🥙 🧆 🍕 🍔 🌭 🍟 🥪 🍗 🍖 🥩 🥓 🐟 🍤 🦐 🦀 🍣 🍱 🍙 🥟 🍢 🍚 🥞 🧇 " +
    "🥐 🥯 🍞 🥖 🧀 🥚 🍰 🧁 🍪 🥧 🍩 🍨 🥣 🍎 🍓 🍌 🥦 🥕 🌽 🌶️ 🥑 🍄 🥔 🍠 🎃 🌿 🍽️").split(" ");
  // Each meal's tile takes the colour of its food (a hue; cards.css mixes it
  // into the tile). The HUD ignores it and stays in the viewer's colours.
  var FOOD_HUE = { "🍝": 4, "🍛": 38, "🍜": 30, "🍲": 14, "🥘": 18, "🫕": 40, "🍳": 46, "🥗": 100, "🌮": 44, "🌯": 34, "🫔": 30,
    "🥙": 32, "🧆": 28, "🍕": 10, "🍔": 26, "🌭": 12, "🍟": 44, "🥪": 36, "🍗": 24, "🍖": 14, "🥩": 356, "🥓": 8, "🐟": 205,
    "🍤": 18, "🦐": 14, "🦀": 6, "🍣": 12, "🍱": 350, "🍙": 210, "🥟": 36, "🍢": 20, "🍚": 200, "🥞": 34, "🧇": 38, "🥐": 34,
    "🥯": 30, "🍞": 32, "🥖": 32, "🧀": 46, "🥚": 44, "🍰": 340, "🧁": 320, "🍪": 30, "🥧": 26, "🍩": 330, "🍨": 300, "🥣": 210,
    "🍎": 358, "🍓": 350, "🍌": 50, "🥦": 110, "🥕": 24, "🌽": 50, "🌶️": 4, "🥑": 85, "🍄": 18, "🥔": 34, "🍠": 20, "🎃": 26, "🌿": 120 };
  function foodHue(icon, name) {
    if (FOOD_HUE[icon] != null) return FOOD_HUE[icon];
    for (var h = 0, i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 360;
    return h;
  }
  // A group's picture, guessed from its name (a group is only ever a name).
  var GROUP_ICONS = [["🧊", "fridge fridges chilled cold dairy"], ["❄️", "freezer frozen"], ["🥫", "cupboard cupboards pantry tins dry"],
    ["🧽", "cleaning clean laundry"], ["🧻", "paper toilet"], ["🧴", "toiletries beauty health personal bathroom"],
    ["🧁", "baking bake"], ["🥤", "drinks drink"], ["🍫", "snacks snack treats"], ["🐾", "pets pet cat cats dog dogs"],
    ["🍼", "baby"], ["🥬", "fruit veg produce garden"], ["🥖", "bread bakery"], ["🥩", "meat butcher"], ["🍷", "wine alcohol"], ["💊", "medicine meds"]];
  function groupIcon(name) {
    var w = String(name || "").toLowerCase().split(/[^a-z]+/);
    for (var i = 0; i < w.length; i++) for (var j = 0; w[i] && j < GROUP_ICONS.length; j++)
      if ((" " + GROUP_ICONS[j][1] + " ").indexOf(" " + w[i] + " ") >= 0) return GROUP_ICONS[j][0];
    return "🏷️";
  }

  // ── the headings: a handwritten title and a drawing in the tab's colours ──
  // Line art, coloured entirely by cards.css (classes, never literal colours),
  // so it follows the viewer's colour picker. The steam rises, the bubbles pop
  // and the sparkles twinkle — CSS only, and still for reduced motion.
  var SPARKS = '<g class="sp"><path d="M24 30l2.6 6 6 2.6-6 2.6-2.6 6-2.6-6-6-2.6 6-2.6z"/><path d="M156 42l1.8 4.2 4.2 1.8-4.2 1.8-1.8 4.2-1.8-4.2-4.2-1.8 4.2-1.8z"/></g>';
  var POT = '<svg class="sh-ill" viewBox="0 0 170 132" aria-hidden="true">' +
    '<ellipse class="shade" cx="86" cy="123" rx="52" ry="4.5"/>' +
    '<g class="st"><path d="M66 44c-9-9 9-15 0-27"/><path d="M86 39c-9-10 9-17 0-31"/><path d="M106 44c-9-9 9-15 0-27"/></g>' +
    '<path class="wood" d="M110 70L141 19"/><ellipse class="wood f" cx="145" cy="12.5" rx="6.5" ry="10" transform="rotate(31 145 12.5)"/>' +
    '<path class="grain" d="M143.5 8.5l2 6.5"/>' +
    '<path class="s f" d="M28 64v24a26 26 0 0 0 26 26h64a26 26 0 0 0 26-26V64"/>' +
    '<path class="band" d="M29 84q57 9 114 0M29 95q57 9 114 0"/>' +
    '<g class="dots"><circle cx="42" cy="91.4" r="1.9"/><circle cx="56" cy="93" r="1.9"/><circle cx="70" cy="93.8" r="1.9"/>' +
      '<circle cx="102" cy="93.8" r="1.9"/><circle cx="116" cy="93" r="1.9"/><circle cx="130" cy="91.4" r="1.9"/></g>' +
    '<path class="heart" d="M86 92.2c-1.6-2.6-6-2-5.4 1.4.5 2.6 5.4 5.2 5.4 5.2s4.9-2.6 5.4-5.2c.6-3.4-3.8-4-5.4-1.4z"/>' +
    '<path class="s" d="M28 70h-8a7 7 0 0 0 0 14h8M144 70h8a7 7 0 0 1 0 14h-8"/>' +
    '<g class="rivet"><circle cx="32.5" cy="73" r="1.7"/><circle cx="32.5" cy="81" r="1.7"/><circle cx="139.5" cy="73" r="1.7"/><circle cx="139.5" cy="81" r="1.7"/></g>' +
    '<ellipse class="soup" cx="86" cy="64" rx="54" ry="6.4"/>' +
    '<circle class="carrot" cx="67" cy="64.5" r="3.6"/><circle class="carrot-in" cx="67" cy="64.5" r="1.3"/>' +
    '<ellipse class="herb" cx="96" cy="63" rx="4.6" ry="2" transform="rotate(-22 96 63)"/><ellipse class="herb" cx="122" cy="64.5" rx="3.6" ry="1.7" transform="rotate(18 122 64.5)"/>' +
    '<circle class="pea" cx="108" cy="65.2" r="2.2"/><circle class="pea" cx="80" cy="66.6" r="1.8"/><circle class="pea" cx="52" cy="63.4" r="1.6"/>' +
    '<g class="bub"><circle cx="74" cy="60.5" r="2"/><circle cx="102" cy="59.5" r="1.6"/><circle cx="114" cy="61" r="1.2"/></g>' +
    '<ellipse class="s rim" cx="86" cy="64" rx="58" ry="8"/>' +
    '<path class="hl" d="M40 79v10a16 16 0 0 0 10 14"/>' +
    '<g class="leaf"><path class="stem" d="M6 126c8-14 20-20 34-22"/><ellipse cx="16" cy="112" rx="8" ry="4" transform="rotate(-40 16 112)"/>' +
      '<ellipse cx="28" cy="106" rx="8" ry="4" transform="rotate(-18 28 106)"/><ellipse cx="22" cy="121" rx="7" ry="3.6" transform="rotate(12 22 121)"/>' +
      '<path class="vein" d="M11 116l10-8M23 109l10-5"/></g>' + SPARKS + '</svg>';
  var BASKET = '<svg class="sh-ill" viewBox="0 0 170 132" aria-hidden="true">' +
    '<ellipse class="shade" cx="85" cy="123" rx="58" ry="4.5"/>' +
    '<path class="s" d="M40 64c0-42 90-42 90 0"/><path class="wrap" d="M52 33l6 5M62 27l5 6M75 23l3 7M95 23l-3 7M108 27l-5 6M118 33l-6 5"/>' +
    '<rect class="wood f" x="44" y="22" width="13" height="48" rx="6.5" transform="rotate(-24 50 46)"/>' +
    '<path class="grain" d="M44 38l8 3M47 47l8 3M50 56l8 3" transform="rotate(-24 50 46)"/>' +
    '<g class="leaf"><ellipse cx="104" cy="44" rx="9" ry="17" transform="rotate(22 104 44)"/><ellipse cx="116" cy="47" rx="8" ry="15" transform="rotate(44 116 47)"/>' +
      '<path class="vein" d="M100 58l7-26M112 58l9-22"/></g>' +
    '<path class="s f" d="M74 64V46c0-6 5-9 5-14v-8h10v8c0 5 5 8 5 14v18z"/><rect class="s lid" x="78" y="17" width="12" height="7" rx="2"/>' +
    '<path class="label" d="M77 46h14v9H77z"/>' +
    '<path class="s f" d="M18 62h134l-14 52H32z"/><path class="s rim" d="M14 62h142"/>' +
    '<path class="weave" d="M24 80h122M28 96h114M56 62l4 52M85 62v52M114 62l-4 52"/>' + SPARKS + '</svg>';
  var TROLLEY = '<svg class="sh-ill" viewBox="0 0 170 132" aria-hidden="true">' +
    '<ellipse class="shade" cx="94" cy="124" rx="58" ry="4.5"/>' +
    '<g class="goods">' +
      '<rect class="wood f" x="58" y="10" width="13" height="44" rx="6.5" transform="rotate(-18 64 32)"/>' +
      '<path class="grain" d="M58 22l8 3M60 31l8 3M62 40l8 3" transform="rotate(-18 64 32)"/>' +
      '<g class="leaf"><ellipse cx="98" cy="30" rx="9" ry="16" transform="rotate(18 98 30)"/><ellipse cx="110" cy="33" rx="8" ry="14" transform="rotate(40 110 33)"/>' +
        '<path class="vein" d="M95 44l5-26M107 46l8-22"/></g>' +
      '<path class="s f" d="M124 42V26c0-6 5-9 5-14V6h10v6c0 5 5 8 5 14v16z"/><rect class="s lid" x="127" y="-1" width="12" height="7" rx="2"/>' +
      '<path class="label" d="M127 26h14v8h-14z"/>' +
    '</g>' +
    '<path class="grip" d="M5 18h9"/><path class="s" d="M8 18h18l16 66"/>' +
    '<path class="s f" d="M30 40h132l-14 44H42z"/><path class="weave" d="M64 40l3 44M96 40v44M128 40l-3 44M34 62h124"/>' +
    '<path class="s" d="M42 84l-4 14h112"/>' +
    '<circle class="s f" cx="52" cy="112" r="9"/><circle class="hub" cx="52" cy="112" r="2.6"/>' +
    '<circle class="s f" cx="136" cy="112" r="9"/><circle class="hub" cx="136" cy="112" r="2.6"/>' + SPARKS + '</svg>';
  var SWASH = '<svg class="sh-swash" viewBox="0 0 200 18" preserveAspectRatio="none" aria-hidden="true"><path d="M4 12C40 3 80 4 112 9s58 6 84-4"/></svg>';
  // The list's subtitle is the trolley bar itself (drawProg paints it).
  var HERO = { list: ["Shopping", '<div class="sh-prog" data-sh-prog></div>', TROLLEY],
    pantry: ["Pantry", "<p>What we keep in</p>", BASKET], recipes: ["Recipes", "<p>What are we cooking tonight?</p>", POT] };
  function hero(k) {
    var h = HERO[k];
    return '<header class="sh-hero ' + k + '"><div class="sh-hero-t"><h3 class="sh-script">' + h[0] + '</h3>' + SWASH +
      h[1] + '</div>' + h[2] + '</header>';
  }

  // ── drawing: a keyed list, so rows MOVE (and can be animated) ────────────
  // Dash.paint morphs by position, which is right for cards whose shape
  // doesn't change; a list whose rows jump sections needs to know which row
  // is which. Each node is { k, sig, html }: an unchanged sig isn't touched
  // (so an open editor's inputs keep their text and focus), a changed one is
  // morphed in place (so the tick's transition runs), and survivors slide to
  // their new places (FLIP).
  function build(html) { var t = document.createElement("template"); t.innerHTML = html; return t.content.firstElementChild; }
  function update(el, html) {
    var n = build(html), i, a;
    for (i = 0; i < n.attributes.length; i++) { a = n.attributes[i]; if (el.getAttribute(a.name) !== a.value) el.setAttribute(a.name, a.value); }
    for (i = el.attributes.length - 1; i >= 0; i--) { a = el.attributes[i].name; if (!n.hasAttribute(a)) el.removeAttribute(a); }
    D.paint(el, n.innerHTML);
  }
  function anim(el, frames, ms) {
    if (CALM) return;
    try { Element.prototype.animate.call(el, frames, { duration: ms, easing: "cubic-bezier(.2,.7,.2,1)" }); } catch (_) {}
  }
  function keyed(box, nodes, animate) {
    var have = {}, top = {}, k, el, i;
    animate = animate && !CALM && box.offsetParent !== null;
    for (i = 0; i < box.children.length; i++) {
      el = box.children[i]; k = el.getAttribute("data-k");
      if (k) { have[k] = el; if (animate) top[k] = el.getBoundingClientRect().top; }
    }
    var want = {};
    nodes.forEach(function (n) { want[n.k] = 1; });
    // Out first, so nothing that stays has to be moved past them (moving a
    // node blurs whatever input inside it has focus).
    Object.keys(have).forEach(function (k2) { if (!want[k2]) { have[k2].remove(); delete have[k2]; } });
    var prev = null, made = [];
    nodes.forEach(function (n) {
      var e = have[n.k];
      if (!e) { e = build(n.html); made.push(e); } else if (e._sig !== n.sig) update(e, n.html);
      e._sig = n.sig;
      var at = prev ? prev.nextSibling : box.firstChild;
      if (at !== e) box.insertBefore(e, at);
      prev = e;
    });
    if (!animate) return;
    nodes.forEach(function (n) {
      var e = have[n.k];
      if (!e || top[n.k] == null) return;
      var dy = top[n.k] - e.getBoundingClientRect().top;
      if (Math.abs(dy) > 1) anim(e, [{ transform: "translateY(" + dy + "px)" }, { transform: "none" }], 320);
    });
    made.forEach(function (e) { anim(e, [{ opacity: 0, transform: "translateY(-6px) scale(.98)" }, { opacity: 1, transform: "none" }], 260); });
  }
  function flash(ids) {
    (ids || []).forEach(function (id) {
      var row = document.querySelector('#sh-list .sh-row[data-id="' + id + '"]');
      if (!row) return;
      row.classList.remove("flash");
      void row.offsetWidth;
      row.classList.add("flash");
      setTimeout(function () { row.classList.remove("flash"); }, 1200);
    });
  }

  // ── the list card ────────────────────────────────────────────────────────
  var L = null;
  function listShell() {
    var host = D.$("sh-list");
    if (!host) return null;
    if (L && host.contains(L.root)) return L;
    host.innerHTML =
      '<div class="sh">' +
        // List · Pantry · Recipes — still ONE card (you run down it in the
        // shop); a swipe across it on a phone goes to the next tab.
        '<div class="sh-tabs" role="tablist" aria-label="Shopping">' + TABS.map(function (t) {
          return '<button type="button" class="sh-tab" role="tab" id="sh-tab-' + t[0] + '" data-sh-tab="' + t[0] + '" aria-controls="sh-pane-' + t[0] + '">' +
            '<span class="sh-tab-i" aria-hidden="true">' + t[1] + '</span><span class="sh-tab-t">' + t[2] + '</span><i data-sh-tab-n></i></button>';
        }).join("") + '</div>' +
        '<div class="sh-pane" id="sh-pane-list" role="tabpanel" aria-labelledby="sh-tab-list" data-pane="list">' + hero("list") +
        '<form class="sh-add" autocomplete="off" data-sh-add>' +
          '<input class="sh-in" type="text" maxlength="300" placeholder="Add to the list… (milk, eggs, 300mL cream)" ' +
            'aria-label="Add to the shopping list" enterkeyhint="done" autocapitalize="sentences">' +
          '<button class="sh-plus" type="submit" aria-label="Add">' + I.plus + '</button>' +
        '</form>' +
        '<div class="sh-chips" data-sh-chips></div>' +
        '<div class="sh-list" role="list" data-sh-items></div>' +
        '<div class="sh-foot" data-sh-foot></div>' +
        '</div>' +
        '<div class="sh-pane sh-pantry" id="sh-usuals" role="tabpanel" aria-labelledby="sh-tab-pantry" data-pane="pantry"></div>' +
        '<div class="sh-pane sh-recipes" id="sh-recipes" role="tabpanel" aria-labelledby="sh-tab-recipes" data-pane="recipes"></div>' +
      '</div>';
    var root = host.firstElementChild;
    L = { root: root, form: root.querySelector("[data-sh-add]"), input: root.querySelector(".sh-add .sh-in"),
      chips: root.querySelector("[data-sh-chips]"), list: root.querySelector("[data-sh-items]"),
      foot: root.querySelector("[data-sh-foot]"), prog: root.querySelector("[data-sh-prog]"),
      tabs: root.querySelectorAll("[data-sh-tab]"), panes: root.querySelectorAll("[data-pane]"), first: true };
    swipe(root);
    L.input.addEventListener("input", function () { ui.typed = L.input.value; refresh(); });
    L.form.addEventListener("submit", function (e) {
      e.preventDefault();
      var got = parseMany(L.input.value);
      if (!got.length) return;
      var r = addItems(got);
      if (r.dup.length && !r.fresh.length && got.length === 1 && !got[0].qty) say(got[0].name + " is already on the list");
      L.input.value = ""; ui.typed = "";
      refresh();
      L.input.focus();
    });
    return L;
  }

  var icons = {}; // recipe name → its picture, for the "from" tag on a row
  // Doubled up: asked for by two or more adds (two recipes, or both of you)
  // and nobody has decided yet what's really needed (see the server's op_add).
  function isFlagged(it) { return !it.done && !it.settled && (it.parts || []).length >= 2; }
  function times(n) { return n === 2 ? "twice" : n + " times"; }
  function flagLabel(it) {
    var ps = it.parts || [], recipes = ps.filter(function (p) { return p.from; }).length;
    return recipes === ps.length ? plural(ps.length, "recipe", "recipes") + " — check" : "Added " + times(ps.length) + " — check";
  }
  function rowNode(it) {
    var meta = "", flagged = isFlagged(it);
    // The flag sits inside the tick button but is checked first in onListClick,
    // so tapping it opens the decision instead of ticking the row.
    if (flagged) meta += '<span class="sh-flag" data-sh-flag>' + I.flag + esc(flagLabel(it)) + '</span>';
    if (it.from) meta += '<span class="sh-from">' + esc((icons[it.from.split(",")[0].trim()] || "🍳") + " " + it.from) + '</span>';
    if (it.by && it.by !== WHO) meta += '<span class="sh-by" title="' + esc("Added by " + it.by) + '">' + esc(it.by) + '</span>';
    // The quantity is its own control, outside the tick: tap it and it opens
    // into − 2L + for a few seconds (ui.step). A ticked row's is just a label.
    var qty = "";
    if (it.qty && it.done) {
      qty = '<span class="sh-qty">' + esc(it.qty) + '</span>';
    } else if (it.qty && ui.step === it.id) {
      var down = stepQty(it.qty, -1), up = stepQty(it.qty, 1);
      qty = '<span class="sh-stepper" role="group" aria-label="' + esc("How many " + it.name) + '">' +
        '<button type="button" class="sh-st" data-sh-step="-1" aria-label="Fewer"' + (down == null ? " disabled" : "") + '>' + I.minus + '</button>' +
        '<b aria-live="polite">' + esc(it.qty) + '</b>' +
        '<button type="button" class="sh-st" data-sh-step="1" aria-label="More"' + (up == null ? " disabled" : "") + '>' + I.plus + '</button></span>';
    } else if (it.qty) {
      qty = '<button type="button" class="sh-qty" data-sh-step-open aria-label="' + esc(it.qty + " — tap to change how many") + '">' + esc(it.qty) + '</button>';
    }
    var html =
      '<div class="sh-row' + (it.done ? " done" : "") + (flagged ? " flagged" : "") + '" role="listitem" data-k="i:' + it.id + '" data-id="' + it.id + '">' +
        '<button type="button" class="sh-main" data-sh-tick aria-pressed="' + !!it.done + '" ' +
          'aria-label="' + esc((it.done ? "Put back: " : "Got it: ") + it.name + (flagged ? " — asked for " + times(it.parts.length) + ", see ⋯" : "")) + '">' +
          '<span class="sh-box" aria-hidden="true">' + I.check + '</span>' +
          '<span class="sh-txt"><span class="sh-name">' + esc(it.name) + '</span>' + (meta ? '<span class="sh-meta">' + meta + '</span>' : '') + '</span>' +
        '</button>' + qty +
        '<button type="button" class="sh-more" data-sh-edit aria-label="' + esc("Change " + it.name) + '">' + I.dots + '</button>' +
      '</div>';
    return { k: "i:" + it.id, sig: html, html: html };
  }
  function headNode(cat, n) {
    var a = AISLE[cat];
    var html = '<div class="sh-sec" data-k="h:' + cat + '"><span class="sh-sec-i" aria-hidden="true">' + a.icon + '</span>' +
      esc(a.label) + '<b>' + n + '</b></div>';
    return { k: "h:" + cat, sig: html, html: html };
  }

  function drawList(s) {
    var C = listShell();
    if (!C) return;
    icons = {};
    s.recipes.forEach(function (r) { icons[r.name] = r.icon || "🍽️"; });
    var todo = s.items.filter(function (i) { return !i.done; });
    var got = s.items.filter(function (i) { return i.done; });
    var nodes = [], groups = {};
    if (!s.items.length) {
      nodes.push({ k: "empty", sig: "1", html: '<div class="sh-empty" data-k="empty"><span aria-hidden="true">🧺</span>' +
        '<b>Nothing on the list</b>Add something above, tap a usual, or pick a recipe.</div>' });
    } else if (!todo.length) {
      nodes.push({ k: "alldone", sig: "1", html: '<div class="sh-empty done" data-k="alldone"><span aria-hidden="true">🎉</span>' +
        '<b>Got everything</b>Clear the trolley when you\'re home.</div>' });
    }
    todo.forEach(function (it) { (groups[aisleOf(it.cat)] = groups[aisleOf(it.cat)] || []).push(it); });
    AISLES.forEach(function (a) {
      var g = groups[a[0]];
      if (!g) return;
      g.sort(function (x, y) { return (x.at - y.at) || (x.id < y.id ? -1 : 1); });
      nodes.push(headNode(a[0], g.length));
      g.forEach(function (it) { nodes.push(rowNode(it)); });
    });
    if (got.length) {
      var gh = '<div class="sh-sec sh-got' + (ui.got ? " open" : "") + '" data-k="h:got">' +
        '<button type="button" class="sh-got-t" data-sh-got aria-expanded="' + ui.got + '">' +
          '<span class="sh-sec-i" aria-hidden="true">✓</span>In the trolley<b>' + got.length + '</b>' + I.chev + '</button>' +
        '<button type="button" class="sh-btn ghost sm" data-sh-clear>Clear</button></div>';
      nodes.push({ k: "h:got", sig: gh, html: gh });
      if (ui.got) {
        got.sort(function (x, y) { return (y.doneAt || 0) - (x.doneAt || 0) || (x.id < y.id ? -1 : 1); });
        got.forEach(function (it) { nodes.push(rowNode(it)); });
      }
    }
    keyed(C.list, nodes, !C.first);
    C.first = false;

    D.paint(C.chips, chipsHtml(s));

    var waiting = queue.length, flagged = todo.filter(isFlagged).length;
    var armed = Date.now() - ui.clearArm < 3000;
    D.paint(C.foot,
      (offline && waiting
        ? '<span class="sh-sync">' + I.cloud + 'Offline — ' + waiting + ' change' + (waiting === 1 ? "" : "s") + ' waiting, sent when you\'re back</span>'
        : '<span class="sh-count">' + (todo.length ? '<b>' + todo.length + '</b> to get' : 'Nothing to get') +
            (got.length ? ' · <b>' + got.length + '</b> in the trolley' : '') +
            (flagged ? ' · <em>' + I.flag + flagged + ' to check</em>' : '') + '</span>') +
      (s.items.length ? '<button type="button" class="sh-btn ghost sm bad' + (armed ? " armed" : "") + '" data-sh-clearall>' +
        (armed ? "Tap again to clear" : "Clear list") + '</button>' : ''));
  }

  // While typing in the add box: pantry things that match (with their usual
  // amounts), then anything bought before. Nothing when the box is empty —
  // the pantry has its own tab.
  function chipsHtml(s) {
    var typed = key(ui.typed.split(/[,;]/).pop().replace(/^\s*\d+\S*\s*/, ""));
    if (!typed) return "";
    var on = {}, seen = {}, list = [];
    s.items.forEach(function (i) { if (!i.done) on[key(i.name)] = 1; });
    function hit(name) { var k = key(name); return k.indexOf(typed) >= 0 && k !== typed && !on[k] && !seen[k]; }
    s.staples.filter(function (x) { return hit(x.name); }).forEach(function (x) {
      seen[key(x.name)] = 1; list.push({ name: x.name, qty: x.qty || "", icon: iconFor(x) });
    });
    Object.keys(hist).map(function (k) { return hist[k]; }).filter(function (h) { return hit(h.name); })
      .sort(function (a, b) { return (key(b.name).indexOf(typed) === 0) - (key(a.name).indexOf(typed) === 0) || b.n - a.n; })
      .forEach(function (h) { seen[key(h.name)] = 1; list.push({ name: h.name, qty: "" }); });
    list = list.slice(0, 6);
    if (!list.length) return "";
    return '<span class="sh-chips-h">Suggestions</span>' + list.map(function (h) {
      return '<button type="button" class="sh-chip" data-sh-quick="' + esc(h.name) + '" data-qty="' + esc(h.qty) + '">' +
        (h.icon ? '<span aria-hidden="true">' + h.icon + '</span>' : I.plus) + esc(h.name) + (h.qty ? '<small>' + esc(h.qty) + '</small>' : '') + '</button>';
    }).join("");
  }

  // ── a picture for a thing, from its name ─────────────────────────────────
  // Used by the usuals and recipe ingredients (each its own picture, not its
  // aisle's); a picture someone picks is stored on the usual and wins. Same lookup as
  // categorise(): a phrase first, then the LAST word that means something
  // ("bin bags" → bin → 🗑️, "chicken stock" → stock → 🥫). Unknown → the aisle's.
  var ICON_WORDS = {
    "🍎": "apple", "🍌": "banana", "🍊": "orange mandarin", "🍋": "lemon lime", "🍓": "strawberry berry raspberry",
    "🫐": "blueberry", "🍇": "grape", "🍉": "watermelon melon rockmelon", "🍍": "pineapple", "🥭": "mango",
    "🥝": "kiwi kiwifruit", "🍐": "pear", "🍑": "peach nectarine apricot plum", "🍒": "cherry", "🥑": "avocado",
    "🍅": "tomato", "🥔": "potato", "🧅": "onion shallot leek", "🧄": "garlic", "🥕": "carrot",
    "🥬": "lettuce cabbage kale spinach choy silverbeet rocket", "🥦": "broccoli broccolini cauliflower",
    "🥒": "cucumber zucchini", "🍆": "eggplant", "🍄": "mushroom", "🎃": "pumpkin", "🌽": "corn sweetcorn cob",
    "🌶️": "chilli chili", "🫑": "capsicum", "🌿": "herb coriander cilantro parsley basil mint dill rosemary thyme sage chive oregano lemongrass",
    "🥗": "salad", "🫘": "bean chickpea lentil",
    "🍞": "bread loaf sourdough", "🥖": "baguette", "🥐": "croissant", "🥯": "bagel", "🫓": "wrap tortilla pita naan",
    "🧁": "muffin cupcake", "🍰": "cake", "🍩": "donut doughnut",
    "🍗": "chicken drumstick wing thigh", "🥩": "beef steak lamb mince veal brisket", "🥓": "bacon ham prosciutto salami",
    "🍖": "pork rib roast", "🌭": "sausage snag", "🐟": "fish salmon barramundi snapper cod fillet tuna sardine",
    "🦐": "prawn shrimp",
    "🥛": "milk cream", "🧀": "cheese feta parmesan mozzarella cheddar haloumi halloumi brie camembert ricotta",
    "🧈": "butter margarine", "🥚": "egg", "🍦": "icecream gelato", "🥄": "yoghurt yogurt custard",
    "🍚": "rice", "🍝": "pasta spaghetti penne noodle lasagne fettuccine linguine macaroni", "🥣": "cereal oat muesli granola weetbix",
    "🥫": "tin can soup stock broth passata gravy", "🫒": "olive oil", "🧂": "salt pepper spice seasoning paprika cumin",
    "🍯": "honey syrup", "🫙": "jam vegemite nutella mayo mayonnaise mustard sauce paste pickle", "🌾": "flour",
    "🍬": "sugar lolly lollie", "🍫": "chocolate choc", "🍪": "biscuit cookie cracker", "🥜": "nut peanut almond cashew",
    "🍿": "popcorn", "🥨": "pretzel", "🍟": "chip crisp",
    "☕️": "coffee", "🍵": "tea", "🧃": "juice cordial", "🥤": "soda coke cola softdrink lemonade kombucha",
    "🍺": "beer", "🍷": "wine", "💧": "water",
    "🗑️": "bin garbage rubbish", "🧽": "sponge dishwashing dishwasher detergent scourer", "🧺": "laundry softener",
    "🧻": "toilet tissue towel napkin", "🧼": "soap", "🧴": "shampoo conditioner lotion sunscreen moisturiser moisturizer bodywash",
    "🪥": "toothbrush toothpaste floss", "🧹": "broom", "🪣": "bucket bleach cleaner spray", "🔋": "battery",
    "💡": "bulb", "🕯️": "candle", "💊": "panadol paracetamol ibuprofen nurofen vitamin", "🩹": "plaster bandaid",
    "🍼": "nappy formula", "🐱": "cat kitty litter", "🐶": "dog", "🌯": "burrito"
  };
  var ICON_PHRASES = [
    ["toilet paper", "🧻"], ["paper towel", "🧻"], ["bin bag", "🗑️"], ["bin liner", "🗑️"], ["garbage bag", "🗑️"],
    ["dishwashing", "🧽"], ["laundry", "🧺"], ["washing powder", "🧺"], ["olive oil", "🫒"], ["ice cream", "🍦"],
    ["peanut butter", "🥜"], ["coconut milk", "🥥"], ["coconut cream", "🥥"], ["tea bag", "🍵"], ["cat food", "🐱"],
    ["dog food", "🐶"], ["hand wash", "🧼"], ["body wash", "🧴"], ["sweet potato", "🍠"], ["spring onion", "🧅"],
    ["baked bean", "🥫"], ["chopped tomato", "🥫"], ["tinned tomato", "🥫"], ["diced tomato", "🥫"], ["tomato paste", "🫙"],
    ["maple syrup", "🍯"], ["soy sauce", "🫙"], ["sour cream", "🥛"], ["cream cheese", "🧀"], ["hot chip", "🍟"],
    ["fish finger", "🐟"], ["garlic bread", "🥖"]
  ];
  var ICON_KW = {};
  Object.keys(ICON_WORDS).forEach(function (e) { ICON_WORDS[e].split(" ").forEach(function (w) { if (w) ICON_KW[key(w)] = e; }); });
  function iconFor(x) {
    if (x.icon) return x.icon;
    var k = key(x.name), padded = " " + k + " ";
    for (var i = 0; i < ICON_PHRASES.length; i++) if (padded.indexOf(" " + ICON_PHRASES[i][0]) >= 0) return ICON_PHRASES[i][1];
    var words = k.split(/[^a-z]+/).filter(Boolean);
    for (var j = words.length - 1; j >= 0; j--) { var e = ICON_KW[key(words[j])]; if (e) return e; }
    return AISLE[aisleOf(x.cat || categorise(x.name))].icon;
  }
  // What can be picked for a staple: roughly by aisle, so it's quick to scan.
  var STAPLE_ICONS = ("🍎 🍌 🍊 🍋 🍓 🫐 🍇 🍉 🍍 🥭 🥝 🍐 🍑 🍒 🥑 🍅 🥔 🍠 🧅 🧄 🥕 🥬 🥦 🥒 🍆 🍄 🎃 🌽 🌶️ 🫑 " +
    "🌿 🌱 🍃 🥗 🍞 🥖 🥐 🥯 🫓 🧁 🍗 🥩 🥓 🍖 🌭 🐟 🦐 🥛 🧀 🧈 🥚 🍦 🥄 " +
    "🍚 🍝 🥣 🥫 🫘 🫒 🧂 🍯 🫙 🌾 🍬 🍫 🍪 🥜 🍿 🍟 ☕️ 🍵 🧃 🥤 🍺 🍷 💧 " +
    "🗑️ 🧽 🧺 🧻 🧼 🧴 🪥 🧹 🪣 🔋 💡 🕯️ 💊 🩹 🍼 🐱 🐶 🐾 🎁 🛒").split(" ");

  // ── small shared bits ────────────────────────────────────────────────────
  function plural(n, one, many) { return n + " " + (n === 1 ? one : many); }
  function recipe(s, id) { for (var i = 0; i < s.recipes.length; i++) if (s.recipes[i].id === id) return s.recipes[i]; return null; }
  function usual(s, id) { for (var i = 0; i < s.staples.length; i++) if (s.staples[i].id === id) return s.staples[i]; return null; }
  function group(s, id) { for (var i = 0; i < s.groups.length; i++) if (s.groups[i].id === id) return s.groups[i]; return null; }
  function clean(v) { return String(v || "").replace(/\s+/g, " ").trim(); }
  // A labelled block in a sheet.
  function field(label, html, hint) {
    return '<div class="sh-field"><span class="sh-label">' + esc(label) + (hint ? '<small>' + esc(hint) + '</small>' : '') + '</span>' + html + '</div>';
  }
  function aisleChips(sel) {
    return AISLES.map(function (a) {
      return '<button type="button" class="sh-opt' + (sel === a[0] ? " on" : "") + '" data-pick-cat="' + a[0] + '" aria-pressed="' + (sel === a[0]) + '">' +
        '<span aria-hidden="true">' + a[1] + '</span>' + esc(a[2]) + '</button>';
    }).join("");
  }

  // ── ONE amount control, used by every editor: − amount + and the units ───
  // Steps by unit (stepQty); a unit typed into the box ("300ml") wins over the
  // chips; tapping a unit on an empty box starts it somewhere sensible.
  function unitChips(sel) {
    var list = UNITS.slice();
    if (sel && !list.some(function (u) { return u[0] === sel; })) list.push([sel, sel]); // "cloves"
    return list.map(function (u) {
      return '<button type="button" class="sh-opt' + (u[0] === sel ? " on" : "") + '" data-amt-unit="' + esc(u[0]) + '" aria-pressed="' + (u[0] === sel) + '">' + esc(u[1]) + '</button>';
    }).join("");
  }
  function amountHtml(q, label) {
    var p = parseQty(q);
    return '<div class="sh-amt" data-amt>' +
      '<div class="sh-qrow">' +
        '<button type="button" class="sh-st" data-amt-step="-1" aria-label="Less">' + I.minus + '</button>' +
        '<input class="sh-in" data-amt-n inputmode="decimal" maxlength="16" placeholder="1" aria-label="' + esc(label || "Amount") + '" value="' +
          esc(p.n == null ? p.raw || "" : num(p.n)) + '">' +
        '<button type="button" class="sh-st" data-amt-step="1" aria-label="More">' + I.plus + '</button>' +
      '</div>' +
      '<div class="sh-opts" data-amt-units role="group" aria-label="Unit">' + unitChips(p.n == null ? "" : p.u) + '</div>' +
    '</div>';
  }
  function amtRead(box) {
    var amt = clean(box.querySelector("[data-amt-n]").value);
    var on = box.querySelector("[data-amt-unit].on"), u = on ? on.getAttribute("data-amt-unit") : "";
    if (!amt) return "";
    var p = parseQty(amt);
    if (p.n == null) return amt + (u ? " " + u : "");
    return p.u ? fmtQty(p.n, p.u) : fmtQty(p.n, u);
  }
  function amtShow(box, q) {
    var p = parseQty(q), u = p.n == null ? "" : p.u, units = box.querySelector("[data-amt-units]");
    box.querySelector("[data-amt-n]").value = p.n == null ? p.raw || "" : num(p.n);
    if (!units.querySelector('[data-amt-unit="' + u + '"]')) units.innerHTML = unitChips(u);
    units.querySelectorAll("[data-amt-unit]").forEach(function (b) {
      var on = b.getAttribute("data-amt-unit") === u;
      b.classList.toggle("on", on); b.setAttribute("aria-pressed", String(on));
    });
  }
  function amtStep(btn) {
    var box = btn.closest("[data-amt]"), dir = +btn.getAttribute("data-amt-step"), q = amtRead(box);
    var on = box.querySelector("[data-amt-unit].on");
    var nq = q ? stepQty(q, dir) : dir > 0 ? startQty(on ? on.getAttribute("data-amt-unit") : "") : null;
    if (nq) { amtShow(box, nq); buzz(); markDirty(); }
  }
  function amtUnit(btn) {
    var box = btn.closest("[data-amt]"), u = btn.getAttribute("data-amt-unit");
    box.querySelectorAll("[data-amt-unit]").forEach(function (b) {
      var on = b === btn;
      b.classList.toggle("on", on); b.setAttribute("aria-pressed", String(on));
    });
    if (u && !clean(box.querySelector("[data-amt-n]").value)) amtShow(box, startQty(u));
    markDirty();
  }

  // ── the sheet: every editor, the same way ────────────────────────────────
  // Slides up from the bottom on a phone, a panel in the middle of a desktop;
  // on <body>, not in the card (her backdrop-filter would trap position:fixed),
  // above everything. One at a time. Kinds:
  //   item    a list row's ⋯: name, how many, aisle, Remove, ☆ add to usuals
  //   flag    a doubled-up row: who asked for how much → Get both / Just one
  //   usual   a usual: picture, name, usual amount, group, aisle
  //   group   a group of usuals: name, delete
  //   cook    a recipe to shop for: tick what's needed → Add N to the list
  //   recipe  the recipe editor: picture, name, ingredient rows, notes
  // Editors are drawn ONCE when opened (the other phone's changes can't wipe
  // what's being typed); flag and cook show live state and are repainted with
  // everything else (paintSheet). Unsaved typing asks before it's thrown away.
  var SH = null, SE = null;
  function sheetRoot() {
    if (SE) return SE;
    var el = document.createElement("div");
    el.className = "sh-scrim";
    el.hidden = true;
    el.innerHTML = '<div class="sh-sheet" role="dialog" aria-modal="true" aria-labelledby="sh-sheet-t">' +
      '<div class="sh-grip" aria-hidden="true"></div>' +
      '<div class="sh-sheet-h"><span class="sh-sheet-ic" aria-hidden="true"></span>' +
        '<span class="sh-sheet-tt"><b id="sh-sheet-t"></b><small></small></span>' +
        '<button type="button" class="sh-x" data-sheet-close aria-label="Close">' + I.x + '</button></div>' +
      '<div class="sh-sheet-b"></div><div class="sh-sheet-f"></div></div>';
    document.body.appendChild(el);
    SE = { root: el, sheet: el.firstElementChild, ic: el.querySelector(".sh-sheet-ic"), t: el.querySelector("#sh-sheet-t"),
      sub: el.querySelector(".sh-sheet-tt small"), body: el.querySelector(".sh-sheet-b"), foot: el.querySelector(".sh-sheet-f") };
    // A phone's keyboard covers the bottom of the screen without moving fixed
    // things, so the sheet sits above it (visualViewport) and never under it.
    if (window.visualViewport) {
      visualViewport.addEventListener("resize", fitSheet);
      visualViewport.addEventListener("scroll", fitSheet);
    }
    return SE;
  }
  function fitSheet() {
    if (!SE || !window.visualViewport) return;
    var vv = window.visualViewport, kb = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
    SE.root.style.setProperty("--kb", Math.round(kb) + "px");
    SE.root.style.setProperty("--vvh", Math.round(vv.height) + "px");
  }
  function openSheet(o) {
    var E = sheetRoot();
    SH = Object.assign({ dirty: false, closeArm: 0, arm: 0 }, o);
    E.sheet.setAttribute("data-kind", o.kind);
    E.ic.textContent = o.icon || "";
    E.ic.hidden = !o.icon;
    E.t.textContent = o.title;
    E.sub.textContent = o.sub || "";
    E.sub.hidden = !o.sub;
    E.body.innerHTML = o.body;
    E.foot.innerHTML = o.foot || "";
    E.body.scrollTop = 0;
    E.root.hidden = false;
    document.documentElement.classList.add("sh-locked");
    fitSheet();
    void E.root.offsetWidth;
    E.root.classList.add("open");
    placeToast();
    var f = o.focus && E.body.querySelector(o.focus);
    if (f) f.focus();
    else if (matchMedia("(hover: hover)").matches) E.sheet.querySelector("[data-sheet-close]").focus();
  }
  function closeSheet(force) {
    if (!SH) return;
    if (SH.dirty && !force && Date.now() - SH.closeArm > 4000) {
      SH.closeArm = Date.now();
      say("Not saved yet — close again to throw the changes away");
      return;
    }
    SH = null;
    SE.root.classList.remove("open");
    placeToast();
    document.documentElement.classList.remove("sh-locked");
    setTimeout(function () { if (!SH) { SE.root.hidden = true; SE.body.innerHTML = ""; SE.foot.innerHTML = ""; } }, CALM ? 0 : 280);
    refresh();
  }
  function markDirty() { if (SH && SH.kind !== "flag" && SH.kind !== "cook") SH.dirty = true; }
  function sheetErr(msg) {
    var e = SE.body.querySelector(".sh-err");
    if (!e) { e = document.createElement("div"); e.className = "sh-err"; SE.body.appendChild(e); }
    e.textContent = msg; e.hidden = false;
    e.scrollIntoView({ block: "nearest" });
  }
  // A destructive button that wants a second tap within 3 s.
  function armed(btn, label) {
    if (Date.now() - SH.arm < 3000) { SH.arm = 0; return true; }
    SH.arm = Date.now();
    var was = btn.textContent;
    btn.textContent = label; btn.classList.add("armed");
    setTimeout(function () { if (btn.isConnected) { btn.textContent = was; btn.classList.remove("armed"); } }, 3000);
    return false;
  }
  // The live sheets, on every render.
  function paintSheet(s) {
    if (!SH) return;
    if (SH.kind === "flag") {
      var it = byId(s, SH.id);
      if (!it || !isFlagged(it)) { closeSheet(true); return; } // decided on the other phone
      D.paint(SE.body, flagBody(it));
      D.paint(SE.foot, flagFoot(it));
    } else if (SH.kind === "cook") {
      var r = recipe(s, SH.id);
      if (!r) { closeSheet(true); return; }
      D.paint(SE.body, cookBody(s, r));
      D.paint(SE.foot, cookFoot(r));
    }
  }

  // Who asked for how much — on a flag, and in a row's sheet.
  function partsHtml(it) {
    return '<ul class="sh-parts">' + (it.parts || []).map(function (p) {
      var src = p.from ? (icons[p.from] || "🍳") + " " + p.from : "Added " + (p.by ? "by " + p.by : "by hand");
      if (p.from && p.by && p.by !== WHO) src += " · " + p.by;
      return '<li><b>' + esc(p.qty || "1") + '</b><span>' + esc(src) + '</span></li>';
    }).join("") + '</ul>';
  }

  // ── item: a list row's ⋯ ─────────────────────────────────────────────────
  function openItem(id) {
    var s = current(), it = byId(s, id);
    if (!it) return;
    var u = usualOf(s, it.name), cat = aisleOf(it.cat);
    openSheet({ kind: "item", id: id, cat: cat, icon: iconFor(it), title: it.name,
      sub: it.done ? "In the trolley" : AISLE[cat].label + (it.by && it.by !== WHO ? " · added by " + it.by : ""),
      body:
        field("What", '<input class="sh-in" data-f="name" maxlength="80" enterkeyhint="done" value="' + esc(it.name) + '">') +
        field("How many", amountHtml(it.qty)) +
        ((it.parts || []).length >= 2 ? field("Asked for by", partsHtml(it), isFlagged(it) ? "doubled up — set the amount you need" : "") : "") +
        field("Aisle", '<div class="sh-opts">' + aisleChips(cat) + '</div>'),
      foot: '<button type="button" class="sh-btn ghost bad" data-item-del>Remove</button>' +
        '<button type="button" class="sh-btn ghost" data-item-usual aria-pressed="' + !!u + '">' + (u ? "★ In the pantry" : "☆ Add to pantry") + '</button>' +
        '<button type="button" class="sh-btn go" data-item-save>Save</button>' });
  }
  function saveItem() {
    var it = byId(current(), SH.id);
    if (!it) { closeSheet(true); return; }
    var name = clean(SE.body.querySelector('[data-f="name"]').value), qty = amtRead(SE.body.querySelector("[data-amt]")), ch = {};
    if (name && name !== it.name) ch.name = name;
    if (qty !== (it.qty || "")) ch.qty = qty;
    if (SH.cat !== aisleOf(it.cat)) ch.cat = SH.cat;
    if (Object.keys(ch).length) edit(it.id, ch);
    closeSheet(true);
  }

  // ── flag: a doubled-up row ───────────────────────────────────────────────
  // The biggest single ask — "just one" of the thing.
  function baseOf(q) { var p = parseQty(q || "1"); return p.n == null ? 0 : p.n * ({ kg: 1000, L: 1000 }[p.u] || 1); }
  function justOne(it) {
    var best = "", n = -1;
    (it.parts || []).forEach(function (p) { var b = baseOf(p.qty); if (b > n) { n = b; best = p.qty || ""; } });
    return best;
  }
  function openFlag(id) {
    var it = byId(current(), id);
    if (!it) return;
    openSheet({ kind: "flag", id: id, icon: "⚑", title: it.name, sub: "Asked for " + times(it.parts.length) + " — how much do you need?",
      body: flagBody(it), foot: flagFoot(it) });
  }
  function flagBody(it) {
    return '<p class="sh-lede">' + (it.parts.every(function (p) { return p.from; })
        ? "More than one recipe needs this. If they're cooked separately you'll want it all; if one lot does both, just one."
        : "This was put on the list more than once. Keep it all, or just one lot?") + '</p>' +
      partsHtml(it) +
      '<div class="sh-total"><span>All together</span><b>' + esc(it.qty || "1") + '</b></div>' +
      '<button type="button" class="sh-link" data-flag-other>Some other amount…</button>';
  }
  function flagFoot(it) {
    var n = it.parts.length;
    return '<button type="button" class="sh-btn ghost" data-flag-one>Just one · ' + esc(justOne(it) || "1") + '</button>' +
      '<button type="button" class="sh-btn go" data-flag-all>' + (n === 2 ? "Get both" : "Get all " + n) + ' · ' + esc(it.qty || String(n)) + '</button>';
  }

  // ── the pantry: things you always keep in, in groups you make ────────────
  // Its own tab. Group chips filter it; each thing is a tile: the round + adds
  // it at its usual amount (and ticks for a moment, so you see it went on),
  // tapping the name opens − amount + / Add to pick first. "Edit" turns the
  // tiles into editors (tap one → its sheet) and offers + New group. NOT a
  // tracker — nothing here reflects the list. The server calls these
  // "staples" (the data predates the name).
  var U = null;
  function usualShell() {
    var host = D.$("sh-usuals");
    if (!host) return null;
    if (U && host.contains(U.root)) return U;
    host.innerHTML =
      '<div class="sh-pane-in">' + hero("pantry") +
        '<div class="sh-bar"><div class="sh-opts scroll" role="tablist" aria-label="Groups" data-u-filters></div>' +
          '<button type="button" class="sh-btn ghost sm" data-u-edit></button></div>' +
        '<div class="sht-list" data-u-list></div>' +
        '<div class="shx-foot" data-u-foot></div>' +
      '</div>';
    var root = host.firstElementChild;
    U = { root: root, filters: root.querySelector("[data-u-filters]"), editBtn: root.querySelector("[data-u-edit]"),
      list: root.querySelector("[data-u-list]"), foot: root.querySelector("[data-u-foot]") };
    return U;
  }
  function usualSort(a, b) {
    return (AISLE[aisleOf(a.cat)].i - AISLE[aisleOf(b.cat)].i) || (a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1);
  }
  function usualTile(x) {
    var t = '<span class="sht-pic" aria-hidden="true">' + iconFor(x) + '</span>' +
      '<span class="sht-t"><b>' + esc(x.name) + '</b>' + (x.qty ? '<small>' + esc(x.qty) + '</small>' : '') + '</span>';
    if (ui.uEdit) {
      return '<div class="sht" role="listitem"><button type="button" class="sht-main" data-u-open="' + x.id + '" ' +
        'aria-label="' + esc("Change " + x.name) + '">' + t + '<span class="sht-ed" aria-hidden="true">' + I.pencil + '</span></button></div>';
    }
    var open = ui.uPick === x.id, just = Date.now() - (ui.uJust[x.id] || 0) < 1600;
    var html = '<div class="sht' + (open ? " open" : "") + (just ? " got" : "") + '" role="listitem">' +
      '<button type="button" class="sht-main" data-u-pick="' + x.id + '" aria-expanded="' + open + '" ' +
        'aria-label="' + esc("Pick how many " + x.name) + '">' + t + '</button>';
    if (!open) {
      return html + '<button type="button" class="sht-add" data-u-quick="' + x.id + '" ' +
        'aria-label="' + esc("Add " + (x.qty ? x.qty + " " : "") + x.name + " to the list") + '">' + (just ? I.tick : I.plus) + '</button></div>';
    }
    var down = stepQty(ui.uAmt, -1), up = stepQty(ui.uAmt, 1);
    return html + '<div class="sht-pick">' +
        '<span class="sh-stepper" role="group" aria-label="' + esc("How many " + x.name) + '">' +
          '<button type="button" class="sh-st" data-u-step="-1" aria-label="Fewer"' + (down == null ? " disabled" : "") + '>' + I.minus + '</button>' +
          '<b aria-live="polite">' + esc(ui.uAmt || "1") + '</b>' +
          '<button type="button" class="sh-st" data-u-step="1" aria-label="More"' + (up == null ? " disabled" : "") + '>' + I.plus + '</button>' +
        '</span>' +
        '<button type="button" class="sh-btn go" data-u-add="' + x.id + '">Add to list</button>' +
      '</div></div>';
  }
  function drawUsuals(s) {
    var C = usualShell();
    if (!C) return;
    var all = s.staples.slice().sort(usualSort), groups = s.groups;
    var known = {}; groups.forEach(function (g) { known[g.id] = 1; });
    var loose = all.filter(function (x) { return !known[x.group]; });
    var f = ui.uGroup;
    if (f !== "all" && f !== "none" && !known[f]) f = ui.uGroup = "all";
    if (f === "none" && !loose.length) f = ui.uGroup = "all";
    if (ui.uPick && !usual(s, ui.uPick)) ui.uPick = null;

    function chip(id, label, n, icon) {
      return '<button type="button" class="sh-opt' + (f === id ? " on" : "") + '" role="tab" aria-selected="' + (f === id) + '" data-u-filter="' + id + '">' +
        (icon ? '<span aria-hidden="true">' + icon + '</span>' : '') + esc(label) + (n != null ? '<i>' + n + '</i>' : '') + '</button>';
    }
    D.paint(C.filters, (groups.length || loose.length < all.length ? chip("all", "All", all.length) : "") +
      groups.map(function (g) { return chip(g.id, g.name, all.filter(function (x) { return x.group === g.id; }).length, groupIcon(g.name)); }).join("") +
      (loose.length && groups.length ? chip("none", "No group", loose.length, "📦") : ""));
    D.paint(C.editBtn, ui.uEdit ? "Done" : I.pencil + "Edit");
    C.editBtn.classList.toggle("go", ui.uEdit);
    C.editBtn.hidden = !all.length && !groups.length;

    var secs = [];
    if (f === "all") {
      groups.forEach(function (g) { secs.push([g, all.filter(function (x) { return x.group === g.id; })]); });
      if (loose.length) secs.push([{ id: "none", name: groups.length ? "No group" : "" }, loose]);
    } else if (f === "none") secs.push([{ id: "none", name: "" }, loose]);
    else secs.push([group(s, f), all.filter(function (x) { return x.group === f; })]);
    var html = !all.length && !groups.length
      ? '<div class="shx-empty"><span aria-hidden="true">🧺</span><b>The pantry\'s empty</b>Save what you buy all the time — 300mL cream, 250g butter, ' +
        'toilet paper — and it\'s one tap onto the list.</div>'
      : secs.map(function (sec) {
        var g = sec[0], rows = sec[1];
        if (!rows.length && !ui.uEdit) return "";
        var head = (f === "all" && g.name) || (f !== "all" && ui.uEdit && g.id !== "none")
          ? '<div class="sht-h"><span class="sht-h-i" aria-hidden="true">' + (g.id === "none" ? "📦" : groupIcon(g.name)) + '</span>' +
            '<span>' + esc(g.name) + '</span><b>' + rows.length + '</b>' +
            (ui.uEdit && g.id !== "none" ? '<button type="button" class="sh-btn ghost sm" data-g-open="' + g.id + '">' + I.pencil + 'Rename</button>' : '') + '</div>'
          : '';
        return '<div class="sht-sec">' + head + (rows.length
          ? '<div class="sht-grid" role="list">' + rows.map(usualTile).join("") + '</div>'
          : '<div class="shx-none">Nothing in this group yet.</div>') + '</div>';
      }).join("");
    D.paint(C.list, html);
    D.paint(C.foot,
      (ui.uEdit ? '<button type="button" class="sh-btn ghost" data-g-new>' + I.plus + 'New group</button>' : '') +
      '<button type="button" class="sh-btn" data-u-new>' + I.plus + 'Add to the pantry</button>');
  }
  // Put a usual on the list at the amount given ("" = just the thing).
  function addUsual(x, qty) {
    if (/^1$/.test(qty)) qty = ""; // one, unitless, is just the thing
    var r = addItems([{ name: x.name, qty: qty, cat: x.cat && x.cat !== "other" ? x.cat : undefined }]);
    var what = (qty ? qty + " " : "") + x.name;
    ui.uJust[x.id] = Date.now();
    setTimeout(refresh, 1700);
    if (r.fresh.length) say("Added " + what + " to the list", { undo: function () { remove(r.fresh, "Took " + x.name + " back off"); } });
    else if (qty) say(x.name + " was already on the list — added " + qty + " (⚑ to check)");
    else say(x.name + " is already on the list");
    buzz();
  }

  // ── usual: its sheet ─────────────────────────────────────────────────────
  function groupChips(s, sel) {
    return '<button type="button" class="sh-opt' + (!sel ? " on" : "") + '" data-u-group="" aria-pressed="' + !sel + '">None</button>' +
      s.groups.map(function (g) {
        return '<button type="button" class="sh-opt' + (sel === g.id ? " on" : "") + '" data-u-group="' + g.id + '" aria-pressed="' + (sel === g.id) + '">' + esc(g.name) + '</button>';
      }).join("") +
      '<button type="button" class="sh-opt add" data-g-inline>' + I.plus + 'New group</button>';
  }
  function picGrid(list, sel, attr, auto) {
    return (auto ? '<button type="button" class="auto' + (!sel ? " on" : "") + '" ' + attr + '="">Auto</button>' : '') +
      list.map(function (e) { return '<button type="button"' + (sel === e ? ' class="on"' : '') + ' ' + attr + '="' + e + '">' + e + '</button>'; }).join("");
  }
  function openUsual(id, preset) {
    var s = current(), x = id ? usual(s, id) : null;
    var d = x ? Object.assign({}, x) : { id: rid(), name: "", qty: "", cat: "", icon: "", group: preset || "" };
    openSheet({ kind: "usual", id: d.id, isNew: !x, draft: d, cat: x ? aisleOf(x.cat) : "",
      icon: x ? iconFor(x) : "🧺", title: x ? x.name : "Add to the pantry", sub: x ? "In the pantry" : "Something you buy all the time",
      body:
        '<div class="sh-ident"><button type="button" class="sh-pic" data-u-pic aria-expanded="false" aria-label="Change the picture">' + iconFor(d) + '</button>' +
          '<input class="sh-in" data-f="name" maxlength="80" enterkeyhint="done" autocapitalize="sentences" placeholder="What is it? — e.g. thickened cream" value="' + esc(d.name) + '"></div>' +
        '<div class="sh-picgrid" data-u-pics hidden>' + picGrid(STAPLE_ICONS, d.icon, "data-u-seticon", true) + '</div>' +
        field("Usual amount", amountHtml(d.qty), "what + puts on the list") +
        field("Group", '<div class="sh-opts" data-u-groups>' + groupChips(s, d.group) + '</div>' +
          '<div class="sh-inline" data-g-row hidden><input class="sh-in" data-g-name maxlength="40" placeholder="Group name — e.g. Baking" enterkeyhint="done">' +
          '<button type="button" class="sh-btn" data-g-make>Add</button></div>') +
        field("Aisle", '<div class="sh-opts">' + aisleChips(x ? aisleOf(x.cat) : "") + '</div>', x ? "" : "worked out from the name if you leave it"),
      foot: (x ? '<button type="button" class="sh-btn ghost bad" data-u-del>Delete</button>' : '') +
        '<button type="button" class="sh-btn go" data-u-save>' + (x ? "Save" : "Add to pantry") + '</button>',
      focus: x ? null : '[data-f="name"]' });
  }
  function saveUsualSheet() {
    var d = SH.draft, name = clean(SE.body.querySelector('[data-f="name"]').value);
    if (!name) { sheetErr("Give it a name."); SE.body.querySelector('[data-f="name"]').focus(); return; }
    var u = { id: d.id, name: cap(name), qty: amtRead(SE.body.querySelector("[data-amt]")), cat: SH.cat || categorise(name),
      icon: d.icon || "", group: d.group || "" };
    var isNew = SH.isNew;
    saveUsual(u);
    closeSheet(true);
    say(isNew ? "Added " + u.name + " to the pantry" : "Saved " + u.name);
  }

  // ── group: its sheet ─────────────────────────────────────────────────────
  function openGroup(id) {
    var s = current(), g = id ? group(s, id) : null;
    var members = g ? s.staples.filter(function (x) { return x.group === g.id; }) : [];
    openSheet({ kind: "group", id: g ? g.id : rid(), isNew: !g, icon: "🗂️", title: g ? g.name : "New group",
      sub: g ? plural(members.length, "thing", "things") : "Fridge, Baking, Cleaning… whatever suits",
      body: field("Name", '<input class="sh-in" data-f="name" maxlength="40" enterkeyhint="done" placeholder="e.g. Baking" value="' + esc(g ? g.name : "") + '">') +
        (members.length ? field("In it", '<div class="sh-mini">' + members.map(function (x) {
          return '<span>' + iconFor(x) + ' ' + esc(x.name) + '</span>'; }).join("") + '</div>', "deleting the group keeps these, with no group") : ""),
      foot: (g ? '<button type="button" class="sh-btn ghost bad" data-g-del>Delete group</button>' : '') +
        '<button type="button" class="sh-btn go" data-g-save>' + (g ? "Save" : "Create group") + '</button>',
      focus: g ? null : '[data-f="name"]' });
  }

  // ── the recipe book ──────────────────────────────────────────────────────
  // Its own tab: a tile per recipe in the colour of its food, its ingredients
  // as a strip of pictures, ✓ n when some are already on the list. Tap one →
  // its cook sheet (tick what's needed, add it to the list); + New → the editor.
  var R = null;
  function recipeShell() {
    var host = D.$("sh-recipes");
    if (!host) return null;
    if (R && host.contains(R.root)) return R;
    host.innerHTML =
      '<div class="sh-pane-in">' + hero("recipes") +
        '<div class="sh-bar">' +
          '<label class="sh-find">' + I.search + '<input class="sh-in" type="search" placeholder="Find a recipe" aria-label="Find a recipe or an ingredient"></label>' +
          '<button type="button" class="sh-btn go" data-r-new>' + I.plus + 'New</button>' +
        '</div>' +
        '<div class="shc-grid" data-r-list></div>' +
      '</div>';
    var root = host.firstElementChild;
    R = { root: root, bar: root.querySelector(".sh-bar"), find: root.querySelector(".sh-find input"), list: root.querySelector("[data-r-list]") };
    R.find.addEventListener("input", function () { ui.find = R.find.value; refresh(); });
    return R;
  }
  function recipeTile(s, r) {
    var icon = r.icon || "🍽️", have = 0, pics = [];
    r.ingredients.forEach(function (g) {
      if (!g.skip && onList(s, g.name)) have++;
      var p = iconFor(g);
      if (pics.indexOf(p) < 0) pics.push(p);
    });
    var more = r.ingredients.length - Math.min(5, pics.length);
    return '<button type="button" class="shc" data-r-open="' + r.id + '" style="--fh:' + foodHue(icon, r.name) + '" ' +
      'aria-label="' + esc(r.name + " — " + plural(r.ingredients.length, "ingredient", "ingredients") + (have ? ", " + have + " on the list" : "")) + '">' +
      '<span class="shc-big" aria-hidden="true">' + esc(icon) + '</span>' +
      '<span class="shc-plate" aria-hidden="true">' + esc(icon) + '</span>' +
      '<b>' + esc(r.name) + '</b>' +
      '<span class="shc-strip" aria-hidden="true">' + pics.slice(0, 5).join("") + (more > 0 ? '<i>+' + more + '</i>' : '') + '</span>' +
      (have ? '<span class="shc-on" aria-hidden="true">' + I.tick + have + '</span>' : '') + '</button>';
  }
  function drawRecipes(s) {
    var C = recipeShell();
    if (!C) return;
    var q = key(ui.find), rs = s.recipes;
    C.bar.classList.toggle("many", rs.length > 4 || !!ui.find);
    var shown = q ? rs.filter(function (r) {
      return key(r.name).indexOf(q) >= 0 || r.ingredients.some(function (g) { return key(g.name).indexOf(q) >= 0; });
    }) : rs;
    D.paint(C.list, !rs.length
      ? '<div class="shx-empty"><span aria-hidden="true">📖</span><b>No recipes yet</b>Add the meals you cook most — then one tap puts everything they need on the list.</div>'
      : !shown.length ? '<div class="shx-none">Nothing matches “' + esc(ui.find) + '”.</div>'
      : shown.map(function (r) { return recipeTile(s, r); }).join(""));
  }

  // ── the tabs ─────────────────────────────────────────────────────────────
  var TABS = [["list", "🛒", "List"], ["pantry", "🧺", "Pantry"], ["recipes", "📖", "Recipes"]];
  var TAB_IX = { list: 0, pantry: 1, recipes: 2 };
  function drawTabs(s) {
    if (!L) return;
    var left = s.items.filter(function (i) { return !i.done; }).length;
    L.tabs.forEach(function (b) {
      var k = b.getAttribute("data-sh-tab"), on = k === ui.tab, n = b.querySelector("[data-sh-tab-n]");
      b.classList.toggle("on", on);
      b.setAttribute("aria-selected", String(on));
      b.tabIndex = on ? 0 : -1;
      var txt = k === "list" && left ? String(left) : "";
      if (n.textContent !== txt) n.textContent = txt;
    });
    L.panes.forEach(function (p) { p.hidden = p.getAttribute("data-pane") !== ui.tab; });
  }
  // The trolley bar, under the list's heading: how far through the shop you are.
  function drawProg(s) {
    if (!L) return;
    var all = s.items.length, got = s.items.filter(function (i) { return i.done; }).length;
    L.prog.classList.toggle("all", !!all && got === all);
    D.paint(L.prog, !all ? '<span class="sh-prog-t">Nothing on it yet — add something below</span>' :
      '<span class="sh-prog-t">' + (got === all ? "All " + all + " in the trolley ✓" : '<b>' + got + '</b> of ' + all + ' in the trolley') + '</span>' +
      '<span class="sh-prog-bar" role="progressbar" aria-valuemin="0" aria-valuemax="' + all + '" aria-valuenow="' + got + '" aria-label="In the trolley">' +
        '<i style="width:' + Math.round(got / all * 100) + '%"></i></span>');
  }
  function setTab(k) {
    if (k === ui.tab || TAB_IX[k] == null || !L) return;
    var back = TAB_IX[k] < TAB_IX[ui.tab];
    ui.tab = k;
    ui.uPick = null;
    if (k !== "pantry") ui.uEdit = false;
    if (ui.step) stepFor(null);
    try { sessionStorage.setItem("sh-tab", k); } catch (_) {}
    render(); // now, so the pane is there to slide in
    var pane = L.root.querySelector('[data-pane="' + k + '"]');
    anim(pane, [{ transform: "translateX(" + (back ? -36 : 36) + "px)", opacity: 0 }, { transform: "none", opacity: 1 }], 280);
    // Switching from far down the list: bring the tabs (and the new tab's top) back into view.
    var bar = L.root.querySelector(".sh-tabs"), top = bar.getBoundingClientRect().top;
    if (top < 0) bar.scrollIntoView({ block: "start", behavior: CALM ? "auto" : "smooth" });
  }
  // A swipe across the card goes to the next tab (phones). Passive listeners
  // only — it never blocks scrolling — and it gives up the moment the finger
  // moves more up/down than across, or starts on something that scrolls
  // sideways itself (the group chips) or takes text.
  function swipe(root) {
    var x0 = 0, y0 = 0, t0 = 0, live = false, dead = true, pane = null;
    function lean(dx) {
      if (!pane || CALM) return;
      var edge = (dx > 0 && TAB_IX[ui.tab] === 0) || (dx < 0 && TAB_IX[ui.tab] === TABS.length - 1);
      pane.style.transform = "translateX(" + Math.max(-60, Math.min(60, dx * (edge ? 0.12 : 0.3))) + "px)";
    }
    function settle() {
      if (!pane) return;
      var p = pane; pane = null;
      if (!p.style.transform) return;
      p.style.transition = "transform 0.2s cubic-bezier(.2,.7,.2,1)";
      p.style.transform = "";
      setTimeout(function () { p.style.transition = ""; }, 220);
    }
    root.addEventListener("touchstart", function (e) {
      var t = e.target;
      dead = e.touches.length !== 1 || !!(t.closest && t.closest("input, textarea, select, .sh-opts.scroll, .sh-stepper, .sh-tabs"));
      if (dead) return;
      live = false;
      x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; t0 = Date.now();
      pane = root.querySelector('[data-pane="' + ui.tab + '"]');
    }, { passive: true });
    root.addEventListener("touchmove", function (e) {
      if (dead) return;
      var dx = e.touches[0].clientX - x0, dy = e.touches[0].clientY - y0;
      if (!live) {
        if (Math.abs(dy) > 10 && Math.abs(dy) >= Math.abs(dx)) { dead = true; settle(); return; }
        if (Math.abs(dx) > 14) live = true;
      }
      if (live) lean(dx);
    }, { passive: true });
    root.addEventListener("touchend", function (e) {
      if (dead) return;
      dead = true;
      var t = e.changedTouches[0], dx = t.clientX - x0, dy = t.clientY - y0, quick = Date.now() - t0 < 350;
      var go = live && Math.abs(dx) > 1.5 * Math.abs(dy) && (Math.abs(dx) > 70 || (quick && Math.abs(dx) > 40));
      var next = go && TABS[TAB_IX[ui.tab] + (dx < 0 ? 1 : -1)];
      if (!next) { settle(); return; }
      if (pane) { pane.style.transform = ""; pane = null; }
      setTab(next[0]);
      buzz();
    }, { passive: true });
    root.addEventListener("touchcancel", function () { dead = true; settle(); }, { passive: true });
  }

  // ── cook: a recipe, to shop for ──────────────────────────────────────────
  // Everything ticked to start; untick what's in the cupboard. What's already
  // on the list says so — adding it adds to it, and the list flags it ⚑ so
  // whoever's shopping decides if both lots are really needed.
  function openCook(id) {
    var s = current(), r = recipe(s, id);
    if (!r) return;
    // Opened empty, then painted: cookBody reads SH.off, which is the new sheet's.
    var off = {};
    r.ingredients.forEach(function (g, i) { if (g.skip) off[i] = true; }); // usually have: unticked to start
    openSheet({ kind: "cook", id: id, off: off, icon: r.icon || "🍽️", title: r.name,
      sub: plural(r.ingredients.length, "ingredient", "ingredients") + (r.used ? " · shopped for " + times(r.used).replace("twice", "2 times") : ""),
      body: "", foot: "" });
    paintSheet(s);
  }
  function cookBody(s, r) {
    function row(g, i) {
      var on = !SH.off[i], have = onList(s, g.name);
      return '<button type="button" class="shx-check' + (on ? " on" : "") + (g.skip ? " have" : "") + '" role="listitem" data-cook-ing="' + i + '" aria-pressed="' + on + '">' +
        '<span class="sh-box" aria-hidden="true">' + I.check + '</span>' +
        '<span class="shx-pic sm" aria-hidden="true">' + iconFor(g) + '</span>' +
        '<span class="shx-t"><b>' + esc(g.name) + '</b>' +
          (have && on ? '<small class="warn">' + I.flag + 'On the list' + (have.qty ? ' · ' + esc(have.qty) : '') + ' — this adds to it</small>'
            : g.skip ? '<small>' + (on ? "Adding it this time" : "Tap if you\'ve run out") + '</small>' : '') + '</span>' +
        (g.qty ? '<span class="sh-qty">' + esc(g.qty) + '</span>' : '') + '</button>';
    }
    var main = "", kept = "";
    r.ingredients.forEach(function (g, i) { if (g.skip) kept += row(g, i); else main += row(g, i); });
    return '<p class="sh-lede">Untick anything that\'s already in the cupboard.</p>' +
      (main ? '<div class="shx-list" role="list">' + main + '</div>' : '') +
      (kept ? '<div class="sh-have-h"><span aria-hidden="true">🫙</span>Usually have — not added</div><div class="shx-list" role="list">' + kept + '</div>' : '') +
      (r.note ? '<div class="sh-note">' + esc(r.note) + '</div>' : '');
  }
  function cookFoot(r) {
    var n = r.ingredients.filter(function (g, i) { return !SH.off[i]; }).length;
    return '<button type="button" class="sh-btn ghost" data-cook-edit>' + I.pencil + 'Edit</button>' +
      '<button type="button" class="sh-btn ghost" data-cook-all>' + (mainOn(r) ? "None" : "All") + '</button>' +
      '<button type="button" class="sh-btn go" data-cook-add' + (n ? "" : " disabled") + '>' + (n ? "Add " + n + " to the list" : "Nothing ticked") + '</button>';
  }

  // All / None only touch what you'd normally buy; the "usually have" ones
  // change one tap at a time.
  function mainOn(r) { return r.ingredients.every(function (g, i) { return g.skip || !SH.off[i]; }); }

  // ── recipe: the editor ───────────────────────────────────────────────────
  // A row per ingredient (picture, name, amount — tap to change, × to drop);
  // under them a composer: what it is, − amount + and the unit, Add. "300ml
  // cream" typed straight into the name works too, and a whole list can be
  // pasted in one go.
  function openRecipeEditor(id) {
    var s = current(), r = id ? recipe(s, id) : null;
    var d = r ? { id: r.id, name: r.name, icon: r.icon || "🍝", note: r.note || "", used: r.used,
      ingredients: r.ingredients.map(function (g) { return Object.assign({}, g); }) }
      : { id: rid(), name: "", icon: "🍝", note: "", ingredients: [] };
    openSheet({ kind: "recipe", id: d.id, isNew: !r, draft: d, ingEdit: -1, icon: "📝",
      title: r ? "Edit recipe" : "New recipe", sub: r ? r.name : "Name it, then add what it needs",
      body:
        '<div class="sh-ident"><button type="button" class="sh-pic" data-r-pic aria-expanded="false" aria-label="Change the picture">' + esc(d.icon) + '</button>' +
          '<input class="sh-in" data-f="name" maxlength="80" enterkeyhint="next" autocapitalize="sentences" placeholder="What\'s it called?" value="' + esc(d.name) + '"></div>' +
        '<div class="sh-picgrid" data-r-pics hidden>' + picGrid(EMOJI, d.icon, "data-r-seticon", false) + '</div>' +
        '<div class="sh-field"><span class="sh-label">Ingredients <i data-ing-count></i></span>' +
          '<p class="sh-hint" data-ing-hint>Ticked ones go on the list. Untick what you always have — spices, sauces, oil.</p>' +
          '<div class="shx-list" role="list" data-ing-list></div>' +
          '<div class="sh-compose" data-ing-compose>' +
            '<span class="sh-compose-h">' + I.plus + 'Add an ingredient</span>' +
            '<input class="sh-in" data-ing-name maxlength="80" enterkeyhint="done" autocapitalize="sentences" placeholder="What — e.g. thickened cream">' +
            amountHtml("", "How much") +
            '<button type="button" class="sh-btn go" data-ing-add>' + I.plus + 'Add ingredient</button>' +
          '</div>' +
          '<button type="button" class="sh-link" data-ing-paste>Paste a whole list instead</button>' +
          '<div class="sh-paste" data-ing-pastebox hidden>' +
            '<textarea class="sh-in" rows="5" placeholder="One a line:&#10;300mL thickened cream&#10;2 onions&#10;garlic"></textarea>' +
            '<button type="button" class="sh-btn" data-ing-paste-go>Add these</button>' +
          '</div>' +
        '</div>' +
        field("Notes", '<textarea class="sh-in" data-f="note" rows="3" maxlength="600" placeholder="Serves 4 · white wine always makes it better">' + esc(d.note) + '</textarea>', "optional"),
      foot: (r ? '<button type="button" class="sh-btn ghost bad" data-r-del>Delete</button>' : '') +
        '<button type="button" class="sh-btn go" data-r-save>' + (r ? "Save" : "Save recipe") + '</button>',
      focus: r ? null : '[data-f="name"]' });
    paintIngredients();
  }
  function paintIngredients(focusIdx) {
    var d = SH.draft, box = SE.body.querySelector("[data-ing-list]");
    SE.body.querySelector("[data-ing-count]").textContent = d.ingredients.length ? String(d.ingredients.length) : "";
    SE.body.querySelector("[data-ing-hint]").hidden = !d.ingredients.length;
    box.innerHTML = !d.ingredients.length ? '<div class="shx-none">Nothing yet — add the first one below.</div>' :
      d.ingredients.map(function (g, i) {
        if (SH.ingEdit === i) {
          return '<div class="shx-ed" role="listitem" data-ing-row="' + i + '">' +
            '<input class="sh-in" data-ing-ename maxlength="80" enterkeyhint="done" aria-label="Ingredient" value="' + esc(g.name) + '">' +
            amountHtml(g.qty, "How much") +
            '<div class="sh-act"><button type="button" class="sh-btn ghost bad sm" data-ing-del="' + i + '">Remove</button>' +
              '<button type="button" class="sh-btn go sm" data-ing-done>Done</button></div></div>';
        }
        return '<div class="shx-row' + (g.skip ? " have" : "") + '" role="listitem" data-ing-row="' + i + '">' +
          '<button type="button" class="shx-tick' + (g.skip ? "" : " on") + '" data-ing-skip="' + i + '" aria-pressed="' + !g.skip + '" ' +
            'aria-label="' + esc(g.skip ? g.name + ": usually have it — tap to buy it with the recipe" : g.name + ": bought with the recipe — tap if you usually have it") + '">' +
            '<span class="sh-box" aria-hidden="true">' + I.check + '</span></button>' +
          '<button type="button" class="shx-main" data-ing-edit="' + i + '" aria-label="' + esc("Change " + g.name) + '">' +
            '<span class="shx-pic sm" aria-hidden="true">' + iconFor(g) + '</span><span class="shx-t"><b>' + esc(g.name) + '</b>' +
            (g.skip ? '<small class="sh-have"><span aria-hidden="true">🫙</span>Usually have — not added</small>' : '') + '</span>' +
            (g.qty ? '<span class="sh-qty">' + esc(g.qty) + '</span>' : '') + '</button>' +
          '<button type="button" class="shx-btn del" data-ing-del="' + i + '" aria-label="' + esc("Drop " + g.name) + '">' + I.x + '</button></div>';
      }).join("");
    if (focusIdx != null) { var f = box.querySelector('[data-ing-row="' + focusIdx + '"] [data-ing-ename]'); if (f) f.focus(); }
  }
  // The open row's edits, back into the draft.
  function commitIng() {
    var i = SH.ingEdit, row = i >= 0 && SE.body.querySelector('[data-ing-row="' + i + '"]');
    if (!row) return;
    var g = SH.draft.ingredients[i], name = clean(row.querySelector("[data-ing-ename]").value);
    if (name) { g.name = cap(name); g.cat = categorise(name); }
    g.qty = amtRead(row.querySelector("[data-amt]"));
    SH.ingEdit = -1;
  }
  function addIngredient() {
    var c = SE.body.querySelector("[data-ing-compose]"), inp = c.querySelector("[data-ing-name]"), raw = clean(inp.value);
    if (!raw) { inp.focus(); c.classList.remove("nudge"); void c.offsetWidth; c.classList.add("nudge"); return; }
    var amt = amtRead(c.querySelector("[data-amt]")), p = parse(raw) || { name: cap(raw), qty: "" };
    SH.draft.ingredients.push({ name: p.name, qty: amt || p.qty, cat: categorise(p.name) });
    commitIng();
    inp.value = "";
    amtShow(c.querySelector("[data-amt]"), "");
    markDirty();
    paintIngredients();
    inp.focus();
  }
  function saveRecipeSheet() {
    commitIng();
    var d = SH.draft, name = clean(SE.body.querySelector('[data-f="name"]').value);
    if (!name) { sheetErr("Give it a name."); SE.body.querySelector('[data-f="name"]').focus(); return; }
    var pending = clean(SE.body.querySelector("[data-ing-name]").value);
    if (pending) addIngredient(); // typed but not added yet — that's still meant
    if (!d.ingredients.length) { sheetErr("Add at least one ingredient."); SE.body.querySelector("[data-ing-name]").focus(); return; }
    var rec = { id: d.id, name: cap(name), icon: d.icon, note: clean(SE.body.querySelector('[data-f="note"]').value),
      ingredients: d.ingredients.map(function (g) {
        var o = { name: g.name, qty: g.qty || "", cat: g.cat || categorise(g.name) };
        if (g.skip) o.skip = true;
        return o;
      }) };
    if (d.used) rec.used = d.used;
    var isNew = SH.isNew;
    saveRecipe(rec);
    closeSheet(true);
    say(isNew ? "Added " + rec.name + " to your recipes — tap it to shop for it" : "Saved " + rec.name);
  }

  // ── the toast (one at a time, with Undo when there is something to undo) ─
  var toast = null, toastT = null, undoFn = null;
  function say(msg, o) {
    o = o || {};
    if (!toast) {
      toast = document.createElement("div");
      toast.className = "sh-toast";
      toast.setAttribute("role", "status");
      document.body.appendChild(toast); // not in a card: a backdrop-filter there would trap position:fixed
      toast.addEventListener("click", function (e) {
        if (e.target.closest("[data-sh-undo]") && undoFn) { var f = undoFn; undoFn = null; f(); hide(); }
      });
    }
    undoFn = o.undo || null;
    toast.className = "sh-toast" + (o.bad ? " bad" : "");
    toast.innerHTML = '<span>' + esc(msg) + '</span>' + (undoFn ? '<button type="button" data-sh-undo>Undo</button>' : '');
    placeToast();
    toast.classList.add("show");
    clearTimeout(toastT);
    toastT = setTimeout(hide, undoFn ? 6500 : o.bad ? 6000 : 3000);
  }
  function hide() { clearTimeout(toastT); if (toast) toast.classList.remove("show"); undoFn = null; }
  // Above Glance's phone bar when it's showing — measured from the bar's TOP
  // edge: the .mobile-navigation box also holds its ☰ drawer, parked below the
  // screen, so its height is ~600px, not the bar's 50. While a sheet is open
  // the toast sits at the top instead, clear of the sheet's buttons — and
  // openSheet/closeSheet call this too, so one already showing moves with it.
  function placeToast() {
    if (!toast) return;
    var nav = document.querySelector(".mobile-navigation"), lift = 0;
    if (nav && getComputedStyle(nav).display !== "none") lift = Math.max(0, window.innerHeight - nav.getBoundingClientRect().top);
    toast.classList.toggle("top", !!SH);
    toast.style.bottom = SH ? "" : Math.round(lift + 14) + "px";
  }

  // ── input ────────────────────────────────────────────────────────────────
  function buzz() { try { if (navigator.vibrate) navigator.vibrate(8); } catch (_) {} }
  // An open − / + on a row folds back into its pill after a few quiet
  // seconds, or at the first tap anywhere else.
  function stepFor(id) {
    clearTimeout(ui.stepT);
    ui.step = id;
    ui.stepT = id ? setTimeout(function () { ui.step = null; refresh(); }, 4000) : null;
    refresh();
  }
  function remember(k, v) { try { localStorage.setItem(k, v); } catch (_) {} }

  function onClick(e) {
    var t = e.target;
    if (!t.closest) return;
    if (SE && SE.root.contains(t)) { onSheetClick(t); return; }
    if (ui.step && !t.closest(".sh-stepper")) stepFor(null);
    var tab = t.closest("[data-sh-tab]");
    if (tab) { setTab(tab.getAttribute("data-sh-tab")); return; }
    // The panes live inside the list card: route them before the list.
    if (t.closest("#sh-usuals")) { onUsualClick(t); return; }
    if (t.closest("#sh-recipes")) { onRecipeClick(t); return; }
    if (t.closest("#sh-list")) onListClick(t);
  }

  function onListClick(t) {
    var el, row = t.closest("[data-id]"), id = row && row.getAttribute("data-id");
    if (t.closest("[data-sh-flag]") && id) { openFlag(id); return; } // inside the tick: first
    if (t.closest("[data-sh-step-open]") && id) {
      stepFor(id);
    } else if ((el = t.closest("[data-sh-step]")) && id) {
      var cur = byId(current(), id), nq = cur && stepQty(cur.qty, +el.getAttribute("data-sh-step"));
      if (nq) { edit(id, { qty: nq }); buzz(); }
      stepFor(id);
    } else if (t.closest("[data-sh-tick]") && id) {
      var it = byId(current(), id);
      if (it) { toggle(id, !it.done); if (!it.done) buzz(); }
    } else if (t.closest("[data-sh-edit]") && id) {
      openItem(id);
    } else if ((el = t.closest("[data-sh-quick]"))) {
      addItems([{ name: el.getAttribute("data-sh-quick"), qty: el.getAttribute("data-qty") || "" }]);
      if (L) { var parts = L.input.value.split(/[,;]/); parts.pop(); L.input.value = parts.length ? parts.join(",") + ", " : ""; ui.typed = L.input.value; L.input.focus(); }
      buzz();
      refresh();
    } else if (t.closest("[data-sh-got]")) {
      ui.got = !ui.got;
      remember("sh-got", ui.got ? "open" : "closed");
      refresh();
    } else if (t.closest("[data-sh-clear]")) {
      clear("done");
    } else if (t.closest("[data-sh-clearall]")) {
      if (Date.now() - ui.clearArm < 3000) { ui.clearArm = 0; clear("all"); }
      else { ui.clearArm = Date.now(); setTimeout(refresh, 3050); }
      refresh();
    }
  }

  function onUsualClick(t) {
    var el, s = current();
    if ((el = t.closest("[data-u-filter]"))) {
      ui.uGroup = el.getAttribute("data-u-filter");
      ui.uPick = null;
      remember("sh-usual-group", ui.uGroup);
      refresh();
    } else if (t.closest("[data-u-edit]")) {
      ui.uEdit = !ui.uEdit; ui.uPick = null;
      refresh();
    } else if ((el = t.closest("[data-u-quick]"))) {
      var q = usual(s, el.getAttribute("data-u-quick"));
      if (q) addUsual(q, q.qty || "");
    } else if ((el = t.closest("[data-u-pick]"))) {
      var pk = usual(s, el.getAttribute("data-u-pick"));
      if (!pk) return;
      if (ui.uPick === pk.id) ui.uPick = null;
      else { ui.uPick = pk.id; ui.uAmt = pk.qty || ""; }
      refresh();
    } else if ((el = t.closest("[data-u-step]"))) {
      var nq = stepQty(ui.uAmt, +el.getAttribute("data-u-step"));
      if (nq) { ui.uAmt = nq; buzz(); refresh(); }
    } else if ((el = t.closest("[data-u-add]"))) {
      var ad = usual(s, el.getAttribute("data-u-add"));
      if (ad) addUsual(ad, ui.uAmt);
      ui.uPick = null;
      refresh();
    } else if ((el = t.closest("[data-u-open]"))) {
      openUsual(el.getAttribute("data-u-open"));
    } else if ((el = t.closest("[data-g-open]"))) {
      openGroup(el.getAttribute("data-g-open"));
    } else if (t.closest("[data-g-new]")) {
      openGroup(null);
    } else if (t.closest("[data-u-new]")) {
      openUsual(null, ui.uGroup !== "all" && ui.uGroup !== "none" ? ui.uGroup : "");
    }
  }

  function onRecipeClick(t) {
    var el;
    if ((el = t.closest("[data-r-open]"))) {
      openCook(el.getAttribute("data-r-open"));
    } else if (t.closest("[data-r-new]")) {
      openRecipeEditor(null);
    }
  }

  function onSheetClick(t) {
    var el, b = SE.body;
    if (t === SE.root) { closeSheet(); return; } // the scrim, outside the sheet
    if (t.closest("[data-sheet-close]")) { closeSheet(); return; }
    if ((el = t.closest("[data-amt-step]"))) { amtStep(el); return; }
    if ((el = t.closest("[data-amt-unit]"))) { amtUnit(el); return; }
    if ((el = t.closest("[data-pick-cat]"))) {
      SH.cat = el.getAttribute("data-pick-cat");
      el.parentNode.querySelectorAll("[data-pick-cat]").forEach(function (x) {
        var on = x === el; x.classList.toggle("on", on); x.setAttribute("aria-pressed", String(on));
      });
      markDirty();
      return;
    }
    var it, s = current();
    switch (SH.kind) {
      case "item":
        if (t.closest("[data-item-save]")) saveItem();
        else if ((el = t.closest("[data-item-del]"))) {
          var gone = SH.id;
          closeSheet(true);
          remove([gone]);
        } else if ((el = t.closest("[data-item-usual]"))) {
          it = byId(s, SH.id);
          if (!it) return;
          var name = clean(b.querySelector('[data-f="name"]').value) || it.name, was = usualOf(s, name);
          if (was) { deleteUsual(was); el.textContent = "☆ Add to pantry"; el.setAttribute("aria-pressed", "false"); }
          else {
            saveUsual({ id: rid(), name: cap(name), qty: amtRead(b.querySelector("[data-amt]")), cat: SH.cat, icon: "", group: "" });
            el.textContent = "★ In the pantry"; el.setAttribute("aria-pressed", "true");
            say(cap(name) + " is in the pantry now");
          }
        }
        return;
      case "flag":
        it = byId(s, SH.id);
        if (!it) { closeSheet(true); return; }
        if (t.closest("[data-flag-all]")) {
          edit(it.id, { settled: true });
          closeSheet(true);
          say(it.name + ": getting " + (it.qty || "both"));
        } else if (t.closest("[data-flag-one]")) {
          var one = justOne(it);
          edit(it.id, { qty: one, settled: true });
          closeSheet(true);
          say(it.name + ": just " + (one || "one"));
        } else if (t.closest("[data-flag-other]")) {
          closeSheet(true);
          openItem(it.id);
        }
        return;
      case "usual":
        if (t.closest("[data-u-save]")) saveUsualSheet();
        else if ((el = t.closest("[data-u-del]"))) {
          var u = usual(s, SH.id);
          if (u && armed(el, "Tap again to delete")) { closeSheet(true); deleteUsual(u); }
        } else if (t.closest("[data-u-pic]")) {
          var grid = b.querySelector("[data-u-pics]");
          grid.hidden = !grid.hidden;
          b.querySelector("[data-u-pic]").setAttribute("aria-expanded", String(!grid.hidden));
        } else if ((el = t.closest("[data-u-seticon]"))) {
          SH.draft.icon = el.getAttribute("data-u-seticon");
          b.querySelector("[data-u-pic]").textContent = iconFor({ name: clean(b.querySelector('[data-f="name"]').value), cat: SH.cat, icon: SH.draft.icon });
          el.parentNode.querySelectorAll("button").forEach(function (x) { x.classList.toggle("on", x === el); });
          el.parentNode.hidden = true;
          markDirty();
        } else if ((el = t.closest("[data-u-group]"))) {
          SH.draft.group = el.getAttribute("data-u-group");
          el.parentNode.querySelectorAll("[data-u-group]").forEach(function (x) {
            var on = x === el; x.classList.toggle("on", on); x.setAttribute("aria-pressed", String(on));
          });
          markDirty();
        } else if (t.closest("[data-g-inline]")) {
          var row = b.querySelector("[data-g-row]");
          row.hidden = false;
          row.querySelector("input").focus();
        } else if (t.closest("[data-g-make]")) {
          makeGroupInline();
        }
        return;
      case "group":
        if (t.closest("[data-g-save]")) {
          var gname = clean(b.querySelector('[data-f="name"]').value);
          if (!gname) { sheetErr("Give the group a name."); return; }
          var isNew = SH.isNew, gid = SH.id;
          saveGroup({ id: gid, name: gname });
          closeSheet(true);
          if (isNew) { ui.uGroup = gid; remember("sh-usual-group", gid); say("Made the " + gname + " group — add things to it"); }
        } else if ((el = t.closest("[data-g-del]"))) {
          var g = group(s, SH.id);
          if (g && armed(el, "Tap again to delete")) { closeSheet(true); deleteGroup(g); }
        }
        return;
      case "cook":
        var r = recipe(s, SH.id);
        if (!r) { closeSheet(true); return; }
        if ((el = t.closest("[data-cook-ing]"))) {
          var i = +el.getAttribute("data-cook-ing");
          if (SH.off[i]) delete SH.off[i]; else SH.off[i] = true;
          refresh();
        } else if (t.closest("[data-cook-all]")) {
          var allOn = mainOn(r);
          r.ingredients.forEach(function (g, j) { if (!g.skip) { if (allOn) SH.off[j] = true; else delete SH.off[j]; } });
          refresh();
        } else if (t.closest("[data-cook-edit]")) {
          closeSheet(true);
          openRecipeEditor(r.id);
        } else if (t.closest("[data-cook-add]")) {
          var pick = r.ingredients.filter(function (g, j) { return !SH.off[j]; });
          if (!pick.length) return;
          var res = addItems(pick.map(function (g) { return { name: cap(g.name), qty: g.qty, cat: g.cat && g.cat !== "other" ? g.cat : undefined }; }),
            { from: r.name, recipe: r.id });
          closeSheet(true);
          say("Added " + plural(pick.length, "thing", "things") + " for " + r.name +
            (res.dup.length ? " · " + res.dup.length + " already on the list — ⚑ to check" : ""),
            res.fresh.length ? { undo: function () { remove(res.fresh, "Took them back off"); } } : {});
          buzz();
        }
        return;
      case "recipe":
        if (t.closest("[data-r-save]")) saveRecipeSheet();
        else if ((el = t.closest("[data-r-del]"))) {
          var rr = recipe(s, SH.id);
          if (rr && armed(el, "Tap again to delete")) { closeSheet(true); deleteRecipe(rr); }
        } else if (t.closest("[data-r-pic]")) {
          var pg = b.querySelector("[data-r-pics]");
          pg.hidden = !pg.hidden;
          b.querySelector("[data-r-pic]").setAttribute("aria-expanded", String(!pg.hidden));
        } else if ((el = t.closest("[data-r-seticon]"))) {
          SH.draft.icon = el.getAttribute("data-r-seticon");
          b.querySelector("[data-r-pic]").textContent = SH.draft.icon;
          el.parentNode.querySelectorAll("button").forEach(function (x) { x.classList.toggle("on", x === el); });
          el.parentNode.hidden = true;
          markDirty();
        } else if (t.closest("[data-ing-add]")) {
          addIngredient();
        } else if ((el = t.closest("[data-ing-skip]"))) {
          commitIng();
          var sg = SH.draft.ingredients[+el.getAttribute("data-ing-skip")];
          if (sg) { if (sg.skip) delete sg.skip; else sg.skip = true; }
          markDirty();
          paintIngredients();
        } else if ((el = t.closest("[data-ing-edit]"))) {
          commitIng();
          SH.ingEdit = +el.getAttribute("data-ing-edit");
          paintIngredients(SH.ingEdit);
        } else if (t.closest("[data-ing-done]")) {
          commitIng();
          markDirty();
          paintIngredients();
        } else if ((el = t.closest("[data-ing-del]"))) {
          commitIng();
          SH.draft.ingredients.splice(+el.getAttribute("data-ing-del"), 1);
          markDirty();
          paintIngredients();
        } else if (t.closest("[data-ing-paste]")) {
          var pb = b.querySelector("[data-ing-pastebox]");
          pb.hidden = !pb.hidden;
          if (!pb.hidden) pb.querySelector("textarea").focus();
        } else if (t.closest("[data-ing-paste-go]")) {
          var ta = b.querySelector("[data-ing-pastebox] textarea");
          String(ta.value).split("\n").map(parse).filter(Boolean).forEach(function (g) {
            SH.draft.ingredients.push({ name: g.name, qty: g.qty, cat: categorise(g.name) });
          });
          ta.value = "";
          b.querySelector("[data-ing-pastebox]").hidden = true;
          markDirty();
          paintIngredients();
        }
        return;
    }
  }
  // "+ New group" from inside a usual's sheet: make it and pick it.
  function makeGroupInline() {
    var row = SE.body.querySelector("[data-g-row]"), name = clean(row.querySelector("input").value);
    if (!name) { row.querySelector("input").focus(); return; }
    var s = current(), had = s.groups.filter(function (g) { return g.name.toLowerCase() === name.toLowerCase(); })[0];
    var g = had || { id: rid(), name: name };
    if (!had) saveGroup(g);
    SH.draft.group = g.id;
    row.querySelector("input").value = "";
    row.hidden = true;
    // drawn from the optimistic state, which already has the new group
    SE.body.querySelector("[data-u-groups]").innerHTML = groupChips(current(), g.id);
    markDirty();
  }

  function onKey(e) {
    var t = e.target;
    if (!t.closest) return;
    var tab = t.closest("[data-sh-tab]");
    if (tab && (e.key === "ArrowLeft" || e.key === "ArrowRight" || e.key === "Home" || e.key === "End")) {
      e.preventDefault();
      var i = TAB_IX[ui.tab], n = TABS.length;
      i = e.key === "Home" ? 0 : e.key === "End" ? n - 1 : (i + (e.key === "ArrowRight" ? 1 : n - 1)) % n;
      setTab(TABS[i][0]);
      var b = L && L.root.querySelector('[data-sh-tab="' + TABS[i][0] + '"]');
      if (b) b.focus();
      return;
    }
    if (SH && SE.root.contains(t)) {
      if (e.key === "Escape") { e.preventDefault(); closeSheet(); return; }
      if (e.key !== "Enter" || t.tagName === "TEXTAREA") return;
      e.preventDefault();
      if (t.closest("[data-ing-compose]")) addIngredient();
      else if (t.closest(".shx-ed")) { commitIng(); markDirty(); paintIngredients(); }
      else if (t.closest("[data-g-row]")) makeGroupInline();
      else if (SH.kind === "recipe" && t.matches('[data-f="name"]')) SE.body.querySelector("[data-ing-name]").focus();
      else { var go = SE.foot.querySelector(".sh-btn.go:not(:disabled)"); if (go) go.click(); }
      return;
    }
    if (e.key === "Escape" && L && t === L.input) { L.input.value = ""; ui.typed = ""; refresh(); }
  }
  function onInput(e) {
    var t = e.target;
    if (!SH || !SE || !SE.root.contains(t)) return;
    markDirty();
    // A usual's picture follows its name until one is picked.
    if (SH.kind === "usual" && t.matches('[data-f="name"]') && !SH.draft.icon) {
      SE.body.querySelector("[data-u-pic]").textContent = iconFor({ name: t.value || "?", cat: SH.cat });
    }
  }

  // ── go ───────────────────────────────────────────────────────────────────
  function render() {
    queued = false;
    var s = current();
    if (!s) return;
    drawList(s); // first: it builds the card the tabs and the trolley bar live in
    drawTabs(s);
    drawProg(s);
    drawUsuals(s);
    drawRecipes(s);
    paintSheet(s);
  }
  function refresh() { if (!queued) { queued = true; requestAnimationFrame(render); } }

  D.ready("#sh-list", function () {
    D.stream(API + "/events", { state: function (s) { take(s); kick(); } }, "sh-live");
    document.addEventListener("click", onClick);
    document.addEventListener("keydown", onKey);
    document.addEventListener("input", onInput);
    // rAF doesn't run in a hidden tab; draw what came in while it was hidden.
    document.addEventListener("visibilitychange", function () { if (!document.hidden) render(); });
  });
})();
