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

**It is ONE card** (`#sh-list`), on purpose — you both just run down it in the shop.
Top to bottom: the add box, the usuals, **Cupboard staples** and the recipe book — each
**folded to one bar** (a little stack of pictures, a count, a chevron) — then the list by
aisle, then In the trolley. The recipe book opens in place (an animated fold), is **shut by default**, and
remembers open/shut per browser (`localStorage["sh-recipes"]`). It was two cards for a day;
rock and Kit-Kat both wanted the one — don't split it back out.

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
- **Usuals.** Under the box: anything bought at least twice that isn't on the list, one
  tap to add. While typing, it becomes *Bought before* — matches from the history.
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
  trolley* puts it back on the list. The merged row flashes.
- **Tap a quantity pill** and it opens into **− 2L +** right on the row (added 2026-11-24 at
  rock's request — "an easier way to increase / decrease"). Each tap saves; a run of quick
  taps goes to the server as ONE edit (`send()` folds a queued edit for the same item into
  the next). It folds back after 4 quiet seconds or the first tap anywhere else. A ticked
  row's pill is just a label. A row with no quantity has no pill — ⋯ sets one.
- **⋯ on a row** opens its editor: name, **How many** (− amount +), **Unit** chips
  (each · g · kg · mL · L · pack · tin · bottle · bunch, plus whatever odd unit the item
  already had, e.g. *cloves*), aisle, **Remove**. Tapping a unit on an item with no amount
  starts it somewhere sensible (100mL / 100g / 1L / 1kg / 1 pack). A unit typed into the
  amount box (`300ml`) wins over the chips.

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
- **Undo** (a toast at the bottom) after Remove, Clear, Clear list, deleting a recipe or
  adding a recipe's ingredients.
- **Who added it.** Each dashboard stamps its adds (`data-who`: `Rock` on the admin script
  tag, `Kit-Kat` on MarsBar's); the *other* dashboard shows "added by …" on the row.

**Cupboard staples (`#sh-staples`, inside the list card — added 2026-11-24)**
- The things you always keep in — toilet paper, cereal, cordial — saved so they're quick to
  add when you're running low. **A plain list you control, NOT a tracker:** nothing in it
  shows or changes what's already on the list. (The first version lit a chip for anything on
  the list and took it off on a second tap; rock and Kit-Kat wanted "more control … not
  something we're tracking", so it was rebuilt the same day. Don't bring the tracking back.)
- Different from the **Usuals** row, which is automatic (bought twice or more); staples are
  the ones you chose. Usuals don't repeat a staple.
- Open the bar (shut by default, remembered per browser as `sh-staples`): a row per staple,
  in aisle order, showing its usual amount if it has one ("usually 24 packs").
  - **round +** → onto the list now, at its usual amount.
  - **tap the name** → the row opens with **− amount +** (the same steps as the list:
    packs, mL/L, g/kg…; starts at the usual amount, or one) and **Add to list**.
  - Already on the list? The amount is **added to** it (the server sums: 24 packs + 24 packs
    = 48 packs; 2L + 2.5L = 4.5L). With no amount on either, it just says it's already there.
  - A fresh add can be undone from the toast.
- **Edit staples**: each row gets a × (take it out, with Undo) and an add box at the top that
  reads like the list's — `cordial, 24 pack toilet paper` → two staples, and **an amount in
  front becomes its usual one**. Saving a name that's already a staple updates it (one per
  name, `key()`), which is also how to change a usual amount.
- **★ Keep as a staple** in a row's ⋯ editor saves that item (name, quantity, aisle) as a
  staple in one tap; it reads **★ A staple** if it already is one, and tapping that takes
  it out.
- Twelve generic **starter staples** (`starterStaples` in shopping.nix) are written in on a
  fresh install — and, ONCE, onto a list from before staples existed (state.json had no
  `staples` key). After that the key is there, so taking them all out sticks.

**Recipes (`#sh-recipes`, built by shopping.js inside the list card)**
- Tap the bar to open the book, tap it again to fold it away. Shutting it closes an open
  recipe, but an unsaved recipe *editor* survives for when it's opened again.
- Tap a recipe → its ingredients, each pre-ticked **unless it's already on the list**
  (marked *on the list*). Untick what's in the cupboard → **Add N to the list**. They land
  in their aisles tagged with the recipe's name, and merge with anything already there.
- **+ New recipe / Edit**: a name, a picture (emoji), ingredients one a line (same parsing
  as the add box), an optional note. Delete takes a second tap.
- A search box appears once there are more than six.
- Four **starter recipes** (`starterRecipes` in `shopping.nix`) are written in only when
  there is no state file at all — a fresh install. Deleting one sticks.

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
  `items/{add,toggle,edit,remove,clear,restore}`, `recipes/{save,delete}`. Every POST
  answers `{ok, state}`. Full contract in the file's header.
- **All or nothing:** a request refused halfway (a batch that would overfill the list) or
  one that can't be written to disk leaves memory exactly as it was.
- **State:** `/var/lib/private/shopping-list/state.json` (StateDirectory under
  DynamicUser), written to a temp file, fsynced and renamed on every change — a crash
  mid-write can't leave half a file. An unreadable file is kept as `state.json.broken-<t>`
  and the service starts empty (without re-seeding — the deleted starters would come back).
- **Limits:** 300 items, 200 recipes, 60 ingredients a recipe, 400 remembered names
  (160 sent to the page), names 80 chars, quantities 24, bodies 64 KB.
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
- ⚠ `#sh-recipes` and `#sh-staples` are INSIDE `#sh-list`, so `onClick` must route their
  taps before the list's branch (`#sh-staples` first; the list branch excludes
  `#sh-recipes`) — otherwise every drawer button is swallowed by the list handler and does
  nothing.
- Rows are a **keyed** list (not `Dash.paint`'s positional morph) so they slide when they
  change aisle or get ticked. An open row editor or recipe editor is drawn once and never
  repainted, so the other person's changes can't wipe what's being typed.
- The toast is appended to `<body>`: inside a card, MarsBar's `backdrop-filter` would
  trap `position: fixed`. It lifts itself above Glance's phone bar when that's showing.
- ⚠ Glance overrides `HTMLElement.prototype.animate` — the row animations use
  `Element.prototype.animate` (as garden.js does).
