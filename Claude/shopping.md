# Shopping list + recipes — shared between both dashboards

**Backend:** `Resources/Shopping-List/shopping-list.py` · unit `shopping-list` from
`Modules/Server/shopping.nix` · **:9558**, tailnet only
**Client:** `Resources/Glance/shopping.js` (one script, BOTH dashboards) · styles in
`Resources/Glance/cards.css` (tokens) + the HUD squaring in `asgard.css`
**Where:** rock's Glance → the **Shopping** page (`asgard:8888/shopping`) · her MarsBar →
the **second dot**, Home · **Shopping** · Eclipse
**Built:** 2026-11-24

One list for the two of you. A tick on her phone in the shop is on rock's screen before
her thumb is off the glass, and the other way round. Plus a recipe book: tap a recipe,
untick what's already in the cupboard, *Add 7 to the list* — filed by aisle.

**It is ONE card** (`#sh-list`), on purpose — you both just run down it in the shop. It was
two cards for a day; rock and Kit-Kat both wanted the one — don't split it back out.
Across its top are **three tabs — List · Pantry · Recipes** (2026-11-25; before that Pantry
and Recipes were bars folded inside the list, and rock found them "not impactful … it should
feel distinct when you're in there"). Mockups of three layouts were weighed first; the tabs
won, with a big **handwritten heading and a drawing** on every tab (List got its own the
next day — rock: "only thing missing now is a list img so it's all consistent").
- **A swipe across the card** (phones) goes to the next/previous tab; the tab is kept for
  that browser tab only (`sessionStorage`), so a fresh look at the dashboard — the one you
  open in the shop — **always starts on List**.
- **List** = the **Shopping** heading (a trolley of bread, greens and a bottle) whose
  subtitle IS the trolley bar (*3 of 18 in the trolley*, a gradient bar; *Nothing on it yet*
  when empty), then the add box, the list by aisle, In the trolley. The List tab carries how
  many are left to get. "Shopping" is the longest title, so on a phone-width card it and the
  trolley are a little smaller (a container query) or the "g" runs into the handle.

Everything that needs more room than a row — an item's details, a doubled-up decision, a
usual, a group, a recipe to shop for, the recipe editor — opens in **a sheet** (below).

```
her phone ──► marsbar:1111/shop-api/* ──► tailscale serve ──┐
                                                            ├──► 127.0.0.1:9558 shopping-list ──► state.json
rock's browser ──► asgard:9558 (tailnet, CORS) ─────────────┘        (one SSE stream per open card)
```

---

## What it does

**The list**
- **Add box.** Type and Enter. A comma adds several — `milk, eggs, 2 onions`.
  Quantities are read off the front or back: `500g beef mince`, `2 cloves garlic`,
  `milk x2`, `eggs (dozen)`, `Milk 2L`. (`7up` stays `7up`: a number glued to a word that
  isn't a unit is part of the name.)
- **Suggestions while typing** — pantry things that match first (with their amount: *Thickened
  cream 300mL*), then things bought before. Nothing shows under an empty box: the
  automatic "Usuals" row (anything bought twice) was removed 2026-11-24 — rock: "kinda
  pointless now" — and the curated list took its name, then became the **Pantry** tab.
- **Aisles.** Grouped in the order a shop is walked: Fruit & veg → Bakery → Meat & fish →
  Dairy & chilled → Pantry → Frozen → Snacks → Drinks → Household → Health & beauty →
  Pets → Other. The aisle is guessed from the name (`shopping.js` → `WORDS` / `PHRASES`:
  the last meaningful word wins, so *chicken stock* is Pantry and *frozen peas* Frozen).
  **Move an item once (⋯ → Aisle) and that name lives there from then on** — the server
  remembers it per name.
- **Tick** = tap anywhere on the row. Ticked things sink into **In the trolley** (newest
  first, collapsible, remembered per browser) with a **Clear** button.
- **Same thing twice is merged, not duplicated.** Names match ignoring case, spacing and a
  plural (`Onions` = `onion`). Quantities with the same unit add up (`500g` + `500g` =
  `1000g`); different units join (`1 tin + 400g`). Re-adding something already *in the
  trolley* puts it back on the list. The merged row flashes. **If the second add said an
  amount or came from a recipe, the row is flagged** (next section).
- **Tap a quantity pill** and it opens into **− 2L +** right on the row. Each tap saves; a
  run of quick taps goes to the server as ONE edit (`send()` folds a queued edit for the
  same item into the next). It folds back after 4 quiet seconds or the first tap anywhere
  else. A ticked row's pill is just a label. A row with no quantity has no pill — ⋯ sets one.
- **⋯ on a row** opens its sheet: name, **How many** (the shared Amount control), who asked
  for how much (if it was doubled up), Aisle, and **Remove · ☆ Add to usuals · Save**.

**Doubled up — the ⚑ flag (added 2026-11-24)**

Two recipes both wanting 300mL of cream really do need 600mL; two recipes both wanting
sour cream probably need one tub. The list can't know which, so it **adds it all up and
flags it**, and whoever is in the shop decides.
- Each item keeps its **parts** — `[{id, from, qty, by}]`, one per time it was asked for.
  An add of something already on the list *with an amount or a recipe* appends a part,
  sums the quantity, and un-settles it. A bare re-add (typing `milk` when milk is there)
  only flashes the row — no part, no flag.
- **Flagged = not ticked, not `settled`, two or more parts.** The row gets a gold edge and
  a chip — *⚑ 2 recipes — check* or *⚑ Added twice — check* — inside the tick button but
  checked first in `onListClick`, so tapping it opens the decision instead of ticking.
- The **flag sheet** lists each part (amount · recipe or who) and the total, then
  **Just one · 300mL** (the biggest single part — `justOne()`) or **Get both · 600mL**
  (*Get all 3* for three). *Some other amount…* opens the item sheet. Either answer
  settles it, on both phones.
- **Changing the amount by hand settles it too** — the server sets `settled` on any `qty`
  edit (the pill's − / +, the item sheet). A *third* ask re-flags.
- Amounts sum with `add_up()` in the .py: a part with no amount counts as one —
  `""` + `""` = **2**, but `""` + `300mL` = **300mL** (a "some cream" and a "300mL cream"
  are probably the same tub, not 301).
- The **cook sheet** warns before it happens: an ingredient already on the list says
  *⚑ On the list · 300mL — this adds to it*, and the toast after adding counts them
  (*2 already on the list — ⚑ to check*).
- ⚠ Idempotent like every write: a part's id IS the client's add id, and `_seen()` checks
  item ids and part ids — a retried recipe add can't double-count.

**Quantities and units** (`parseQty` / `fmtQty` / `stepQty` in shopping.js, `merge_qty`
in the .py — ⚠ their metric tables must agree)
- Metric is written the Australian-label way and tight: **300mL, 2L, 500g, 1.5kg**.
  Whatever is typed (`300ml`, `2 litres`, `500 grams`) is tidied to that on the way in;
  word units get a space and a plural (`3 tins`, `1 pack`); anything without a leading
  number (`dozen`, `a few`) or with a unit it doesn't know (`2 cloves`) is kept as typed.
- **Steps:** g / mL go 50 at a time below 500 and 100 from 500, rolling over to kg / L at
  1000 (900mL + → 1L); kg / L go 0.5 and roll back under 1 (1L − → 500mL); counts and
  word units go 1. Steps snap to their grid (330mL + → 350mL). − stops at 50 / 1 (the
  button disables); `2-3` and other non-numbers don't step. Every step sends the
  ABSOLUTE new quantity, never a delta — that's what keeps it idempotent.
- **Merging** on the server adds metric across sizes (600mL + 1L = 1.6L, 750g + 500g =
  1.25kg) and the same word unit across plurals (1 tin + 2 tins = 3 tins).
- **Undo** (a toast) after Remove, Clear, Clear list, deleting a recipe, a usual or a
  group, and adding a recipe's ingredients or a usual.
- **Who added it.** Each dashboard stamps its adds (`data-who`: `Rock` on the admin script
  tag, `Kit-Kat` on MarsBar's); the *other* dashboard shows "added by …" on the row.

**Pantry (`#sh-usuals`, the Pantry tab — named 2026-11-25)**
- The things you always keep in — cream, butter, toilet paper, cordial — each with **its
  usual amount** (*Thickened cream 300mL*, *Butter 250g*), sorted into **groups you make**
  (*Cupboard*, *Fridge*, *Cleaning & paper*, *Baking*…). It was "Cupboard staples", then
  "Usuals" (rock: "I also hate usuals") — six names were mocked up and **Pantry** won.
  ⚠ The list's aisle that used to be called *Pantry* is now **Tins & dry goods** (label
  only — its id is still `pantry`), so the two can't be confused.
- **A plain list you control, NOT a tracker:** nothing in it shows or changes what's
  already on the list. (The first staples lit a chip for anything on the list and took it
  off on a second tap; rock and Kit-Kat wanted "more control … not something we're
  tracking". Don't bring the tracking back.)
- The tab: the **Pantry heading** (a basket of bread, greens and a bottle), **group chips**
  (*All 16 · 🥫 Cupboard 6 · 🧊 Fridge 4…*, a scroller that fades at its edge; the pick is
  remembered as `sh-usual-group`; a group's picture is guessed from its name —
  `groupIcon()`, 🏷️ when nothing fits) and **Edit**; then a section per group, *No group*
  last, each a grid of **tiles** (picture, name, usual amount, a round **+** in the corner).
  - **+** → onto the list now, at its usual amount — and the tile **ticks for ~1.6 s**
    (`ui.uJust`) so you see it went on.
  - **tap the tile** → it spans the row and opens **− amount +** (starts at the usual
    amount) and **Add to list**.
  - Already on the list? The amount is **added**, and the row is flagged (⚑) for the shop
    to decide. With no amount, it just says it's already there.
  - Tiles are **stacked** (picture over name): a phone's two columns are too narrow to put
    a name beside the picture and the + — it broke words mid-letter.
- **Edit** → tiles become buttons with a pencil (tap one → its sheet), each group header
  gets **Rename** (the group sheet: name, who's in it, *Delete group* — its things stay,
  with no group, and Undo brings both back), and **+ New group** / **+ Add to the pantry**.
- **The pantry sheet:** picture + name (the picture follows the name until one is picked),
  **Usual amount** (the Amount control), **Group** chips with *+ New group* inline, Aisle,
  **Delete · Save**. Saving a name that's already there updates that one (one per name,
  `key()`), keeping its picture and group.
- **☆ Add to pantry** on an item's sheet saves it (name, amount, aisle) in one tap; it
  reads **★ In the pantry** if it already is, and tapping that takes it out.
- **Pictures:** each has its own, not its aisle's. Unpicked, it's **guessed from the name**
  (`iconFor` — `ICON_PHRASES` first, then the last word that means something, like
  `categorise()`: bin bags 🗑️, herbs/coriander/basil 🌿, coffee ☕️, cereal 🥣, cordial 🧃…;
  unknown → the aisle's). The sheet's picture opens a grid of ~95 (`STAPLE_ICONS`) plus
  **Auto**. ⚠ Symbols from the old BMP block (☕) need U+FE0F after them or they render as
  small grey text — the tables carry it; add it to any new one.
- **Stored as `staples`** (the server's name, from before either rename — kept so old
  lists and backups load): `{id, name, qty, cat, icon, group}`, and `groups: [{id, name}]`
  (≤ 30, one per name). The code still says `usual`/`staple`; only what you see says Pantry.
- **Starters & migration** (`starterGroups` / `starterStaples` in shopping.nix): 16 things
  in Cupboard / Fridge / Cleaning & paper, written on a fresh install and, ONCE, onto a list
  with no `staples` key. A list from the flat-staples days (has `staples`, no `groups`) is
  **grouped by aisle once** (`group_by_aisle()`: dairy/meat/produce/bakery/frozen → Fridge,
  household/personal/pets → Cleaning & paper, the rest → Cupboard), pictures kept. After
  that both keys exist, so emptying them sticks.

**Recipes (`#sh-recipes`, the Recipes tab)**
- The tab wears the pick's **second colour** (`--ag-alt`: her vine green, the HUD's second
  tone) — its buttons, chips, and the recipe/cook sheets. The **Recipes heading** is a pot
  of soup with rising steam, popping bubbles, a band of dots with a heart, rivets, a wooden
  spoon and a herb sprig (rock asked for "a bit more design in the pot").
- **+ New**, and **Find a recipe** (names and ingredients) once there are more than four.
  Then a **tile per recipe**: the dish on a plate, a big faded copy behind it, the tile
  washed in **the colour of its food** (`FOOD_HUE` by the recipe's picture — tomato-red
  bolognese, corn-yellow tacos; a hash of the name for anything unlisted; the HUD ignores
  it and stays in the viewer's colours), its ingredients as a **strip of pictures** (+N for
  the rest), and **✓ n** when n of them are on the list already.
- **Tap a recipe → its cook sheet:** every ingredient ticked to start; untick what's in the
  cupboard → **Add N to the list** (or *All / None*). Anything already on the list is
  marked *⚑ On the list — this adds to it* (left to you: 300mL twice may really mean
  600mL). They land in their aisles tagged with the recipe's name. **Edit** opens the editor.
- **"Usually have" (2026-11-25)** — spices, sauces, oil: part of the recipe, but in the
  cupboard for years. In the editor every ingredient has a **tick** ("Ticked ones go on the
  list. Untick what you always have"); unticked ones grey out with *🫙 Usually have — not
  added*. On the cook sheet they sit in their own **Usually have — not added** section,
  **unticked** — tap one if you've run out this time. *All / None* only touch the rest.
  Stored as `skip: true` on the ingredient (only when set — the server drops anything
  else, and recipes from before read as they did).
- **The recipe editor** (rock: "legit just a text box" → rebuilt 2026-11-24): picture +
  name; **Ingredients** as rows (tick, picture, name, amount pill, ×) — tap one to change
  it in place (name + the Amount control, Done); under them **Add an ingredient**: *What*,
  then − amount + with unit chips, **Add ingredient** (Enter works). `300ml cream` typed
  into *What* is parsed too. **Paste a whole list instead** takes one a line. An optional
  note; **Delete · Save**.
- Four **starter recipes** (`starterRecipes` in shopping.nix) are written in only when
  there is no state file at all. Deleting one sticks.

**The headings (Shopping, Pantry, Recipes)**
- The title is **Dancing Script Bold** — from nixpkgs (`pkgs.dancing-script`), served by
  BOTH Glances at `/assets/fonts/dancing-script-bold.ttf` (glance.nix `fontFiles`,
  marsbar.nix's asset farm) and loaded by `@font-face "Shop Script"` in cards.css, whose
  relative `url("fonts/…")` resolves next to cards.css. Nothing is fetched from the web.
  It's gradient-filled in the tab's colour with a swash underneath. Neon (Beon) and a
  cookbook serif (Fraunces) were mocked up too; handwritten was picked for both dashboards.
- The drawings (`TROLLEY`, `BASKET`, `POT` in shopping.js) are inline SVG coloured **only by
  classes** in cards.css (`--k`, `--k2`, a warm `--wood`) — never a literal — so they follow
  both colour pickers. The pot's steam and bubbles, the trolley's goods bobbing and the
  sparkles are CSS animations, still under reduced motion. On the HUD (asgard.css) the heading gets a grid instead of dots and the drawing
  glows; everything is squared and the tab labels are Orbitron.
- `--ag-alt` (the second colour) is a token each theme defines — `marsbar.css`
  (`hsl(var(--mb-h2) …)`) and `asgard.css` (`var(--hud2)`) — so cards.css stays
  theme-neutral.

**Sheets — one system for every editor**
- A bottom sheet on a phone (grab handle, the footer's buttons always in thumb reach), a
  centred dialog from 700px wide. Appended to `<body>` — MarsBar's `backdrop-filter` would
  trap `position: fixed` inside a card.
- Fits the phone keyboard (`visualViewport` → `--kb` / `--vvh`). Escape or the scrim
  closes; with unsaved changes the first close only warns. Deletes take a second tap.
- **The Amount control** (`amountHtml` / `amtRead` / `amtStep` / `amtUnit`) is one piece used
  everywhere an amount is set — item, pantry thing, ingredient, an open pantry tile: − box +
  with the same steps as the list's pill, and unit chips. A unit typed into the box
  (`300ml`) wins over the chips; tapping a unit with no amount starts somewhere sensible
  (100mL / 100g / 1L / 1kg / 1 pack).
- **Editors are drawn once and never repainted** — the other phone's changes can't wipe
  what's being typed. The **flag and cook sheets repaint live** (`paintSheet()` on every
  state), so a decision made on the other phone shows at once.
- ⚠ The sheet uses `--ag-surface` (opaque), not `--ag-pop` — pop is see-through and the
  list showed through it. HUD squaring for it is `.sh-scrim .sh-sheet` in asgard.css: a
  bare `.sh-sheet` loses to cards.css, which loads later.

## Instant, and fine on one bar of signal

The client never edits the server's state. What's drawn is the last server snapshot with
the queue of not-yet-confirmed changes **replayed on top** (`current()`), so a tap shows
immediately, a stale snapshot from the stream can't undo it on screen, and a change the
server refuses simply drops out of the queue (the row goes back, a toast says why).

Changes go one at a time, in order. If the network is gone (a 5xx from serve, or no answer)
they **wait and retry** with backoff, the footer says *Offline — N changes waiting*, and
they're sent the moment the stream reconnects or the browser says it's online. Every server
write is **idempotent** so a retry that had in fact arrived does nothing twice: an add
carries the client's own id (a second add with that id is ignored), a toggle says *which
way*, remove/edit name ids. ⚠ Keep that property if a new write is added — the client will
replay it.

The queue is **in memory**: closing the tab while offline loses what was waiting. A
deliberate trade — persisting it would mean replaying hour-old ticks over the other
person's newer ones.

## The server

- stdlib Python, one process, one lock. `GET /events` (SSE — `state` with everything on
  connect and after every change, `ping` every 15 s), `GET /state`, and POSTs:
  `items/{add,toggle,edit,remove,clear,restore}`, `recipes/{save,delete}`,
  `staples/{save,delete}` (the usuals), `groups/{save,delete}`. Every POST answers
  `{ok, state}`. Full contract in the file's header.
- **All or nothing:** a request refused halfway (a batch that would overfill the list) or
  one that can't be written to disk leaves memory exactly as it was.
- **State:** `/var/lib/private/shopping-list/state.json` (StateDirectory under
  DynamicUser), written to a temp file, fsynced and renamed on every change — a crash
  mid-write can't leave half a file. An unreadable file is kept as `state.json.broken-<t>`
  and the service starts empty (without re-seeding — the deleted starters would come back).
- **Limits:** 300 items, 200 recipes, 60 ingredients a recipe, 30 groups, 12 parts an
  item, 400 remembered names (160 sent to the page), names 80 chars, group names 40,
  quantities 24, bodies 64 KB.
- **Typos don't haunt the suggestions:** an item removed within two minutes of being added
  for the first time is dropped from the history too.

## Security — same as the other dashboard backends

- CORS answered only for the origins in `Modules/Server/_origins.nix`, never `*`.
- Every POST needs `X-Dash: 1` (a custom header forces a preflight only those origins
  pass), so another web page open on a tailnet browser can't write to the list.
- Strings are cleaned server-side (control characters and bidi overrides out — the
  zero-width joiner stays, it holds 👩‍🍳 together — lengths capped); ids and aisles match
  a pattern. `shopping.js` escapes everything it draws.
- `:9558` is not in `allowedTCPPorts`; only `tailscale0` is trusted. Her phone never needs
  a grant on it — it goes through `marsbar:1111/shop-api`.

## Backups (added 2026-11-24)

The list lives on the NVMe (`/var/lib/private/shopping-list/state.json`), which is exactly
what a reinstall rewrites. The data drives are never formatted (`Hosts/Asgard/_disko.nix`),
so copies go to **`/data/.state/backups/shopping-list/`** — real ext4 on the 8TB, beside the
arr databases. All in `Modules/Server/shopping.nix`:

- **When:** every night at 03:17 (`shopping-list-backup.timer`, `Persistent` — a night
  missed while Asgard was off runs at the next boot) **and every time the service stops**
  (`ExecStopPost`): each deploy, and the shutdown before a reinstall.
- **What's kept:** `latest.json` plus dated `state-<when>.json` copies — only when the
  list actually changed, so it's the **last 60 distinct versions**, not 60 nights. Root-only
  (0700 dir, 0600 files). A list that doesn't parse is never backed up over a good one.
- **Restore by itself:** `ExecStartPre` — no list on the NVMe but a backup on the drive →
  it's put back before the service starts. That's the fresh-install case, and it needs no
  hand. The unit is `WantsMountsFor=/data/.state` (soft — the list must still run with the
  drive missing) so that first start sees the drive.
- **Restore by hand** (on Asgard): `sudo shopping-list-restore` lists them (with "18 to
  get, 6 recipes, 14 staples" per copy); `sudo shopping-list-restore latest` or `… <file>`
  puts one back. It stops the service first, which backs up the list you had — so a restore
  can be undone with another restore.
- A restore gives the list a **new `sid`**, so every open dashboard takes it instead of
  ignoring it as older than what it has (`take()` in shopping.js).
- ⚠ **nofail drives:** with the 8TB missing, `/data/.state` is an empty folder on the NVMe.
  Every script checks `mountpoint` first and does nothing (the restore command says why)
  rather than write a "backup" that would vanish with the NVMe. The catch: a fresh install
  booted with the 8TB unplugged starts the list fresh (starters), and once that list exists
  nothing auto-restores — use `shopping-list-restore latest`.
- The three scripts are `writeShellApplication`s (shellchecked at build). Their paths can be
  overridden by `SHOP_STATE_DIR` / `SHOP_BACKUP_DIR` / `SHOP_BACKUP_MOUNT` — only so they can
  be exercised away from Asgard; the units never set them.

## Traps

- ⚠ **It's user data.** A rebuild never touches the list. A reinstall restores it from
  the backup on the 8TB (above) — if that drive is there.
- ⚠ **`/shop-api` is a persisted serve mount** (see `Claude/marsbar.md` → serve mounts).
  Renaming it needs an explicit `tailscale serve --http=1111 --set-path=/shop-api off` on
  the marsbar node; deleting the Nix line does not remove it. And it must never collide
  with a Glance page slug — hence the `-api` suffix.
- ⚠ **MarsBar has used all three of Glance's columns.** Shopping took the third; the
  read-only Network card moved to the foot of her Eclipse column. A fourth section there
  means a second page (behind ☰) or sharing a column.
- **The aisle tables live in the client** (`AISLES`, `WORDS`, `PHRASES` in shopping.js).
  The server stores whatever `[a-z]{1,12}` it's given; an id the client doesn't know is
  drawn under Other. `key()` (what counts as "the same item") exists in BOTH files — keep
  them in step or merging and "on the list" disagree.
- ⚠ `#sh-usuals` and `#sh-recipes` are INSIDE `#sh-list` (they're the Pantry and Recipes
  panes), so `onClick` routes taps in order — the sheet, a tab, `#sh-usuals`,
  `#sh-recipes`, then the list — otherwise every pane button is swallowed by the list
  handler and does nothing.
- ⚠ `render()` must call `drawList()` FIRST: it builds the card the tabs and the trolley bar
  live in. Drawn before it, the first paint had no active tab and no trolley bar.
- The panes are hidden with the `hidden` attribute, which `.sh-pane { display: flex }`
  would override — hence `.sh-pane[hidden] { display: none }`. Keep it.
- **The swipe** (`swipe()`) uses passive touch listeners only, so it can never block a
  scroll: it gives up as soon as the finger moves more up/down than across, and ignores
  touches that start on something that scrolls sideways or takes text (the group chips,
  inputs, a stepper, the tab bar). The pane leans a little with the finger; at the first
  or last tab it barely moves. Glance itself has no touch gestures (checked) to fight with.
- Rows are a **keyed** list (not `Dash.paint`'s positional morph) so they slide when they
  change aisle or get ticked.
- The toast is appended to `<body>` (same reason as the sheet). It sits above Glance's
  phone bar — measured from **`.mobile-navigation`'s top edge**, never its height: that
  box also holds the ☰ drawer parked below the screen, so it's ~600px tall and the toast
  used to float mid-screen. While a sheet is open it moves to the **top** (`.top`), and
  `openSheet`/`closeSheet` re-place one that's already showing (`placeToast()`).
- ⚠ Glance overrides `HTMLElement.prototype.animate` — the row animations use
  `Element.prototype.animate` (as garden.js does).
