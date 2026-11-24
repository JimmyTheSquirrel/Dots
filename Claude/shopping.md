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

```
her phone ──► marsbar:1111/shop-api/* ──► tailscale serve ──┐
                                                            ├──► 127.0.0.1:9558 shopping-list ──► state.json
rock's browser ──► asgard:9558 (tailnet, CORS) ─────────────┘        (one SSE stream per open card)
```

---

## What it does

**The list (`#sh-list`)**
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
- **⋯ on a row** opens its editor: name, how many, aisle, **Remove**.
- **Undo** (a toast at the bottom) after Remove, Clear, Clear list, deleting a recipe or
  adding a recipe's ingredients.
- **Who added it.** Each dashboard stamps its adds (`data-who`: `Rock` on the admin script
  tag, `Kit-Kat` on MarsBar's); the *other* dashboard shows "added by …" on the row.

**Recipes (`#sh-recipes`)**
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

## Traps

- ⚠ **It's user data.** A rebuild never touches the list; **reinstalling Asgard starts it
  empty** (bar the starters). Nothing backs it up — copy `state.json` off if that matters.
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
- Rows are a **keyed** list (not `Dash.paint`'s positional morph) so they slide when they
  change aisle or get ticked. An open row editor or recipe editor is drawn once and never
  repainted, so the other person's changes can't wipe what's being typed.
- The toast is appended to `<body>`: inside a card, MarsBar's `backdrop-filter` would
  trap `position: fixed`. It lifts itself above Glance's phone bar when that's showing.
- ⚠ Glance overrides `HTMLElement.prototype.animate` — the row animations use
  `Element.prototype.animate` (as garden.js does).
