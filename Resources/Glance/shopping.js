// shopping.js — the shared shopping list and recipe book, on BOTH dashboards.
//
// ONE card (#sh-list — one card to run down in the shop), painted from
// shopping-list's /events stream (Resources/Shopping-List/shopping-list.py,
// :9558), top to bottom:
//
//   adding       an add box (a comma adds several — "milk, eggs, 2 onions"),
//                the usuals one tap away, and the recipe book (#sh-recipes,
//                built inside this card) folded to one bar until tapped open,
//                remembered per browser: tap a recipe, untick what you've
//                already got, "Add 7 to the list"; + New recipe / Edit, one
//                ingredient a line
//   the list     grouped by aisle in the order you walk a supermarket, ticked
//                things sinking into "In the trolley", ⋯ on a row to fix its
//                name, quantity or aisle, Undo after anything that removes
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
    ["pantry", "🥫", "Pantry"],
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
    ["pack", "pack"], ["tin", "tin"], ["bottle", "bottle"], ["bunch", "bunch"]];
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
  var ui = { edit: null, cook: null, off: {}, rEdit: null, rArm: 0, clearArm: 0, typed: "", find: "", got: true, rOpen: false,
    step: null, stepT: null, sOpen: false, sEdit: false, sPick: null, sAmt: "", sIcon: null };
  try {
    ui.got = localStorage.getItem("sh-got") !== "closed";
    ui.rOpen = localStorage.getItem("sh-recipes") === "open";
    ui.sOpen = localStorage.getItem("sh-staples") === "open";
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
    send("items/edit", body, function (st) { var it = byId(st, id); if (it) Object.assign(it, changes); });
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

  // Cupboard staples: one per name — the server folds a save onto an existing
  // staple of the same name (key()), and so does this.
  function stapleOf(s, name) {
    var k = key(name);
    for (var i = 0; i < s.staples.length; i++) if (key(s.staples[i].name) === k) return s.staples[i];
    return null;
  }
  function saveStaple(st) {
    send("staples/save", st, function (s) {
      var k = key(st.name), keep = null;
      s.staples = s.staples.filter(function (x) {
        if (x.id === st.id || key(x.name) === k) { keep = x; return false; }
        return true;
      }).concat([Object.assign({}, keep && !("icon" in st) ? { icon: keep.icon || "" } : {}, st, keep ? { id: keep.id } : {})]);
    });
  }
  function deleteStaple(st) {
    send("staples/delete", { id: st.id }, function (s) {
      s.staples = s.staples.filter(function (x) { return x.id !== st.id; });
    });
    say("Took " + st.name + " out of the staples", { undo: function () { saveStaple(st); } });
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
    search: svg('<circle cx="11" cy="11" r="6"/><path d="M20 20l-4.5-4.5"/>')
  };
  var EMOJI = ("🍝 🍛 🍜 🍲 🥘 🫕 🍳 🥗 🌮 🌯 🫔 🥙 🧆 🍕 🍔 🌭 🍟 🥪 🍗 🍖 🥩 🥓 🐟 🍤 🦐 🦀 🍣 🍱 🍙 🥟 🍢 🍚 🥞 🧇 " +
    "🥐 🥯 🍞 🥖 🧀 🥚 🍰 🧁 🍪 🥧 🍩 🍨 🥣 🍎 🍓 🍌 🥦 🥕 🌽 🌶️ 🥑 🍄 🥔 🍠 🎃 🌿 🍽️").split(" ");

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
        '<form class="sh-add" autocomplete="off" data-sh-add>' +
          '<input class="sh-in" type="text" maxlength="300" placeholder="Add to the list… (milk, eggs, 2 onions)" ' +
            'aria-label="Add to the shopping list" enterkeyhint="done" autocapitalize="sentences">' +
          '<button class="sh-plus" type="submit" aria-label="Add">' + I.plus + '</button>' +
        '</form>' +
        '<div class="sh-chips" data-sh-chips></div>' +
        // The recipe book lives IN this card, folded to one bar: one card to
        // run down in the shop, with everything for adding at its top.
        '<div class="sh-staples" id="sh-staples"></div>' +
        '<div class="sh-recipes" id="sh-recipes"></div>' +
        '<div class="sh-list" role="list" data-sh-items></div>' +
        '<div class="sh-foot" data-sh-foot></div>' +
      '</div>';
    var root = host.firstElementChild;
    L = { root: root, form: root.querySelector("[data-sh-add]"), input: root.querySelector(".sh-add .sh-in"),
      chips: root.querySelector("[data-sh-chips]"), list: root.querySelector("[data-sh-items]"),
      foot: root.querySelector("[data-sh-foot]"), first: true };
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
  function rowNode(it) {
    var meta = "";
    if (it.from) meta += '<span class="sh-from">' + esc((icons[it.from.split(",")[0].trim()] || "🍳") + " " + it.from) + '</span>';
    if (it.by && it.by !== WHO) meta += '<span class="sh-by" title="' + esc("Added by " + it.by) + '">' + esc(it.by) + '</span>';
    var open = ui.edit === it.id;
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
      '<div class="sh-row' + (it.done ? " done" : "") + (open ? " editing" : "") + '" role="listitem" data-k="i:' + it.id + '" data-id="' + it.id + '">' +
        '<button type="button" class="sh-main" data-sh-tick aria-pressed="' + !!it.done + '" ' +
          'aria-label="' + esc((it.done ? "Put back: " : "Got it: ") + it.name) + '">' +
          '<span class="sh-box" aria-hidden="true">' + I.check + '</span>' +
          '<span class="sh-txt"><span class="sh-name">' + esc(it.name) + '</span>' + (meta ? '<span class="sh-meta">' + meta + '</span>' : '') + '</span>' +
        '</button>' + qty +
        '<button type="button" class="sh-more" data-sh-edit aria-expanded="' + open + '" aria-label="' + esc("Change " + it.name) + '">' + I.dots + '</button>' +
      '</div>';
    return { k: "i:" + it.id, sig: html, html: html };
  }
  // The editor is drawn ONCE when opened (its sig never changes), so a change
  // arriving from the other dashboard can't wipe what is being typed.
  function editorNode(it) {
    var chips = AISLES.map(function (a) {
      return '<button type="button" class="sh-ais' + (aisleOf(it.cat) === a[0] ? " on" : "") + '" data-sh-cat="' + a[0] + '">' +
        '<span aria-hidden="true">' + a[1] + '</span>' + esc(a[2]) + '</button>';
    }).join("");
    var p = parseQty(it.qty);
    var html =
      '<div class="sh-ed" data-k="e:' + it.id + '" data-id="' + it.id + '">' +
        '<div class="sh-ed-row">' +
          '<label class="sh-f"><span>Item</span><input class="sh-in" data-f="name" maxlength="80" value="' + esc(it.name) + '"></label>' +
          '<div class="sh-f sh-f-q"><span>How many</span><div class="sh-qrow">' +
            '<button type="button" class="sh-st" data-sh-ed-step="-1" aria-label="Fewer">' + I.minus + '</button>' +
            '<input class="sh-in" data-f="amt" inputmode="decimal" maxlength="16" placeholder="1" aria-label="Amount" value="' +
              esc(p.n == null ? p.raw || "" : num(p.n)) + '">' +
            '<button type="button" class="sh-st" data-sh-ed-step="1" aria-label="More">' + I.plus + '</button>' +
          '</div></div>' +
        '</div>' +
        '<div class="sh-f"><span>Unit</span><div class="sh-aisles" data-sh-units>' + unitChips(p.n == null ? "" : p.u) + '</div></div>' +
        '<div class="sh-f"><span>Aisle</span><div class="sh-aisles">' + chips + '</div></div>' +
        '<div class="sh-act">' +
          '<button type="button" class="sh-btn ghost bad" data-sh-del>Remove</button>' +
          starBtn(!!stapleOf(current(), it.name)) +
          '<button type="button" class="sh-btn go" data-sh-save>Done</button>' +
        '</div>' +
      '</div>';
    return { k: "e:" + it.id, sig: "e", html: html };
  }
  // "Keep as a staple" in a row's editor. The editor is drawn once, so a tap
  // repaints just this button (setStar).
  function starBtn(on) {
    return '<button type="button" class="sh-btn ghost sh-star' + (on ? " on" : "") + '" data-sh-staple aria-pressed="' + on + '">' +
      (on ? "★ A staple" : "☆ Keep as a staple") + '</button>';
  }
  function setStar(btn, on) {
    btn.classList.toggle("on", on);
    btn.setAttribute("aria-pressed", String(on));
    btn.textContent = on ? "★ A staple" : "☆ Keep as a staple";
  }
  function unitChips(sel) {
    var list = UNITS.slice();
    if (sel && !list.some(function (u) { return u[0] === sel; })) list.push([sel, sel]); // "cloves", "dozen"
    return list.map(function (u) {
      return '<button type="button" class="sh-ais sh-unit' + (u[0] === sel ? " on" : "") + '" data-sh-unit="' + esc(u[0]) + '">' + esc(u[1]) + '</button>';
    }).join("");
  }
  // What an open editor's How many + Unit say, as one quantity. A unit typed
  // into the amount box ("300ml") wins over the chips.
  function edQty(ed) {
    var amt = ed.querySelector('[data-f="amt"]').value.replace(/\s+/g, " ").trim();
    var on = ed.querySelector("[data-sh-unit].on"), u = on ? on.getAttribute("data-sh-unit") : "";
    if (!amt) return "";
    var p = parseQty(amt);
    if (p.n == null) return amt + (u ? " " + u : "");
    return p.u ? fmtQty(p.n, p.u) : fmtQty(p.n, u);
  }
  function edShow(ed, q) {
    var p = parseQty(q);
    ed.querySelector('[data-f="amt"]').value = p.n == null ? p.raw || "" : num(p.n);
    var u = p.n == null ? "" : p.u, box = ed.querySelector("[data-sh-units]");
    if (!box.querySelector('[data-sh-unit="' + u + '"]')) box.innerHTML = unitChips(u);
    box.querySelectorAll("[data-sh-unit]").forEach(function (b) { b.classList.toggle("on", b.getAttribute("data-sh-unit") === u); });
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
        '<b>Nothing on the list</b>Add something above, or pick a recipe and add everything it needs.</div>' });
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
      g.forEach(function (it) { nodes.push(rowNode(it)); if (ui.edit === it.id) nodes.push(editorNode(it)); });
    });
    if (got.length) {
      var gh = '<div class="sh-sec sh-got' + (ui.got ? " open" : "") + '" data-k="h:got">' +
        '<button type="button" class="sh-got-t" data-sh-got aria-expanded="' + ui.got + '">' +
          '<span class="sh-sec-i" aria-hidden="true">✓</span>In the trolley<b>' + got.length + '</b>' + I.chev + '</button>' +
        '<button type="button" class="sh-btn ghost sm" data-sh-clear>Clear</button></div>';
      nodes.push({ k: "h:got", sig: gh, html: gh });
      if (ui.got) {
        got.sort(function (x, y) { return (y.doneAt || 0) - (x.doneAt || 0) || (x.id < y.id ? -1 : 1); });
        got.forEach(function (it) { nodes.push(rowNode(it)); if (ui.edit === it.id) nodes.push(editorNode(it)); });
      }
    }
    if (ui.edit && !byId(s, ui.edit)) ui.edit = null; // removed from the other dashboard
    keyed(C.list, nodes, !C.first);
    C.first = false;

    D.paint(C.chips, chipsHtml(s));

    var waiting = queue.length;
    var armed = Date.now() - ui.clearArm < 3000;
    D.paint(C.foot,
      (offline && waiting
        ? '<span class="sh-sync">' + I.cloud + 'Offline — ' + waiting + ' change' + (waiting === 1 ? "" : "s") + ' waiting, sent when you\'re back</span>'
        : '<span class="sh-count">' + (todo.length ? '<b>' + todo.length + '</b> to get' : 'Nothing to get') +
            (got.length ? ' · <b>' + got.length + '</b> in the trolley' : '') + '</span>') +
      (s.items.length ? '<button type="button" class="sh-btn ghost sm bad' + (armed ? " armed" : "") + '" data-sh-clearall>' +
        (armed ? "Tap again to clear" : "Clear list") + '</button>' : ''));
  }

  // The usuals (bought at least twice, not on the list), or — while typing —
  // anything bought before that matches.
  function chipsHtml(s) {
    var typed = key(ui.typed.split(/[,;]/).pop().replace(/^\s*\d+\S*\s*/, "")), list = [], label;
    var on = {};
    s.items.forEach(function (i) { if (!i.done) on[key(i.name)] = 1; });
    var all = Object.keys(hist).map(function (k) { return hist[k]; }).filter(function (h) { return !on[key(h.name)]; });
    if (typed) {
      label = "Bought before";
      list = all.filter(function (h) { return key(h.name).indexOf(typed) >= 0 && key(h.name) !== typed; })
        .sort(function (a, b) { return (key(b.name).indexOf(typed) === 0) - (key(a.name).indexOf(typed) === 0) || b.n - a.n; });
    } else {
      label = "Usuals";
      // (what's already a staple has its own drawer, so it isn't repeated here)
      list = all.filter(function (h) { return h.n >= 2 && !stapleOf(s, h.name); })
        .sort(function (a, b) { return b.n - a.n || b.at - a.at; });
    }
    list = list.slice(0, typed ? 6 : 10);
    if (!list.length) return "";
    return '<span class="sh-chips-h">' + label + '</span>' + list.map(function (h) {
      return '<button type="button" class="sh-chip" data-sh-quick="' + esc(h.name) + '">' + I.plus + esc(h.name) + '</button>';
    }).join("");
  }

  // ── a picture for a thing, from its name ─────────────────────────────────
  // Used by the cupboard staples (each its own picture, not its aisle's); a
  // picture someone picks is stored on the staple and wins. Same lookup as
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

  // ── cupboard staples ─────────────────────────────────────────────────────
  // The things you always keep in, saved so they're quick to add when you're
  // running low — a plain list you control, NOT a tracker: nothing here shows
  // or changes what's already on the list. Folded to one bar like the recipe
  // book (open/shut remembered per browser). Each staple is a row:
  //   +            adds it now, at its usual amount (if it has one)
  //   tap the name opens − amount + and "Add to list", to pick how much first
  // Adding something already on the list adds to it (the server sums: 24 pack
  // + 24 pack = 48 packs). "Edit staples" gives each row a × and an add box
  // that reads like the list's ("cordial, 24 pack toilet paper").
  // (Changed 2026-11-24 at rock's request: the first version lit a chip for
  // anything on the list and took it off again on a second tap — "we want more
  // control … not something we're tracking".)
  var S = null;
  function stapleShell() {
    var host = D.$("sh-staples");
    if (!host) return null;
    if (S && host.contains(S.root)) return S;
    host.innerHTML =
      '<div class="shr shs">' +
        '<button type="button" class="shr-toggle" data-shs-toggle aria-expanded="false" aria-controls="shs-body"></button>' +
        '<div class="shr-body" id="shs-body"><div class="shr-inner">' +
          '<div class="shs-list" role="list" data-shs-list></div>' +
          '<div class="shs-tools" data-shs-tools></div>' +
        '</div></div>' +
      '</div>';
    var root = host.firstElementChild;
    S = { root: root, toggle: root.querySelector("[data-shs-toggle]"), inner: root.querySelector(".shr-inner"),
      list: root.querySelector("[data-shs-list]"), tools: root.querySelector("[data-shs-tools]"), mode: null };
    return S;
  }
  function stapleSort(a, b) {
    return (AISLE[aisleOf(a.cat)].i - AISLE[aisleOf(b.cat)].i) || (a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1);
  }
  // The amount being picked, shown as "1" when there's none (= one).
  function amtLabel(q) { return q || "1"; }
  function stapleRow(x) {
    var icon = iconFor(x), name = '<span class="shs-t"><span class="shs-n">' + esc(x.name) + '</span>' +
      (x.qty ? '<small>usually ' + esc(x.qty) + '</small>' : '') + '</span>';
    var t = '<span class="shs-i" aria-hidden="true">' + icon + '</span>' + name;
    if (ui.sEdit) {
      // Editing: tap the picture to pick another (or Auto, the guess from its name).
      var picking = ui.sIcon === x.id;
      return '<div class="shs-row' + (picking ? " open" : "") + '" role="listitem"><span class="shs-main">' +
          '<button type="button" class="shs-i pickable" data-shs-icon="' + x.id + '" aria-expanded="' + picking + '" ' +
            'aria-label="' + esc("Change the picture for " + x.name) + '">' + icon + '</button>' + name + '</span>' +
        '<button type="button" class="shs-btn del" data-shs-del="' + x.id + '" aria-label="' + esc("Take " + x.name + " out of the staples") + '">' + I.x + '</button>' +
        (picking ? '<div class="shs-pick shs-icons" role="group" aria-label="' + esc("Pictures for " + x.name) + '">' +
          '<button type="button" class="shs-auto' + (x.icon ? "" : " on") + '" data-shs-seticon="">Auto</button>' +
          STAPLE_ICONS.map(function (e) {
            return '<button type="button" class="' + (x.icon === e ? "on" : "") + '" data-shs-seticon="' + e + '">' + e + '</button>';
          }).join("") + '</div>' : '') +
        '</div>';
    }
    var open = ui.sPick === x.id;
    var html = '<div class="shs-row' + (open ? " open" : "") + '" role="listitem">' +
      '<button type="button" class="shs-main" data-shs-pick="' + x.id + '" aria-expanded="' + open + '" ' +
        'aria-label="' + esc("Pick how many " + x.name) + '">' + t + '</button>';
    if (!open) {
      return html + '<button type="button" class="shs-btn" data-shs-quick="' + x.id + '" ' +
        'aria-label="' + esc("Add " + (x.qty ? x.qty + " " : "") + x.name + " to the list") + '">' + I.plus + '</button></div>';
    }
    var down = stepQty(ui.sAmt, -1), up = stepQty(ui.sAmt, 1);
    return html + '<div class="shs-pick">' +
        '<span class="sh-stepper" role="group" aria-label="' + esc("How many " + x.name) + '">' +
          '<button type="button" class="sh-st" data-shs-step="-1" aria-label="Fewer"' + (down == null ? " disabled" : "") + '>' + I.minus + '</button>' +
          '<b aria-live="polite">' + esc(amtLabel(ui.sAmt)) + '</b>' +
          '<button type="button" class="sh-st" data-shs-step="1" aria-label="More"' + (up == null ? " disabled" : "") + '>' + I.plus + '</button>' +
        '</span>' +
        '<button type="button" class="sh-btn go" data-shs-add="' + x.id + '">Add to list</button>' +
      '</div></div>';
  }
  function drawStaples(s) {
    var C = stapleShell();
    if (!C) return;
    var all = s.staples.slice().sort(stapleSort);
    if (!all.length && ui.sOpen) ui.sEdit = true; // nothing saved yet: straight to adding some
    if (ui.sPick && !all.some(function (x) { return x.id === ui.sPick; })) ui.sPick = null; // taken out on the other dashboard
    C.root.classList.toggle("open", ui.sOpen);
    C.root.classList.toggle("editing", ui.sEdit);
    C.toggle.setAttribute("aria-expanded", String(ui.sOpen));
    C.inner.inert = !ui.sOpen;
    var faces = [];
    all.forEach(function (x) { var f = iconFor(x); if (faces.indexOf(f) < 0) faces.push(f); });
    D.paint(C.toggle,
      '<span class="shr-stack" aria-hidden="true">' + (faces.length ? faces.slice(0, 3) : ["🧺"]).map(function (f) {
        return '<span>' + f + '</span>'; }).join("") + '</span>' +
      '<span class="shr-toggle-t"><b>Cupboard staples</b><small>' +
        (!all.length ? "Save the things you always keep in" :
          ui.sOpen && !ui.sEdit ? "Tap a name to pick how many" : plural(all.length, "staple", "staples") + " saved") +
      '</small></span>' + I.chev);

    D.paint(C.list, !all.length ? '<div class="shr-none">No staples yet — add toilet paper, cereal, cordial… above.</div>' :
      all.map(stapleRow).join(""));

    // The tools are drawn only when the mode changes, so the add box keeps
    // what's being typed while the other dashboard changes things.
    var mode = ui.sEdit ? "edit" : "use";
    if (C.mode !== mode) {
      C.mode = mode;
      C.tools.innerHTML = ui.sEdit
        ? '<form class="shs-add" data-shs-form autocomplete="off">' +
            '<input class="sh-in" type="text" maxlength="300" placeholder="Add staples — cordial, 24 pack toilet paper" aria-label="Add a staple" enterkeyhint="done" autocapitalize="sentences">' +
            '<button type="submit" class="sh-plus" aria-label="Save as a staple">' + I.plus + '</button>' +
          '</form>' +
          '<div class="sh-act"><span class="shs-hint">Tap a picture to change it. An amount in front becomes its usual one.</span><button type="button" class="sh-btn go sm" data-shs-done>Done</button></div>'
        : '<div class="sh-act"><button type="button" class="sh-btn ghost sm" data-shs-edit>Edit staples</button></div>';
    }
  }
  // Put a staple on the list at the amount given ("" = just the thing).
  function addStaple(x, qty) {
    if (/^1$/.test(qty)) qty = ""; // one, unitless, is just the thing
    var r = addItems([{ name: x.name, qty: qty, cat: x.cat && x.cat !== "other" ? x.cat : undefined }]);
    var what = (qty ? qty + " " : "") + x.name;
    if (r.fresh.length) say("Added " + what + " to the list", { undo: function () { remove(r.fresh, "Took " + x.name + " back off"); } });
    else if (qty) say(x.name + ": added " + qty + " to what's on the list");
    else say(x.name + " is already on the list");
    buzz();
  }

  // ── the recipe card ──────────────────────────────────────────────────────
  var R = null;
  function recipeShell() {
    var host = D.$("sh-recipes");
    if (!host) return null;
    if (R && host.contains(R.root)) return R;
    // Collapsed to one bar unless opened (remembered per browser): on a phone
    // the list is what you came for, and six recipe tiles under it are a
    // screen and a half of scrolling.
    host.innerHTML =
      '<div class="shr">' +
        '<button type="button" class="shr-toggle" data-shr-toggle aria-expanded="false" aria-controls="shr-body"></button>' +
        '<div class="shr-body" id="shr-body"><div class="shr-inner">' +
          '<div class="shr-bar">' +
            '<label class="shr-find">' + I.search + '<input class="sh-in" type="search" placeholder="Find a recipe…" aria-label="Find a recipe"></label>' +
            '<button type="button" class="sh-btn" data-shr-new>' + I.plus + 'New recipe</button>' +
          '</div>' +
          '<div class="shr-panel" data-shr-panel></div>' +
          '<div class="shr-grid" data-shr-grid></div>' +
        '</div></div>' +
      '</div>';
    var root = host.firstElementChild;
    R = { root: root, toggle: root.querySelector("[data-shr-toggle]"), inner: root.querySelector(".shr-inner"),
      bar: root.querySelector(".shr-bar"), find: root.querySelector(".shr-find input"),
      panel: root.querySelector("[data-shr-panel]"), grid: root.querySelector("[data-shr-grid]"), mode: null };
    R.find.addEventListener("input", function () { ui.find = R.find.value; refresh(); });
    return R;
  }
  function recipe(s, id) { for (var i = 0; i < s.recipes.length; i++) if (s.recipes[i].id === id) return s.recipes[i]; return null; }
  function plural(n, one, many) { return n + " " + (n === 1 ? one : many); }

  function drawRecipes(s) {
    var C = recipeShell();
    if (!C) return;
    var q = key(ui.find), rs = s.recipes;
    // The bar: a little stack of their pictures, how many, and which way it opens.
    C.root.classList.toggle("open", ui.rOpen);
    C.toggle.setAttribute("aria-expanded", String(ui.rOpen));
    C.inner.inert = !ui.rOpen;
    D.paint(C.toggle,
      '<span class="shr-stack" aria-hidden="true">' + (rs.length ? rs.slice(0, 4).map(function (r) {
        return '<span>' + esc(r.icon || "🍽️") + '</span>';
      }).join("") : '<span>📖</span>') + '</span>' +
      '<span class="shr-toggle-t"><b>' + (rs.length ? plural(rs.length, "recipe", "recipes") : "Recipes") + '</b>' +
        '<small>' + (ui.rOpen ? "Pick what to cook" : rs.length ? "Tap to pick one" : "Tap to add your first") + '</small></span>' +
      I.chev);
    C.bar.classList.toggle("many", rs.length > 6);
    var shown = q ? rs.filter(function (r) {
      return key(r.name).indexOf(q) >= 0 || r.ingredients.some(function (g) { return key(g.name).indexOf(q) >= 0; });
    }) : rs;
    D.paint(C.grid, !rs.length
      ? '<div class="sh-empty"><span aria-hidden="true">📖</span><b>No recipes yet</b>Add the meals you cook most — then one tap puts everything they need on the list.</div>'
      : !shown.length ? '<div class="shr-none">Nothing matches “' + esc(ui.find) + '”.</div>'
      : shown.map(function (r) {
        var need = r.ingredients.filter(function (g) { return !onList(s, g.name); }).length;
        return '<button type="button" class="shr-tile' + (ui.cook === r.id || ui.rEdit === r.id ? " on" : "") + '" data-shr-open="' + r.id + '">' +
          '<span class="shr-ico" aria-hidden="true">' + esc(r.icon || "🍽️") + '</span>' +
          '<span class="shr-tile-t"><b>' + esc(r.name) + '</b><small>' + plural(r.ingredients.length, "ingredient", "ingredients") +
            (need < r.ingredients.length ? ' · ' + (need ? need + " to get" : "all on the list") : '') + '</small></span></button>';
      }).join(""));

    if (ui.rEdit !== null) {
      if (C.mode !== "edit:" + ui.rEdit) { C.panel.innerHTML = editorHtml(ui.rEdit === "new" ? null : recipe(s, ui.rEdit)); C.mode = "edit:" + ui.rEdit; }
      var del = C.panel.querySelector("[data-shr-del]");
      if (del) { var armed = Date.now() - ui.rArm < 3000; del.classList.toggle("armed", armed); del.textContent = armed ? "Tap again to delete" : "Delete"; }
    } else if (ui.cook) {
      var r = recipe(s, ui.cook);
      if (!r) { ui.cook = null; C.panel.innerHTML = ""; C.mode = null; return; }
      if (C.mode !== "cook") { C.panel.innerHTML = ""; C.mode = "cook"; }
      D.paint(C.panel, cookHtml(s, r));
    } else if (C.mode) {
      C.panel.innerHTML = ""; C.mode = null;
    }
  }

  function cookHtml(s, r) {
    var n = 0;
    var rows = r.ingredients.map(function (g, i) {
      var on = !ui.off[i], have = onList(s, g.name);
      if (on) n++;
      return '<button type="button" class="shr-ing' + (on ? " on" : "") + (have ? " have" : "") + '" data-shr-ing="' + i + '" aria-pressed="' + on + '">' +
        '<span class="sh-box" aria-hidden="true">' + I.check + '</span>' +
        '<span class="shr-ing-n">' + esc(g.name) + (have ? '<em>on the list</em>' : '') + '</span>' +
        (g.qty ? '<span class="sh-qty">' + esc(g.qty) + '</span>' : '') + '</button>';
    }).join("");
    return '<div class="shr-cook">' +
      '<div class="shr-head"><span class="shr-ico lg" aria-hidden="true">' + esc(r.icon || "🍽️") + '</span>' +
        '<span class="shr-head-t"><b>' + esc(r.name) + '</b><small>' + plural(r.ingredients.length, "ingredient", "ingredients") +
          (r.used ? ' · on the list ' + plural(r.used, "time", "times") + ' before' : '') + '</small></span>' +
        '<button type="button" class="sh-x" data-shr-close aria-label="Close">' + I.x + '</button></div>' +
      '<div class="shr-hint">Untick anything you\'ve already got.</div>' +
      '<div class="shr-ings">' + rows + '</div>' +
      (r.note ? '<div class="shr-note">' + esc(r.note) + '</div>' : '') +
      '<div class="sh-act">' +
        '<button type="button" class="sh-btn ghost" data-shr-edit>Edit</button>' +
        '<button type="button" class="sh-btn ghost" data-shr-all>' + (n === r.ingredients.length ? "None" : "All") + '</button>' +
        '<button type="button" class="sh-btn go" data-shr-add' + (n ? "" : " disabled") + '>' +
          (n ? "Add " + n + " to the list" : "Nothing to add") + '</button>' +
      '</div></div>';
  }

  function editorHtml(r) {
    var icon = (r && r.icon) || "🍝";
    var lines = r ? r.ingredients.map(function (g) { return (g.qty ? g.qty + " " : "") + g.name; }).join("\n") : "";
    return '<form class="shr-ed" data-shr-form autocomplete="off">' +
      '<div class="shr-head"><span class="shr-head-t"><b>' + (r ? "Edit recipe" : "New recipe") + '</b>' +
        '<small>One ingredient a line — “500g beef mince”, “2 onions”, “garlic”.</small></span>' +
        '<button type="button" class="sh-x" data-shr-close aria-label="Close">' + I.x + '</button></div>' +
      '<div class="shr-name">' +
        '<button type="button" class="shr-ico lg shr-pick" data-shr-icon aria-label="Pick a picture" aria-expanded="false">' + esc(icon) + '</button>' +
        '<input class="sh-in" name="name" maxlength="80" placeholder="What\'s it called?" aria-label="Recipe name" value="' + esc(r ? r.name : "") + '">' +
      '</div>' +
      '<div class="shr-emoji" hidden>' + EMOJI.map(function (e) {
        return '<button type="button" data-shr-emoji="' + e + '"' + (e === icon ? ' class="on"' : '') + '>' + e + '</button>';
      }).join("") + '</div>' +
      '<label class="sh-f"><span>Ingredients</span><textarea class="sh-in" name="ings" rows="8" placeholder="500g beef mince&#10;1 onion&#10;2 cloves garlic&#10;1 tin chopped tomatoes&#10;Spaghetti">' + esc(lines) + '</textarea></label>' +
      '<label class="sh-f"><span>Notes <small>optional</small></span><textarea class="sh-in" name="note" rows="2" maxlength="600" placeholder="Serves 4 · double it for leftovers">' + esc(r ? r.note || "" : "") + '</textarea></label>' +
      '<div class="shr-err" hidden></div>' +
      '<div class="sh-act">' +
        (r ? '<button type="button" class="sh-btn ghost bad" data-shr-del>Delete</button>' : '') +
        '<button type="button" class="sh-btn ghost" data-shr-close>Cancel</button>' +
        '<button type="submit" class="sh-btn go">' + (r ? "Save" : "Save recipe") + '</button>' +
      '</div></form>';
  }

  function openCook(id) {
    var s = current();
    var r = recipe(s, id);
    if (!r) return;
    ui.rEdit = null; ui.cook = id; ui.off = {};
    r.ingredients.forEach(function (g, i) { if (onList(s, g.name)) ui.off[i] = true; });
    render();
    reveal();
  }
  function openEditor(id) { ui.cook = null; ui.rEdit = id; ui.rArm = 0; render(); reveal(); var n = R && R.panel.querySelector('input[name="name"]'); if (n && id === "new") n.focus(); }
  function closePanel() { ui.cook = null; ui.rEdit = null; ui.rArm = 0; refresh(); }
  function reveal() {
    if (!R || !R.panel.firstElementChild) return;
    var r = R.panel.getBoundingClientRect();
    if (r.top < 70 || r.top > innerHeight - 120) R.panel.scrollIntoView({ behavior: CALM ? "auto" : "smooth", block: "start" });
  }
  function submitRecipe(form) {
    var s = current(), editing = ui.rEdit !== "new" ? recipe(s, ui.rEdit) : null;
    var name = form.querySelector('[name="name"]').value.replace(/\s+/g, " ").trim();
    var ings = String(form.querySelector('[name="ings"]').value).split("\n").map(parse).filter(Boolean)
      .map(function (g) { return { name: g.name, qty: g.qty, cat: categorise(g.name) }; });
    var err = form.querySelector(".shr-err");
    if (!name || !ings.length) {
      err.textContent = !name ? "Give it a name." : "Add at least one ingredient.";
      err.hidden = false;
      (!name ? form.querySelector('[name="name"]') : form.querySelector('[name="ings"]')).focus();
      return;
    }
    var rec = { id: editing ? editing.id : rid(), name: cap(name), icon: form.querySelector("[data-shr-icon]").textContent,
      ingredients: ings, note: form.querySelector('[name="note"]').value.trim() };
    if (editing) { rec.used = editing.used; }
    saveRecipe(rec);
    ui.rEdit = null;
    ui.cook = rec.id; ui.off = {};
    rec.ingredients.forEach(function (g, i) { if (onList(s, g.name)) ui.off[i] = true; });
    say(editing ? "Saved " + rec.name : "Added " + rec.name + " to your recipes");
    render();
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
    // Above Glance's phone bar when it is showing.
    var nav = document.querySelector(".mobile-navigation");
    var lift = nav && getComputedStyle(nav).display !== "none" ? nav.getBoundingClientRect().height : 0;
    toast.style.bottom = Math.round(lift + 18) + "px";
    toast.classList.add("show");
    clearTimeout(toastT);
    toastT = setTimeout(hide, undoFn ? 6500 : o.bad ? 6000 : 3000);
  }
  function hide() { clearTimeout(toastT); if (toast) toast.classList.remove("show"); undoFn = null; }

  // ── input ────────────────────────────────────────────────────────────────
  function buzz() { try { if (navigator.vibrate) navigator.vibrate(8); } catch (_) {} }
  function closeEdit(save) {
    var id = ui.edit;
    if (!id) return;
    var ed = document.querySelector('#sh-list .sh-ed[data-id="' + id + '"]'), it = byId(current(), id);
    if (save && ed && it) {
      var name = ed.querySelector('[data-f="name"]').value.replace(/\s+/g, " ").trim();
      var qty = edQty(ed);
      var ch = {};
      if (name && name !== it.name) ch.name = name;
      if (qty !== (it.qty || "")) ch.qty = qty;
      if (Object.keys(ch).length) edit(id, ch);
    }
    ui.edit = null;
    refresh();
  }

  // An open − / + folds back into its pill after a few quiet seconds, or at
  // the first tap anywhere else.
  function stepFor(id) {
    clearTimeout(ui.stepT);
    ui.step = id;
    ui.stepT = id ? setTimeout(function () { ui.step = null; refresh(); }, 4000) : null;
    refresh();
  }

  function onClick(e) {
    var t = e.target, el;
    if (!t.closest) return;
    if (ui.step && !t.closest(".sh-stepper")) stepFor(null);
    if (t.closest("#sh-staples")) { onStapleClick(t); return; }
    if (t.closest("#sh-list") && !t.closest("#sh-recipes")) {
      var row = t.closest("[data-id]"), id = row && row.getAttribute("data-id");
      if ((el = t.closest("[data-sh-staple]")) && id) {
        var me2 = byId(current(), id), edEl = el.closest(".sh-ed");
        var nm = (edEl && edEl.querySelector('[data-f="name"]').value.replace(/\s+/g, " ").trim()) || (me2 && me2.name);
        if (!nm) return;
        var was = stapleOf(current(), nm);
        if (was) { deleteStaple(was); setStar(el, false); }
        else {
          saveStaple({ id: rid(), name: nm, qty: me2 && me2.qty || "", cat: me2 ? me2.cat : categorise(nm) });
          setStar(el, true);
          say(nm + " is a staple now — it's in Cupboard staples");
        }
      } else if (t.closest("[data-sh-step-open]") && id) {
        stepFor(id);
      } else if ((el = t.closest("[data-sh-step]")) && id) {
        var cur = byId(current(), id), nq = cur && stepQty(cur.qty, +el.getAttribute("data-sh-step"));
        if (nq) { edit(id, { qty: nq }); buzz(); }
        stepFor(id);
      } else if ((el = t.closest("[data-sh-ed-step]")) && id) {
        var ed = el.closest(".sh-ed"), dir = +el.getAttribute("data-sh-ed-step"), q = edQty(ed);
        var on = ed.querySelector("[data-sh-unit].on");
        var nq2 = q ? stepQty(q, dir) : dir > 0 ? startQty(on ? on.getAttribute("data-sh-unit") : "") : null;
        if (nq2) { edShow(ed, nq2); buzz(); }
      } else if ((el = t.closest("[data-sh-unit]")) && id) {
        var ed2 = el.closest(".sh-ed"), u = el.getAttribute("data-sh-unit");
        el.parentNode.querySelectorAll("[data-sh-unit]").forEach(function (b) { b.classList.toggle("on", b === el); });
        // A unit on an item with no amount yet starts it somewhere sensible.
        if (u && !ed2.querySelector('[data-f="amt"]').value.trim()) edShow(ed2, startQty(u));
      } else if ((el = t.closest("[data-sh-tick]")) && id) {
        var it = byId(current(), id);
        if (it) { toggle(id, !it.done); if (!it.done) buzz(); }
      } else if (t.closest("[data-sh-edit]") && id) {
        if (ui.edit === id) closeEdit(true);
        else { closeEdit(true); ui.edit = id; render(); var f = document.querySelector('#sh-list .sh-ed[data-id="' + id + '"] [data-f="name"]'); if (f && matchMedia("(hover: hover)").matches) f.focus(); }
      } else if ((el = t.closest("[data-sh-cat]")) && id) {
        var cat = el.getAttribute("data-sh-cat");
        el.parentNode.querySelectorAll(".sh-ais").forEach(function (b) { b.classList.toggle("on", b === el); });
        edit(id, { cat: cat });
      } else if (t.closest("[data-sh-save]")) {
        closeEdit(true);
      } else if (t.closest("[data-sh-del]") && id) {
        ui.edit = null;
        remove([id]);
      } else if ((el = t.closest("[data-sh-quick]"))) {
        addItems([{ name: el.getAttribute("data-sh-quick") }]);
        if (ui.typed && L) { var parts = L.input.value.split(/[,;]/); parts.pop(); L.input.value = parts.length ? parts.join(",") + ", " : ""; ui.typed = L.input.value; L.input.focus(); }
        buzz();
      } else if (t.closest("[data-sh-got]")) {
        ui.got = !ui.got;
        try { localStorage.setItem("sh-got", ui.got ? "open" : "closed"); } catch (_) {}
        refresh();
      } else if (t.closest("[data-sh-clear]")) {
        clear("done");
      } else if (t.closest("[data-sh-clearall]")) {
        if (Date.now() - ui.clearArm < 3000) { ui.clearArm = 0; clear("all"); }
        else { ui.clearArm = Date.now(); setTimeout(refresh, 3050); }
        refresh();
      }
      return;
    }
    if (t.closest("#sh-recipes")) {
      if (t.closest("[data-shr-toggle]")) {
        ui.rOpen = !ui.rOpen;
        if (!ui.rOpen) ui.cook = null; // an unsaved recipe editor stays, for when it's opened again
        try { localStorage.setItem("sh-recipes", ui.rOpen ? "open" : "closed"); } catch (_) {}
        refresh();
      } else if ((el = t.closest("[data-shr-open]"))) {
        var rid2 = el.getAttribute("data-shr-open");
        if (ui.cook === rid2) closePanel(); else openCook(rid2);
      } else if (t.closest("[data-shr-new]")) {
        openEditor("new");
      } else if (t.closest("[data-shr-close]")) {
        closePanel();
      } else if ((el = t.closest("[data-shr-ing]"))) {
        var i = +el.getAttribute("data-shr-ing");
        if (ui.off[i]) delete ui.off[i]; else ui.off[i] = true;
        render();
      } else if (t.closest("[data-shr-all]")) {
        var r = recipe(current(), ui.cook);
        if (r) {
          var allOn = r.ingredients.every(function (g, j) { return !ui.off[j]; });
          ui.off = {};
          if (allOn) r.ingredients.forEach(function (g, j) { ui.off[j] = true; });
        }
        render();
      } else if (t.closest("[data-shr-add]")) {
        var rr = recipe(current(), ui.cook);
        if (!rr) return;
        var pick = rr.ingredients.filter(function (g, j) { return !ui.off[j]; });
        if (!pick.length) return;
        var res = addItems(pick.map(function (g) { return { name: cap(g.name), qty: g.qty, cat: g.cat && g.cat !== "other" ? g.cat : undefined }; }),
          { from: rr.name, recipe: rr.id });
        var fresh = res.fresh;
        say("Added " + plural(pick.length, "thing", "things") + " for " + rr.name,
          fresh.length ? { undo: function () { remove(fresh, "Took them back off"); } } : {});
        buzz();
        closePanel();
      } else if (t.closest("[data-shr-edit]")) {
        openEditor(ui.cook);
      } else if ((el = t.closest("[data-shr-icon]"))) {
        var box = R.panel.querySelector(".shr-emoji");
        box.hidden = !box.hidden;
        el.setAttribute("aria-expanded", String(!box.hidden));
      } else if ((el = t.closest("[data-shr-emoji]"))) {
        var pickB = R.panel.querySelector("[data-shr-icon]");
        pickB.textContent = el.getAttribute("data-shr-emoji");
        el.parentNode.querySelectorAll("button").forEach(function (b) { b.classList.toggle("on", b === el); });
        el.parentNode.hidden = true;
        pickB.setAttribute("aria-expanded", "false");
      } else if (t.closest("[data-shr-del]")) {
        var victim = recipe(current(), ui.rEdit);
        if (!victim) return;
        if (Date.now() - ui.rArm < 3000) { ui.rArm = 0; ui.rEdit = null; deleteRecipe(victim); }
        else { ui.rArm = Date.now(); setTimeout(refresh, 3050); }
        refresh();
      }
    }
  }
  function onKey(e) {
    var t = e.target;
    if (!t.closest) return;
    var ed = t.closest("#sh-list .sh-ed");
    if (ed) {
      if (e.key === "Enter") { e.preventDefault(); closeEdit(true); }
      else if (e.key === "Escape") closeEdit(false);
      return;
    }
    if (e.key === "Escape" && t.closest("#sh-recipes")) closePanel();
    if (e.key === "Escape" && L && t === L.input) { L.input.value = ""; ui.typed = ""; refresh(); }
  }
  function onStapleClick(t) {
    var el, s = current();
    function staple(id) { return s.staples.filter(function (x) { return x.id === id; })[0]; }
    if (t.closest("[data-shs-toggle]")) {
      ui.sOpen = !ui.sOpen;
      if (!ui.sOpen) { ui.sEdit = false; ui.sPick = null; ui.sIcon = null; }
      try { localStorage.setItem("sh-staples", ui.sOpen ? "open" : "closed"); } catch (_) {}
      refresh();
    } else if ((el = t.closest("[data-shs-quick]"))) {
      var q = staple(el.getAttribute("data-shs-quick"));
      if (q) addStaple(q, q.qty || "");
    } else if ((el = t.closest("[data-shs-pick]"))) {
      var pk = staple(el.getAttribute("data-shs-pick"));
      if (!pk) return;
      if (ui.sPick === pk.id) ui.sPick = null;
      else { ui.sPick = pk.id; ui.sAmt = pk.qty || ""; }
      refresh();
    } else if ((el = t.closest("[data-shs-step]"))) {
      var nq = stepQty(ui.sAmt, +el.getAttribute("data-shs-step"));
      if (nq) { ui.sAmt = nq; buzz(); refresh(); }
    } else if ((el = t.closest("[data-shs-add]"))) {
      var ad = staple(el.getAttribute("data-shs-add"));
      if (ad) addStaple(ad, ui.sAmt);
      ui.sPick = null;
      refresh();
    } else if ((el = t.closest("[data-shs-icon]"))) {
      var ic = el.getAttribute("data-shs-icon");
      ui.sIcon = ui.sIcon === ic ? null : ic;
      refresh();
    } else if ((el = t.closest("[data-shs-seticon]"))) {
      var who = staple(ui.sIcon);
      if (who) saveStaple({ id: who.id, name: who.name, qty: who.qty || "", cat: who.cat, icon: el.getAttribute("data-shs-seticon") });
      ui.sIcon = null;
      buzz();
      refresh();
    } else if ((el = t.closest("[data-shs-del]"))) {
      var gone = staple(el.getAttribute("data-shs-del"));
      if (gone) deleteStaple(gone);
    } else if (t.closest("[data-shs-edit]")) {
      ui.sEdit = true; ui.sPick = null; render();
      var inp = S && S.tools.querySelector("input");
      if (inp && matchMedia("(hover: hover)").matches) inp.focus();
    } else if (t.closest("[data-shs-done]")) {
      ui.sEdit = false; ui.sIcon = null; refresh();
    }
  }
  function onSubmit(e) {
    var sf = e.target.closest && e.target.closest("[data-shs-form]");
    if (sf) {
      e.preventDefault();
      var inp = sf.querySelector("input");
      parseMany(inp.value).forEach(function (g) {
        saveStaple({ id: rid(), name: g.name, qty: g.qty, cat: categorise(g.name) });
      });
      inp.value = "";
      inp.focus();
      return;
    }
    var f = e.target.closest && e.target.closest("[data-shr-form]");
    if (!f) return;
    e.preventDefault();
    submitRecipe(f);
  }

  // ── go ───────────────────────────────────────────────────────────────────
  function render() {
    queued = false;
    var s = current();
    if (!s) return;
    drawList(s);
    drawStaples(s);
    drawRecipes(s);
  }
  function refresh() { if (!queued) { queued = true; requestAnimationFrame(render); } }

  D.ready("#sh-list, #sh-recipes", function () {
    D.stream(API + "/events", { state: function (s) { take(s); kick(); } }, "sh-live");
    document.addEventListener("click", onClick);
    document.addEventListener("keydown", onKey);
    document.addEventListener("submit", onSubmit);
    // rAF doesn't run in a hidden tab; draw what came in while it was hidden.
    document.addEventListener("visibilitychange", function () { if (!document.hidden) render(); });
  });
})();
