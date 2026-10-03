{ ... }: {
  # Asgard — the Glance dashboard (port 8888): its whole YAML config (pages,
  # widgets, the CSS/JS injected into <head>), the Yggdrasil banner asset, and
  # the native unit that runs it.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    # ── Glance assets (served at /assets/) ──
    glanceAssets = pkgs.runCommand "glance-assets" {} ''
      mkdir -p $out
      cp ${../../Resources/Glance/yggdrasil-banner.png} $out/yggdrasil.png
    '';

    # ── Power dashboard tunables (Monitoring page) ──
    #
    # Reference ceiling for the draw bar, in watts. Deliberately NOT the plug's
    # 3680 W rating: against that scale an idling server sits at ~1% and the bar
    # never visibly moves. Set it near this box's realistic peak instead.
    powerRefW = 150.0;
    #
    # Electricity tariff in $/kWh — REAL, from the GloBird GLOSAVE offer
    # (NSW / Ausgrid), replacing the earlier guess of 0.32.
    #
    # The plan is stepped, not flat:
    #   first 15.00 kWh/day   $0.28600  →  $0.27742 after discounts
    #   balance (>15/day)     $0.31350  →  $0.30410 after discounts
    # "after discounts" = the 1% direct-debit + 2% pay-on-time conditional
    # discounts, which apply to usage AND the daily supply charge.
    #
    # The BALANCE rate is the correct one here, because these figures answer
    # "what does this device cost me" — a marginal question. Billing for the
    # 28 days to 24-Aug-2026 averaged 16.81 kWh/day, comfortably over the 15
    # kWh step, so every additional kWh a plug draws is charged at the balance
    # rate. ⚠ If daily household use ever drops below 15 kWh, the marginal rate
    # becomes 0.27742 instead and this should follow it.
    powerRate = 0.3041;

    # Daily supply charge, $/day, after the same 3% conditional discounts
    # ($0.95700 before). Deliberately NOT folded into powerRate: it is billed
    # whether or not a single device is plugged in, so attributing any of it to
    # a plug's consumption would be wrong. Shown on its own row for context,
    # because per-device costs alone understate the actual bill.
    powerSupplyDaily = 0.92829;

    # ── Glance YAML config ──
    # No secret is ever written into this file — it lands in the world-readable
    # Nix store. The two that Glance needs (the HA token and the SABnzbd API
    # key) are pulled in by Glance itself when it loads the config, via
    # `readFileFromEnv` (see systemd.services.glance below).
    #
    # Runs as native systemd service (not container) so server-stats widget
    # can read host CPU/memory/disk directly from /proc and /sys.
    glanceConfig = pkgs.writeText "glance.yml" ''
      server:
        port: 8888
        assets-path: ${glanceAssets}

      document:
        head: |
          <style>
            /* ── Ambient colour field ───────────────────────────────────────
               Four large, heavily-blurred colour orbs fixed behind the whole
               page — mint, cyan, violet and a warm gold. This is the standard
               glassmorphism trick: the cards are semi-transparent with a
               backdrop blur, so these tint whatever sits above them and the
               dashboard stops reading as one flat green. The colour lives in
               the BACKGROUND, not in fifty repainted borders, which is why it
               adds variety without fighting the data.

               Very low alpha on purpose (0.05–0.09). At higher values this
               turns into a lava lamp and the text loses contrast — the whole
               point is atmosphere you notice only if you look for it.

               position: fixed so it does not scroll, and z-index/pointer-events
               keep it behind and non-interactive. */
            body::before {
              content: "";
              position: fixed;
              inset: -20%;
              z-index: -1;
              pointer-events: none;
              background:
                radial-gradient(38% 34% at 18% 14%, hsla(160, 70%, 45%, 0.09), transparent 70%),
                radial-gradient(34% 30% at 84% 22%, hsla(190, 75%, 50%, 0.075), transparent 70%),
                radial-gradient(40% 36% at 74% 82%, hsla(265, 65%, 55%, 0.065), transparent 70%),
                radial-gradient(30% 28% at 26% 88%, hsla(42, 70%, 52%, 0.05), transparent 70%);
              filter: blur(30px);
            }

            /* ── Glass cards ────────────────────────────────────────────────
               Mint-green base, deliberately NOT the purple used on marsbar.

               Two techniques from the glassmorphism playbook are doing the work:
                 1. ALPHA-CHANNEL GRADIENTS, not a solid colour at low opacity.
                    A flat rgba fill greys everything behind it evenly; a gradient
                    between two alphas lets the ambient orbs show through unevenly,
                    which is what actually reads as glass.
                 2. INSET HIGHLIGHT — a 1px inner top edge via box-shadow inset,
                    imitating light catching the lip of a pane. Cheaper and far
                    subtler than an outline, and it survives on any background.

               Still no borders: the nesting fix below means this card is the only
               container, and outlines are what made it look busy before. */
            .widget {
              position: relative;
              border: none;
              border-radius: 18px;
              padding: 16px 16px 18px;
              background: linear-gradient(168deg,
                hsla(158, 26%, 14%, 0.50),
                hsla(180, 18%, 10%, 0.30) 55%,
                hsla(200, 20%, 9%, 0.22));
              backdrop-filter: blur(11px) saturate(125%);
              box-shadow:
                inset 0 1px 0 hsla(160, 60%, 80%, 0.07),
                0 10px 28px -18px hsla(180, 60%, 8%, 0.9);
              transition: background 0.35s ease, box-shadow 0.35s ease;
            }
            .widget:hover {
              background: linear-gradient(168deg,
                hsla(158, 30%, 16%, 0.58),
                hsla(180, 20%, 11%, 0.34) 55%,
                hsla(200, 22%, 10%, 0.26));
              box-shadow:
                inset 0 1px 0 hsla(160, 65%, 82%, 0.11),
                0 12px 32px -18px hsla(180, 60%, 8%, 0.95);
            }
            /* Top edge highlight, run through three hues rather than one so the
               accent colour shifts across the width of the card. This is where
               most of the "not so one-sided" comes from up close. */
            .widget::after {
              content: "";
              position: absolute;
              left: 20px; right: 20px; top: 0;
              height: 1px;
              background: linear-gradient(to right,
                transparent,
                hsla(160, 75%, 62%, 0.30) 25%,
                hsla(190, 70%, 62%, 0.22) 55%,
                hsla(265, 60%, 68%, 0.14) 80%,
                transparent);
            }
            /* ⚠ THE "border within a border" FIX.
               Glance wraps every widget's content in its own framed box:
                 .widget-content:not(.widget-content-frameless), .widget-content-frame {
                   background: var(--color-widget-background);
                   border: 1px solid var(--color-widget-content-border);
                   box-shadow: 0px 3px 0px 0px ...;
                 }
               With the .widget card above ALSO drawing a container, every panel
               rendered as a box inside a box — which is what looked so bad. The
               outer card is the one we style, so the inner frame is flattened to
               nothing here. Keep these two in sync: restoring a border on .widget
               without removing this, or vice versa, brings the nesting straight
               back. `frameless` is Glance's own opt-out but is only applied to a
               couple of widget types, so it cannot be relied on. */
            .widget-content:not(.widget-content-frameless),
            .widget-content-frame {
              background: transparent;
              border: none;
              box-shadow: none;
              padding: 0;
            }

            .widget-header {
              margin-bottom: 12px;
              padding-bottom: 8px;
            }
            .widget-header .widget-title {
              letter-spacing: 0.13em;
              font-weight: 600;
              color: hsla(160, 34%, 74%, 0.72);
            }

            /* ── Monitor widget tweaks ── */
            .widget-type-monitor .monitor-site {
              border-radius: 8px;
              transition: background-color 0.2s ease;
            }

            /* ── Yggdrasil tree banner ── */
            .ygg-widget {
              position: relative;
            }
            .ygg-widget::before,
            .ygg-widget::after {
              content: "";
              display: block;
              position: absolute;
              top: 0;
              left: 50%;
              transform: translateX(-50%);
              width: 200px;
              height: 200px;
              background-repeat: no-repeat;
              background-position: center;
              background-size: contain;
              pointer-events: none;
            }
            /* Ring — SVG behind the tree */
            .ygg-widget::before {
              background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400'%3E%3Cdefs%3E%3CradialGradient id='bg' cx='50%25' cy='50%25' r='45%25'%3E%3Cstop offset='0%25' stop-color='hsla(160,30%25,25%25,0.12)'/%3E%3Cstop offset='100%25' stop-color='hsla(160,30%25,15%25,0)'/%3E%3C/radialGradient%3E%3C/defs%3E%3Ccircle cx='200' cy='200' r='180' fill='url(%23bg)'/%3E%3Cg fill='none' stroke='hsla(160,35%25,55%25,0.35)' stroke-width='1.5'%3E%3Ccircle cx='200' cy='200' r='178'/%3E%3Ccircle cx='200' cy='200' r='170'/%3E%3C/g%3E%3Cg fill='hsla(160,40%25,60%25,0.45)' font-family='serif' font-size='14' font-weight='bold'%3E%3Ctext x='200' y='28' text-anchor='middle'%3E%E1%9A%A0 %E1%9A%B1 %E1%9A%A6 %E1%9A%B2 %E1%9A%A8 %E1%9A%B7 %E1%9A%A2%E1%9A%B3 %E1%9A%BE %E1%9A%A9%3C/text%3E%3Ctext transform='translate(375,100) rotate(72)' text-anchor='middle'%3E%E1%9A%B1%E1%9A%A6%E1%9A%B2%E1%9A%A8%E1%9A%B7%3C/text%3E%3Ctext transform='translate(390,240) rotate(90)' text-anchor='middle'%3E%E1%9A%A2%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%3C/text%3E%3Ctext transform='translate(350,350) rotate(115)' text-anchor='middle'%3E%E1%9A%B1%E1%9A%A6%E1%9A%B7%E1%9A%A8%E1%9A%B2%3C/text%3E%3Ctext x='200' y='390' text-anchor='middle'%3E%E1%9A%BE %E1%9A%A9 %E1%9A%A0 %E1%9A%B1 %E1%9A%A6 %E1%9A%B2 %E1%9A%A8 %E1%9A%B7 %E1%9A%A2%3C/text%3E%3Ctext transform='translate(50,350) rotate(-115)' text-anchor='middle'%3E%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%E1%9A%B1%3C/text%3E%3Ctext transform='translate(10,240) rotate(-90)' text-anchor='middle'%3E%E1%9A%A6%E1%9A%B2%E1%9A%A8%E1%9A%B7%E1%9A%A2%3C/text%3E%3Ctext transform='translate(25,100) rotate(-72)' text-anchor='middle'%3E%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%E1%9A%B1%3C/text%3E%3C/g%3E%3Cg fill='none' stroke='hsla(160,35%25,55%25,0.2)' stroke-width='0.6'%3E%3Cpath d='M160,340 Q175,330 190,340 Q195,350 190,360 Q180,365 170,358 Q162,350 160,340Z'/%3E%3Cpath d='M240,340 Q225,330 210,340 Q205,350 210,360 Q220,365 230,358 Q238,350 240,340Z'/%3E%3C/g%3E%3C/svg%3E");
              opacity: 0.8;
              filter: drop-shadow(0 0 12px hsla(160, 50%, 45%, 0.25));
              transition: opacity 0.3s ease, filter 0.3s ease;
            }
            /* Tree image — on top of ring */
            .ygg-widget::after {
              background-image: url("/assets/yggdrasil.png");
              opacity: 0.85;
              filter: drop-shadow(0 0 8px hsla(160, 50%, 40%, 0.3));
              transition: opacity 0.3s ease, filter 0.3s ease;
            }
            .ygg-widget:hover::before,
            .ygg-widget:hover::after {
              opacity: 1;
              filter: drop-shadow(0 0 18px hsla(160, 55%, 50%, 0.4));
            }
            /* Reserve space for the absolutely positioned banner */
            .ygg-widget {
              padding-top: 208px;
            }

            /* ── Power monitoring (Home Assistant plug) ── */
            .pw { display: flex; flex-direction: column; gap: 15px; }

            /* Hero — the one number worth reading from across the room */
            .pw-hero {
              display: flex; align-items: flex-end; justify-content: space-between;
              gap: 20px; flex-wrap: wrap;
            }
            .pw-big {
              font-size: 3.2rem;
              line-height: 0.95;
              font-weight: 500;
              color: var(--color-text-highlight);
              font-variant-numeric: tabular-nums;
              text-shadow: 0 0 16px hsla(160, 55%, 50%, 0.25);
            }
            .pw-big-unit {
              font-size: var(--font-size-h4);
              color: var(--color-text-subdue);
              margin-left: 5px;
            }
            .pw-trail {
              text-align: right;
              font-size: var(--font-size-h6);
              color: var(--color-text-subdue);
              line-height: 1.75;
            }

            /* Draw bar. Scaled to a realistic ceiling, NOT the plug's 3680 W
               rating — against 3.6 kW an idling server is an invisible sliver. */
            .pw-bar {
              position: relative; height: 6px; border-radius: 3px;
              background: hsla(160, 30%, 50%, 0.10); overflow: hidden;
            }
            .pw-bar-fill {
              position: absolute; top: 0; bottom: 0; left: 0; border-radius: 3px;
              background: linear-gradient(90deg, hsl(160, 50%, 42%), hsl(160, 72%, 58%));
              box-shadow: 0 0 10px hsla(160, 60%, 50%, 0.35);
            }
            .pw-scale {
              display: flex; justify-content: space-between;
              margin-top: -7px;
              font-size: var(--font-size-h6);
              color: var(--color-text-subdue);
            }

            /* Stat grid — auto-fit reflows instead of overflowing the column */
            .pw-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(102px, 1fr));
              gap: 13px 20px;
              border-top: 1px solid var(--color-separator);
              padding-top: 13px;
            }
            .pw-grid-bare { border-top: none; padding-top: 0; }
            .pw-cell { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
            /* Power monitoring type scale — bumped a step across the board. The
               h6/h4 defaults were fine on an ultrawide at arm's length and small
               everywhere else, and this is the page that gets read most. */
            .pw-k {
              font-size: 0.78rem; text-transform: uppercase;
              letter-spacing: 0.08em; color: var(--color-text-subdue);
            }
            .pw-v {
              font-size: 1.05rem; color: var(--color-text-base);
              font-variant-numeric: tabular-nums;
            }
            .pw-v-lg { font-size: var(--font-size-h2); color: var(--color-text-highlight); }
            .pw-v-sub { font-size: var(--font-size-h6); color: var(--color-text-subdue); }

            /* Switch rows — sized to take lights and plugs later, not just the one */
            .pw-sw-row {
              display: flex; align-items: center; gap: 11px; padding: 10px 0;
              border-bottom: 1px solid hsla(160, 30%, 50%, 0.08);
            }
            .pw-sw-row:last-of-type { border-bottom: none; }
            .pw-sw-name { flex: 1; min-width: 0; }
            .pw-sw-label { color: var(--color-text-base); }
            .pw-sw-note { font-size: var(--font-size-h6); color: var(--color-text-subdue); }
            .pw-pill {
              flex-shrink: 0;
              font-size: var(--font-size-h6); text-transform: uppercase;
              letter-spacing: 0.07em; padding: 3px 11px; border-radius: 999px;
            }
            .pw-on {
              color: hsl(160, 60%, 62%); background: hsla(160, 50%, 45%, 0.14);
              border: 1px solid hsla(160, 50%, 50%, 0.30);
            }
            /* "off" is a normal state, not a fault — this was styled red, which
               made every idle plug read as an alarm. Red stays reserved for
               things that are actually wrong. */
            .pw-off {
              color: var(--color-text-subdue); background: hsla(0, 0%, 50%, 0.10);
              border: 1px solid hsla(0, 0%, 60%, 0.18);
            }
            .pw-lock {
              flex-shrink: 0; font-size: var(--font-size-h6);
              letter-spacing: 0.07em; color: hsl(160, 80%, 62%);
            }
            .pw-empty {
              font-size: var(--font-size-h6); color: var(--color-text-subdue);
              font-style: italic; padding-top: 9px;
            }

            /* ── Device cards ──
               <details>/<summary> is doing the expand/collapse. Glance injects
               widget markup with innerHTML, which does NOT execute <script>, so
               anything JS-driven inside a template is dead on arrival — native
               disclosure is the only thing that works without a head-side hook. */
            /* Device cards. An accent stripe down the leading edge picks up the
               live/idle state, so a glance across the grid shows what is drawing
               power without reading a single label. */
            /* Device cards — borderless too. A soft diagonal gradient separates
               them from the widget behind, and a low-alpha stripe down the
               leading edge gives the grid some rhythm without outlining
               everything. */
            .pw-card {
              position: relative;
              overflow: hidden;
              border: none;
              border-radius: 14px;
              background: linear-gradient(150deg, hsla(160, 26%, 22%, 0.28), hsla(160, 18%, 14%, 0.10));
              transition: background 0.25s ease;
            }
            .pw-card::before {
              content: "";
              position: absolute;
              left: 0; top: 0; bottom: 0;
              width: 2px;
              background: linear-gradient(to bottom,
                hsla(160, 70%, 58%, 0.42), hsla(160, 55%, 55%, 0.12), transparent);
            }
            /* Rotate the accent hue per card — mint, cyan, violet. Keeps the grid
               from reading as one repeated green tile without colouring the data
               itself, which has to stay semantic (green ok / red bad). */
            .pw-cards .pw-card:nth-child(3n+2)::before {
              background: linear-gradient(to bottom,
                hsla(192, 72%, 60%, 0.42), hsla(192, 55%, 55%, 0.10), transparent);
            }
            .pw-cards .pw-card:nth-child(3n)::before {
              background: linear-gradient(to bottom,
                hsla(265, 62%, 68%, 0.40), hsla(265, 50%, 60%, 0.10), transparent);
            }
            .pw-card:hover {
              background: linear-gradient(150deg, hsla(160, 30%, 26%, 0.34), hsla(160, 18%, 15%, 0.13));
            }
            .pw-card[open] {
              background: linear-gradient(150deg, hsla(160, 32%, 28%, 0.36), hsla(160, 18%, 16%, 0.15));
            }
            /* Tile grid. auto-fill + minmax keeps cards card-sized instead of
               letting one device stretch the full width of an ultrawide, and
               takes extra devices later without a layout change. align-items
               start so an expanded card does not stretch its row-mates. */
            .pw-cards {
              display: grid;
              grid-template-columns: repeat(auto-fill, minmax(248px, 1fr));
              gap: 12px;
              align-items: start;
            }

            .pw-card-head {
              display: flex; flex-direction: column;
              padding: 12px 14px; cursor: pointer; list-style: none;
            }
            .pw-card-top { display: flex; align-items: center; gap: 9px; }
            /* Both spellings needed — WebKit still uses the pseudo-element */
            .pw-card-head::-webkit-details-marker { display: none; }
            .pw-card-head::marker { content: ""; }

            .pw-chev {
              flex-shrink: 0; width: 7px; height: 7px;
              border-right: 1.5px solid hsla(160, 50%, 60%, 0.7);
              border-bottom: 1.5px solid hsla(160, 50%, 60%, 0.7);
              transform: rotate(-45deg);
              transition: transform 0.2s ease;
            }
            .pw-card[open] .pw-chev { transform: rotate(45deg); }

            .pw-card-name {
              color: var(--color-text-highlight);
              font-size: 1.06rem; font-weight: 600;
              flex: 1; min-width: 0;
              overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
            }
            /* display:block — these are <span>s inside a <summary>, and an
               inline box ignores the top margin that separates it from the name */
            .pw-card-sub {
              display: block;
              font-size: var(--font-size-h6); color: var(--color-text-subdue);
              margin: 3px 0 0 16px;
            }

            /* Label left, value right — reads as a spec sheet at tile width,
               where the previous side-by-side columns had nowhere to go. */
            .pw-card-stats {
              display: flex; flex-direction: column; gap: 7px;
              margin-top: 11px; padding-top: 10px;
              border-top: 1px solid hsla(160, 35%, 50%, 0.12);
            }
            .pw-mini { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; }
            .pw-mini .pw-k { font-size: 0.66rem; }
            .pw-mini .pw-v { font-size: var(--font-size-h5); }

            .pw-card-body {
              padding: 2px 14px 14px;
              display: flex; flex-direction: column; gap: 14px;
            }
            /* Section headings inside a card: a small glyph and a rule that fades
               out to the right, so groups separate without another hard border. */
            .pw-sec-title {
              display: flex; align-items: center; gap: 9px;
              font-size: var(--font-size-h6); text-transform: uppercase;
              letter-spacing: 0.12em; color: hsl(160, 48%, 66%);
              padding-bottom: 8px; margin-bottom: 2px;
            }
            .pw-sec-title::before { content: "◆"; font-size: 0.58em; color: hsla(160, 60%, 58%, 0.55); }
            .pw-sec-title::after {
              content: ""; flex: 1; height: 1px;
              background: linear-gradient(to right, hsla(160, 45%, 55%, 0.18), transparent);
            }

            /* Action row — the toggle lives here */
            .pw-actions {
              display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
              border-top: 1px solid var(--color-separator); padding-top: 13px;
            }
            /* Sliding switch, matching the marsbar dashboard. State is taken from
               the sibling .pw-pill that PRECEDES this button — the toggle script
               already paints .pw-on/.pw-off there, so this needs no markup and no
               JS change. font-size:0 hides the word "TOGGLE" (and the "···" the
               script writes while a request is in flight). */
            .pw-toggle {
              position: relative;
              flex: none;
              width: 48px; height: 27px;
              padding: 0;
              font-size: 0;
              border-radius: 999px;
              cursor: pointer;
              background: hsla(160, 10%, 45%, 0.20);
              border: 1px solid hsla(160, 25%, 60%, 0.18);
              transition: background 0.22s ease, border-color 0.22s ease;
            }
            .pw-toggle::after {
              content: "";
              position: absolute; top: 3px; left: 3px;
              width: 19px; height: 19px;
              border-radius: 50%;
              background: hsl(160, 10%, 66%);
              transition: transform 0.22s ease, background 0.22s ease;
            }
            .pw-pill.pw-on ~ .pw-toggle {
              background: linear-gradient(120deg, hsl(160, 78%, 54%), hsl(160, 72%, 56%));
              border-color: hsla(160, 80%, 68%, 0.55);
            }
            .pw-pill.pw-on ~ .pw-toggle::after {
              transform: translateX(21px);
              background: hsl(160, 40%, 97%);
            }
            .pw-toggle:disabled { opacity: 0.3; cursor: not-allowed; }
            .pw-toggle:hover:not(:disabled) {
              background: hsla(160, 45%, 45%, 0.20);
              border-color: hsla(160, 50%, 50%, 0.50);
            }
            .pw-toggle:disabled {
              cursor: not-allowed; opacity: 0.55;
              color: hsl(160, 80%, 62%);
              background: hsla(160, 60%, 45%, 0.08);
              border-color: hsla(160, 70%, 55%, 0.28);
            }
            .pw-action-note {
              font-size: var(--font-size-h6); color: var(--color-text-subdue);
              flex: 1; min-width: 160px;
            }

            /* Section heading above a group of tiles */
            .pw-group-title {
              font-size: var(--font-size-h6); text-transform: uppercase;
              letter-spacing: 0.1em; color: var(--color-text-subdue);
              margin-bottom: 9px;
            }

            /* One tile per row once a phone-width column can't hold two */
            @media (max-width: 460px) {
              .pw-cards { grid-template-columns: 1fr; }
            }

            /* Group bar — one control that fans out to every member below it */
            .pw-groupbar {
              display: flex; align-items: center; gap: 14px; flex-wrap: wrap;
              padding: 13px 15px; margin-bottom: 14px;
              border: 1px solid hsla(160, 45%, 50%, 0.28);
              border-radius: 11px;
              background: hsla(160, 40%, 40%, 0.08);
            }
            .pw-groupbar-id { display: flex; flex-direction: column; gap: 3px; flex: 1; min-width: 0; }
            .pw-groupbar-name { color: var(--color-text-highlight); font-size: var(--font-size-h4); }

            /* Toggle sitting in a card header, beside the state pill */
            .pw-card-top .pw-toggle { padding: 3px 11px; }

            /* Generic label-left / value-right rows, for the side widgets */
            .pw-rows { display: flex; flex-direction: column; gap: 9px; }
            .pw-row {
              display: flex; justify-content: space-between;
              align-items: baseline; gap: 12px;
            }
            .pw-row + .pw-row {
              border-top: 1px solid hsla(160, 30%, 50%, 0.07);
              padding-top: 9px;
            }
            .pw-row-hi .pw-v {
              color: var(--color-text-highlight);
              font-size: var(--font-size-h3);
            }

            /* Empty state for a section whose hardware does not exist yet —
               reads as "nothing here yet", not as something broken. */
            .pw-placeholder {
              border: 1px dashed hsla(160, 40%, 50%, 0.22);
              border-radius: 11px;
              padding: 20px 18px;
              text-align: center;
              color: var(--color-text-subdue);
              font-size: var(--font-size-h6);
              line-height: 1.75;
            }
            .pw-placeholder strong { color: hsl(160, 45%, 60%); font-weight: 500; }

            /* Real-vs-apparent split. Same trick as the draw bar: the useful
               range is nowhere near the plug's rating, so scale to apparent. */
            .pw-pf-bar {
              position: relative; height: 5px; border-radius: 3px;
              background: hsla(160, 45%, 55%, 0.16); overflow: hidden;
            }
            .pw-pf-fill {
              position: absolute; top: 0; bottom: 0; left: 0; border-radius: 3px;
              background: linear-gradient(90deg, hsl(160, 50%, 42%), hsl(160, 72%, 58%));
            }
            .pw-legend {
              display: flex; gap: 16px; flex-wrap: wrap;
              font-size: var(--font-size-h6); color: var(--color-text-subdue);
            }
            .pw-legend span::before {
              content: ""; display: inline-block;
              width: 8px; height: 8px; border-radius: 2px; margin-right: 6px;
            }
            .pw-legend .pw-lg-real::before { background: hsl(160, 68%, 55%); }
            .pw-legend .pw-lg-reactive::before { background: hsla(160, 55%, 58%, 0.55); }

            /* Caveat — stops a session counter from reading as a lifetime total */
            .pw-caveat {
              font-size: var(--font-size-h6); color: var(--color-text-subdue);
              border-left: 2px solid hsla(160, 70%, 55%, 0.35);
              padding-left: 10px; line-height: 1.6;
            }

            /* ── Subtle divider between widget sections ── */
            /* Direct children only — inside a group widget the tabs are also
               .widget elements, and the descendant selector drew a rule between
               tab panes. */
            .column-full > .widget + .widget {
              border-top: 1px solid hsla(160, 30%, 50%, 0.08);
              padding-top: 4px;
            }

            /* ── Page header ── */
            .page-navigation-item.page-navigation-item-current {
              text-shadow: 0 0 10px hsla(160, 60%, 50%, 0.4);
            }

            /* ── Clock styling ── */
            .widget-type-clock .clock-time {
              text-shadow: 0 0 12px hsla(160, 50%, 50%, 0.25);
            }

            /* ── Network panel (live throughput + speed test) ── */
            .np { display: flex; flex-direction: column; gap: 14px; }
            .np-row { display: flex; gap: 32px; flex-wrap: wrap; }
            .np-cell { flex: 1 1 200px; min-width: 170px; }
            .np-head { display: flex; align-items: baseline; gap: 7px; }
            .np-arrow { font-size: 1.05em; line-height: 1; }
            .np-num {
              font-size: var(--font-size-h2);
              font-weight: 500;
              color: var(--color-text-highlight);
              font-variant-numeric: tabular-nums;
            }
            .np-unit { font-size: var(--font-size-h5); color: var(--color-text-subdue); }
            .np-foot {
              font-size: var(--font-size-h6);
              color: var(--color-text-subdue);
              font-variant-numeric: tabular-nums;
            }
            .np-down { color: var(--color-positive); }
            .np-up { color: hsl(200, 68%, 58%); }

            /* viewBox is stretched to the cell width, so the stroke has to opt
               out of scaling or it goes lumpy on a wide column. */
            .np-spark {
              display: block;
              width: 100%;
              height: 34px;
              margin: 7px 0 5px;
              overflow: visible;
            }
            .np-spark .np-line {
              fill: none;
              stroke: currentColor;
              stroke-width: 1.4;
              stroke-linejoin: round;
              vector-effect: non-scaling-stroke;
            }
            .np-spark .np-fill { fill: currentColor; opacity: 0.13; stroke: none; }

            .np-meta {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 14px;
              flex-wrap: wrap;
              border-top: 1px solid var(--color-separator);
              padding-top: 11px;
              font-size: var(--font-size-h6);
              color: var(--color-text-subdue);
            }
            .np-btn {
              font: inherit;
              font-size: var(--font-size-h6);
              letter-spacing: 0.06em;
              text-transform: uppercase;
              color: var(--color-text-base);
              background: hsla(160, 40%, 40%, 0.10);
              border: 1px solid hsla(160, 40%, 45%, 0.30);
              border-radius: 7px;
              padding: 5px 13px;
              cursor: pointer;
              transition: background-color 0.2s ease, border-color 0.2s ease;
            }
            .np-btn:hover:not(:disabled) {
              background: hsla(160, 45%, 45%, 0.20);
              border-color: hsla(160, 50%, 50%, 0.50);
            }
            .np-btn:disabled { opacity: 0.5; cursor: default; }
          </style>

          <script>
            // Glance 0.8.5 renders every widget server-side exactly once per page
            // load — page.js calls fetchPageContent() a single time from
            // setupPage() and there is no client-side widget refresh to hook. So
            // the live half of the Network panel is driven from here instead.
            //
            // This has to live in document.head: widget markup is injected with
            // `pageContentElement.innerHTML = ...`, and innerHTML does not execute
            // <script> tags, so the same code inside a custom-api template would
            // never run. Inline handlers would survive, but listeners are attached
            // here to keep Go's template escaping out of the picture entirely.
            //
            // Reads network-panel.py on :9555, which is CORS-open and reachable
            // over the tailnet. Derived from location.hostname on purpose, so this
            // keeps working when the dashboard is opened by IP rather than by name.
            (function () {
              var API = location.protocol + "//" + location.hostname + ":9555";
              var POLL_MS = 2000;
              var started = false;

              function fmt(v) {
                if (typeof v !== "number" || !isFinite(v)) return "--";
                return v >= 100 ? v.toFixed(0) : v.toFixed(1);
              }

              function text(id, value) {
                var el = document.getElementById(id);
                if (el) el.textContent = value;
              }

              // Relative time, recomputed client-side so the "last run" stamp does
              // not go stale on a dashboard that stays open for days.
              function ago(iso) {
                var t = Date.parse(iso);
                if (isNaN(t)) return "never";
                var s = Math.max(0, (Date.now() - t) / 1000);
                if (s < 90) return "just now";
                if (s < 5400) return Math.round(s / 60) + "m ago";
                if (s < 172800) return Math.round(s / 3600) + "h ago";
                return Math.round(s / 86400) + "d ago";
              }

              function spark(id, values) {
                var svg = document.getElementById(id);
                if (!svg || !values || values.length < 2) return;

                var w = 240, h = 34, pad = 2, n = values.length, max = 0;
                for (var i = 0; i < n; i++) if (values[i] > max) max = values[i];
                // Each direction auto-scales to its own peak. A shared scale is
                // more honest but pins the upload trace flat to the floor on an
                // asymmetric line, which reads as "nothing is happening".
                if (max <= 0) max = 1;

                var pts = [];
                for (var j = 0; j < n; j++) {
                  var x = (j / (n - 1)) * w;
                  var y = h - pad - (values[j] / max) * (h - pad * 2);
                  pts.push(x.toFixed(1) + "," + y.toFixed(1));
                }

                var line = "M" + pts.join(" L");
                svg.querySelector(".np-line").setAttribute("d", line);
                svg.querySelector(".np-fill").setAttribute(
                  "d", line + " L" + w + "," + h + " L0," + h + " Z");
              }

              function render(data) {
                var live = data.live || {};
                text("np-down", fmt(live.down));
                text("np-up", fmt(live.up));
                text("np-peak-down", fmt(live.peak_down));
                text("np-peak-up", fmt(live.peak_up));
                spark("np-spark-down", live.hist_down);
                spark("np-spark-up", live.hist_up);

                var st = data.speedtest || {};
                if (st.ok) {
                  text("np-st-down", fmt(st.down));
                  text("np-st-up", fmt(st.up));
                  text("np-st-ping", fmt(st.ping));
                  text("np-st-jitter", fmt(st.jitter));
                  // The separator lives with the value, so "never run" does not
                // render a dangling bullet.
                text("np-st-server", st.server ? "· " + st.server : "");
                  text("np-st-when", ago(st.timestamp));
                }

                var btn = document.getElementById("np-run");
                if (btn) {
                  btn.disabled = !!data.running;
                  btn.textContent = data.running ? "Running" : "Run now";
                }
              }

              function tick() {
                // Nothing to update behind a hidden tab, and the browser throttles
                // these to a crawl anyway.
                if (document.hidden) return;
                fetch(API + "/api", { cache: "no-store" })
                  .then(function (r) { return r.json(); })
                  .then(render)
                  .catch(function () { /* next tick will retry */ });
              }

              function attach() {
                var btn = document.getElementById("np-run");
                if (!btn) return;
                btn.addEventListener("click", function () {
                  btn.disabled = true;
                  btn.textContent = "Running";
                  fetch(API + "/run", { method: "POST", headers: { "X-Dash": "1" } })
                    .then(tick)
                    .catch(function () { btn.textContent = "Failed"; });
                });
              }

              function boot() {
                if (started || !document.getElementById("np-down")) return false;
                started = true;
                attach();
                tick();
                setInterval(tick, POLL_MS);
                document.addEventListener("visibilitychange", function () {
                  if (!document.hidden) tick();
                });
                return true;
              }

              // Widget markup lands asynchronously, well after DOMContentLoaded.
              document.addEventListener("DOMContentLoaded", function () {
                if (boot()) return;
                var obs = new MutationObserver(function () {
                  if (boot()) obs.disconnect();
                });
                obs.observe(document.body, { childList: true, subtree: true });
              });
            })();
          </script>

          <script>
            // Switch toggles on the Monitoring page.
            //
            // Same constraint as the network panel above: widget markup is
            // injected with innerHTML, which does not execute <script>, so this
            // has to live in document.head. Event delegation on `document`
            // means it does not care when the widget markup arrives — no
            // MutationObserver, no boot race.
            //
            // Talks to ha-bridge on :9556 (Modules/Server/home-assistant.nix), which
            // holds the HA token server-side. Note the button's `disabled`
            // attribute is cosmetic: the bridge's ALLOWED set is what actually
            // makes Asgard's and Eclipse's relays unreachable.
            (function () {
              var API = location.protocol + "//" + location.hostname + ":9556";

              function paint(entity, state) {
                var pills = document.querySelectorAll('[data-ha-pill="' + entity + '"]');
                for (var i = 0; i < pills.length; i++) {
                  pills[i].textContent = state;
                  pills[i].className = "pw-pill " + (state === "on" ? "pw-on" : "pw-off");
                }
              }

              // Toggling the group changes its members too, so repaint from the
              // bridge rather than trusting the single entity that was clicked.
              function refreshAll() {
                fetch(API + "/states", { cache: "no-store" })
                  .then(function (r) { return r.json(); })
                  .then(function (m) {
                    Object.keys(m).forEach(function (k) { paint(k, m[k]); });
                  })
                  .catch(function () { /* leave the optimistic paint in place */ });
              }

              document.addEventListener("click", function (e) {
                if (!e.target.closest) return;
                var btn = e.target.closest(".pw-toggle[data-entity]");
                if (!btn || btn.disabled) return;

                // These buttons sit inside <summary>. Without this, the click
                // would also expand/collapse the card underneath them.
                e.preventDefault();
                e.stopPropagation();

                var entity = btn.getAttribute("data-entity");
                var label = btn.textContent;
                btn.disabled = true;
                btn.textContent = "···";

                fetch(API + "/toggle/" + encodeURIComponent(entity), { method: "POST", headers: { "X-Dash": "1" } })
                  .then(function (r) { return r.json(); })
                  .then(function (d) {
                    btn.disabled = false;
                    btn.textContent = label;
                    if (d && d.state) { paint(entity, d.state); refreshAll(); }
                    else { btn.textContent = "failed"; }
                  })
                  .catch(function () {
                    btn.disabled = false;
                    btn.textContent = "failed";
                  });
              });

              // Keep the pills honest without a reload. This used to repaint ONLY
              // after a click here, so a light toggled from the marsbar dashboard,
              // the HA app, an automation or a physical switch left this page
              // showing a stale state indefinitely.
              document.addEventListener("DOMContentLoaded", function () {
                refreshAll();
                setInterval(refreshAll, 3000);
              });
            })();
          </script>

      theme:
        # Mint-green primary — the "mission control" homelab look, and the one
        # this dashboard has always had. An orange experiment was tried and
        # rejected. Colour variety now comes from the ambient orbs and the
        # secondary accents in the CSS rather than from repainting everything.
        positive-color: hsl(152, 62%, 52%)
        negative-color: hsl(0, 84%, 60%)

      pages:
        # ════════════════════════════════════════════════════════════════════
        # PAGE 1 — Asgard (host stats, network, service health)
        #
        # There is deliberately NO bookmarks column. Every link it carried was
        # also a monitor row below, and monitor rows are already clickable — the
        # page was listing the same thirteen services twice, which was most of
        # why it scrolled. Add new services to the monitors, not to a sidebar.
        # ════════════════════════════════════════════════════════════════════
        - name: Asgard
          columns:
            - size: full
              widgets:
                - type: server-stats
                  servers:
                    - type: local
                      name: Asgard
                      hide-mountpoints-by-default: true
                      mountpoints:
                        "/data/media":
                          name: Media Pool
                          hide: false

                # No storage widget here — the server-stats widget above already
                # reports the pool as its DISK bar (mountpoint /data/media, named
                # "Media Pool"), so a second readout only duplicated it.
                #
                # Removing it also took out a browser-side poller, and with it a
                # class of silent breakage: that script fetched localhost:<port>,
                # which in a browser means the *viewer's* machine, not Asgard — so
                # it had never once updated except when viewed from the server
                # itself. Any browser-side fetch added here must use asgard:<port>
                # (or location.hostname); the network panel below does exactly that.

                # ── Network ────────────────────────────────────────────────
                # A group so the live readout and the speed test share one
                # widget slot instead of stacking. Both tabs render from the
                # same /api call on network-panel.py (:9555) — over localhost,
                # because Glance fetches server-side.
                #
                # Glance renders a widget once per page load and never again, so
                # everything below is only the FIRST frame: the poller in
                # document.head takes over by id and keeps it moving. That is
                # also why the ids matter — don't rename one without editing the
                # script. This replaced a `flow` TUI in a read-only ttyd, which
                # spent most of its life showing xterm.js's reconnect banner.
                - type: group
                  widgets:
                    - type: custom-api
                      title: Network
                      cache: 5s
                      url: http://localhost:9555/api
                      template: |
                        <div class="np">
                          <div class="np-row">
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-arrow np-down">↓</span>
                                <span class="np-num" id="np-down">{{ printf "%.1f" (.JSON.Float "live.down") }}</span>
                                <span class="np-unit">Mb/s</span>
                              </div>
                              <svg class="np-spark np-down" id="np-spark-down" viewBox="0 0 240 34" preserveAspectRatio="none">
                                <path class="np-fill" d=""></path>
                                <path class="np-line" d=""></path>
                              </svg>
                              <div class="np-foot">
                                download · peak
                                <span id="np-peak-down">{{ printf "%.1f" (.JSON.Float "live.peak_down") }}</span>
                                over {{ .JSON.Int "live.window" }}s
                              </div>
                            </div>
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-arrow np-up">↑</span>
                                <span class="np-num" id="np-up">{{ printf "%.1f" (.JSON.Float "live.up") }}</span>
                                <span class="np-unit">Mb/s</span>
                              </div>
                              <svg class="np-spark np-up" id="np-spark-up" viewBox="0 0 240 34" preserveAspectRatio="none">
                                <path class="np-fill" d=""></path>
                                <path class="np-line" d=""></path>
                              </svg>
                              <div class="np-foot">
                                upload · peak
                                <span id="np-peak-up">{{ printf "%.1f" (.JSON.Float "live.peak_up") }}</span>
                                over {{ .JSON.Int "live.window" }}s
                              </div>
                            </div>
                          </div>
                          <div class="np-meta">
                            <span>{{ .JSON.String "live.iface" }} · sampled every second · each trace scaled to its own peak</span>
                          </div>
                        </div>

                    # Upload reads ~30 Mb/s on a 50 Mb/s uplink and that is
                    # correct: wan-egress-shaping puts every WAN-bound packet in
                    # a 30 Mbit htb class. The footnote says so, because this
                    # otherwise looks exactly like a broken uplink.
                    - type: custom-api
                      title: Speed test
                      cache: 30s
                      url: http://localhost:9555/api
                      template: |
                        {{ $ok := .JSON.Bool "speedtest.ok" }}
                        <div class="np">
                          <div class="np-row">
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-arrow np-down">↓</span>
                                <span class="np-num" id="np-st-down">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.down") }}{{ else }}--{{ end }}</span>
                                <span class="np-unit">Mb/s</span>
                              </div>
                              <div class="np-foot">download</div>
                            </div>
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-arrow np-up">↑</span>
                                <span class="np-num" id="np-st-up">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.up") }}{{ else }}--{{ end }}</span>
                                <span class="np-unit">Mb/s</span>
                              </div>
                              <div class="np-foot">upload · shaped to 30</div>
                            </div>
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-num" id="np-st-ping">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.ping") }}{{ else }}--{{ end }}</span>
                                <span class="np-unit">ms</span>
                              </div>
                              <div class="np-foot">
                                ping ·
                                <span id="np-st-jitter">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.jitter") }}{{ else }}--{{ end }}</span>
                                ms jitter
                              </div>
                            </div>
                          </div>
                          <div class="np-meta">
                            <span>
                              Ookla, every 6h ·
                              <span id="np-st-when">{{ if $ok }}…{{ else }}never run{{ end }}</span>
                              <span id="np-st-server">{{ if $ok }}· {{ .JSON.String "speedtest.server" }}{{ end }}</span>
                            </span>
                            <button class="np-btn" id="np-run" type="button">Run now</button>
                          </div>
                        </div>

                # ── Service health ─────────────────────────────────────────
                # One group rather than four stacked monitors. "All" is the
                # default tab because that is the question this page exists to
                # answer; the category tabs are for when something is red and
                # you want it isolated. The duplicated checks cost nothing —
                # they are local HTTP GETs on a 1m cache.
                - type: group
                  widgets:
                    - type: monitor
                      title: All
                      cache: 1m
                      sites:
                        - title: Jellyfin
                          url: http://asgard:8096
                          icon: sh:jellyfin
                        - title: Jellyseerr
                          url: http://asgard:5055
                          icon: sh:jellyseerr
                        - title: Immich
                          url: http://asgard:2283
                          icon: sh:immich
                        - title: Audiobookshelf
                          url: http://asgard:13378
                          icon: sh:audiobookshelf
                        - title: SABnzbd
                          url: http://asgard:8080
                          icon: sh:sabnzbd
                        - title: Prowlarr
                          url: http://asgard:9696
                          icon: sh:prowlarr
                        - title: Sonarr
                          url: http://asgard:8989
                          icon: sh:sonarr
                        - title: Radarr
                          url: http://asgard:7878
                          icon: sh:radarr
                        - title: Lidarr
                          url: http://asgard:8686
                          icon: sh:lidarr
                        - title: Shelfarr
                          url: http://asgard:5056
                          icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/shelfarr.svg
                        - title: Suwayomi
                          url: http://asgard:4567
                          icon: sh:suwayomi
                        - title: FileBrowser
                          url: http://asgard:8081
                          icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/filebrowser.svg
                        - title: Home Assistant
                          url: http://asgard:8123
                          icon: sh:home-assistant

                    - type: monitor
                      title: Media
                      cache: 1m
                      sites:
                        - title: Jellyfin
                          url: http://asgard:8096
                          icon: sh:jellyfin
                        - title: Jellyseerr
                          url: http://asgard:5055
                          icon: sh:jellyseerr
                        - title: Immich
                          url: http://asgard:2283
                          icon: sh:immich
                        - title: Audiobookshelf
                          url: http://asgard:13378
                          icon: sh:audiobookshelf
                        - title: Suwayomi
                          url: http://asgard:4567
                          icon: sh:suwayomi

                    - type: monitor
                      title: Downloads
                      cache: 1m
                      sites:
                        - title: SABnzbd
                          url: http://asgard:8080
                          icon: sh:sabnzbd
                        - title: Prowlarr
                          url: http://asgard:9696
                          icon: sh:prowlarr

                    - type: monitor
                      title: Arr
                      cache: 1m
                      sites:
                        - title: Sonarr
                          url: http://asgard:8989
                          icon: sh:sonarr
                        - title: Radarr
                          url: http://asgard:7878
                          icon: sh:radarr
                        - title: Lidarr
                          url: http://asgard:8686
                          icon: sh:lidarr
                        - title: Shelfarr
                          url: http://asgard:5056
                          icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/shelfarr.svg

                    - type: monitor
                      title: Management
                      cache: 1m
                      sites:
                        - title: FileBrowser
                          url: http://asgard:8081
                          icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/filebrowser.svg
                        - title: Home Assistant
                          url: http://asgard:8123
                          icon: sh:home-assistant

            - size: small
              widgets:
                - type: clock
                  hour-format: 12h

                - type: custom-api
                  title: Yggdrasil Network
                  css-class: ygg-widget
                  cache: 15s
                  url: http://localhost:9553/status
                  template: |
                    <style>
                      .ts-online {
                        width: 8px;
                        height: 8px;
                        border-radius: 50%;
                        background-color: hsl(142, 72%, 39%);
                        display: inline-block;
                        margin-left: 4px;
                        vertical-align: middle;
                      }
                      .ts-offline {
                        width: 8px;
                        height: 8px;
                        border-radius: 50%;
                        background-color: var(--color-negative);
                        display: inline-block;
                        margin-left: 4px;
                        vertical-align: middle;
                      }
                    </style>
                    <ul class="list list-gap-10 collapsible-container" data-collapse-after="10">
                      <li>
                        <div class="flex items-center gap-10">
                          <div class="grow flex items-center gap-8">
                            <span class="size-h4 block text-truncate color-primary">{{ .JSON.String "self.name" }}</span>
                            <span class="ts-online"></span>
                          </div>
                          <span class="size-h5 color-subtext">{{ .JSON.String "self.ip" }}</span>
                        </div>
                      </li>
                      {{ range .JSON.Array "peers" }}
                      <li>
                        <div class="flex items-center gap-10">
                          <div class="grow flex items-center gap-8">
                            <span class="size-h4 block text-truncate color-primary">{{ .String "name" }}</span>
                            {{ if .Bool "online" }}
                              <span class="ts-online" data-popover-type="text" data-popover-text="Online"></span>
                            {{ else }}
                              <span class="ts-offline" data-popover-type="text" data-popover-text="Offline"></span>
                            {{ end }}
                          </div>
                          <span class="size-h5 color-subtext">{{ .String "ip" }}</span>
                        </div>
                      </li>
                      {{ end }}
                    </ul>

        # ════════════════════════════════════════════════════════════════════
        # PAGE 2 — Downloads (SABnzbd iframe + queue stats)
        # ════════════════════════════════════════════════════════════════════
        - name: Downloads
          columns:
            - size: small
              widgets:
                # Both read SABnzbd's own queue API. They used to query
                # Prometheus for sabnzbd_queue_* from an exporter container;
                # that metrics stack is gone, and SAB serves the same two
                # numbers itself. localhost:8080 is the socat proxy into the
                # Mullvad namespace — the same path speedtest.service uses.
                #
                # The apikey is substituted by Glance at load time from a
                # systemd credential (readFileFromEnv), never written here —
                # see systemd.services.glance. `mbleft` is a JSON *string*;
                # .Float parses it.
                - type: custom-api
                  title: Queue
                  cache: 15s
                  url: http://localhost:8080/api
                  parameters:
                    mode: queue
                    output: json
                    apikey: "''${readFileFromEnv:SABNZBD_API_KEY_FILE}"
                  template: |
                    <p class="size-h1">{{ .JSON.Int "queue.noofslots_total" }} <span class="size-h4 color-subtext">items</span></p>

                - type: custom-api
                  title: Remaining
                  cache: 15s
                  url: http://localhost:8080/api
                  parameters:
                    mode: queue
                    output: json
                    apikey: "''${readFileFromEnv:SABNZBD_API_KEY_FILE}"
                  template: |
                    <p class="size-h1 color-primary">{{ printf "%.2f" (div (.JSON.Float "queue.mbleft") 1024.0) }} <span class="size-h4 color-subtext">GB</span></p>

                - type: monitor
                  title: Status
                  cache: 1m
                  sites:
                    - title: SABnzbd
                      url: http://asgard:8080
                      icon: sh:sabnzbd
                    - title: Prowlarr
                      url: http://asgard:9696
                      icon: sh:prowlarr

            - size: full
              widgets:
                - type: iframe
                  title: SABnzbd
                  source: http://asgard:8080
                  height: 700

        # ════════════════════════════════════════════════════════════════════
        # PAGE 3 — Terminal (ttyd web console — login as rock, sudo works)
        # ════════════════════════════════════════════════════════════════════
        - name: Terminal
          columns:
            - size: full
              widgets:
                - type: iframe
                  title: Asgard Terminal
                  source: http://asgard:7681
                  height: 700

        # ════════════════════════════════════════════════════════════════════
        # PAGE 4 — Eclipse (TV box: fix-it buttons + live status)
        # Panel served by the eclipse-control service (port 9554), which drives
        # the LibreELEC box over SSH. iframe because Glance's html widget
        # sanitises everything — see Claude/eclipse.md.
        # ════════════════════════════════════════════════════════════════════
        - name: Eclipse
          columns:
            - size: full
              widgets:
                - type: iframe
                  title: Eclipse Control
                  source: http://asgard:9554
                  height: 700

        # ════════════════════════════════════════════════════════════════════
        # PAGE 5 — Monitoring (Home Assistant power draw, Asgard's own plug)
        #
        # Reads Home Assistant's REST API directly over localhost — both HA
        # and Glance run natively on Asgard, so no proxy service needed.
        # Auth via a long-lived access token: HA tokens can't be minted
        # declaratively (they require an existing logged-in session), so this
        # one was created by hand in the HA UI and stored in sops as
        # `ha-token`. Glance substitutes it (its readFileFromEnv variable,
        # HA_TOKEN_FILE) when it loads this config — once, at startup; the sops
        # secret restarts glance.service when it changes — from a systemd
        # credential, exactly like the SABnzbd key, so the token never touches
        # the Nix store. See systemd.services.glance below. (Not spelled out
        # with its dollar-brace here: Glance expands those even in comments.)
        #
        # Entities come from the Athom Plug V3 (ESPHome) feeding Asgard's PSU,
        # named "Server-power" in HA. It exposes far more than draw:
        #   sensor.server_power_power               — real power, W
        #   sensor.server_power_voltage / _current  — V / A
        #   sensor.server_power_apparent_power      — VA
        #   sensor.server_power_power_factor        — real ÷ apparent
        #   sensor.server_power_total_daily_energy  — kWh, resets at midnight
        #   sensor.server_power_total_energy        — kWh since the plug booted
        #   sensor.server_power_uptime_sensor       — plug boot timestamp
        #   sensor.server_power_wifi_signal_db      — dBm
        #   switch.server_power_switch              — THE RELAY, see below
        #
        # ⚠ NEVER derive the daily average from `total_energy / uptime_sensor`.
        # That was the original approach and it breaks hard: the two counters do
        # NOT reset together. Rebooting Asgard on 2026-09-19 reset the uptime
        # while the energy counter kept accumulating, so the maths divided days
        # of kWh by 5 hours — 2.165 kWh / 5.5 h * 24 = 9.45 kWh/day, and a box
        # actually drawing 35.5 W (~$95/yr) was projected at $1047/yr. The error
        # is silent and plausible-looking, which is the dangerous part.
        #
        # `total_daily_energy` is NOT a safe substitute either — that was tried
        # next and also wrong. It resets on device restart as well as at midnight,
        # so after the same reboot it held 5.5 h of energy while hours-since-
        # midnight said 22 h, under-reporting Asgard at $43/yr against a true
        # ~$149/yr. Both cumulative counters reset on restart; anything derived
        # from one divided by a clock will silently break the next time the plug
        # blips.
        #
        # The projections therefore come from INSTANTANEOUS power (W * 0.024 =
        # kWh/day). It is a snapshot rather than a measured average, so it moves
        # with load — but it is always internally consistent and cannot lie by an
        # order of magnitude. Label these "at current draw", not "average".
        # A real average would need HA's long-term statistics API, which is out
        # of reach from a Jinja template.
        #
        # ⚠ `total_energy` is NOT a lifetime total, despite the entity name.
        # The ESPHome counter restarts whenever the plug power-cycles. Checked
        # 2026-09-17: the plug's boot timestamp matched Asgard's `uptime` to the
        # minute, i.e. that plug restart hard-cut the server. It is labelled
        # "since plug boot" with a relative stamp for that reason — the old
        # "LIFETIME USAGE" label made a 75-minute sample read as months of data.
        #
        # ⚠ switch.server_power_switch is Asgard's mains feed. Toggling it cuts
        # the server mid-write. It is rendered as a READ-ONLY pill deliberately:
        # a dashboard is the wrong place for a one-click power cut. Leave it
        # read-only unless you actually want a remote kill switch.
        #
        # Widgets render server-side once per page load — Glance 0.8.5 has no
        # client-side widget refresh, so `cache:` only affects the NEXT load.
        # Reload to update. Relative timestamps are the exception; page.js ticks
        # those client-side.
        # ════════════════════════════════════════════════════════════════════
        - name: Monitoring
          # Without this the page stretches the full 2560px of an ultrawide and
          # a single device card becomes a metre-wide band. `slim` is a Glance
          # page option (wide|slim) and caps the content column; it allows at
          # most 2 columns per page.
          width: slim
          columns:
            - size: full
              widgets:
                # ── Machines whose relay must never be flipped ──────────────
                # Asgard and Eclipse: monitored in full, rendered locked. Both
                # are running computers — cutting mains means an unclean stop.
                # The lock that matters is ALLOWED in Modules/Server/home-assistant.nix;
                # the disabled button here is only the visible half.
                #
                # Everything comes from one POST to HA's /api/template, which
                # renders Jinja server-side and returns JSON. Beats a stack of
                # /api/states subrequests: the arithmetic (elapsed hours, true
                # averages, costs) happens in Jinja where it is readable, and
                # the whole widget is a single round trip.
                #
                # ⚠ The body MUST use a literal block scalar (|-). A folded one
                # (>-) joins the {% set %} lines and HA answers 400.
                - type: custom-api
                  title: Power Monitoring
                  cache: 30s
                  url: http://localhost:8123/api/template
                  method: POST
                  body-type: json
                  headers:
                    Authorization: Bearer ''${readFileFromEnv:HA_TOKEN_FILE}
                  body:
                    template: |-
                      {% set r = ${toString powerRate} %}
                      {% set devs = [
                        ('Asgard', 'server_power', 'switch.server_power_switch', 'Server · Athom Plug V3'),
                        ('Eclipse', 'eclipse', 'switch.eclipse_switch', 'Pi 5 TV box · Athom Plug V3')] %}
                      {% set ns = namespace(rows=[], total=0) %}
                      {% for label, slug, ent, sub in devs %}
                      {% set p = states('sensor.' ~ slug ~ '_power')|float(0) %}
                      {% set tot = states('sensor.' ~ slug ~ '_total_energy')|float(0) %}
                      {% set today = states('sensor.' ~ slug ~ '_total_daily_energy')|float(0) %}
                      {% set up = states('sensor.' ~ slug ~ '_uptime_sensor') %}
                      {% set upd = as_datetime(up) %}
                      {% set hrs = ((now() - upd).total_seconds() / 3600) if upd else 0 %}
                      {% set avg = p * 0.024 %}
                      {% set ns.total = ns.total + p %}
                      {% set ns.rows = ns.rows + ['{"name": "' ~ label ~ '", "sub": "' ~ sub ~ '", "entity": "' ~ ent ~ '", "state": "' ~ states(ent) ~ '", "power": ' ~ (p|round(1)) ~ ', "voltage": ' ~ (states('sensor.' ~ slug ~ '_voltage')|float(0)|round(1)) ~ ', "current": ' ~ (states('sensor.' ~ slug ~ '_current')|float(0)|round(3)) ~ ', "apparent": ' ~ (states('sensor.' ~ slug ~ '_apparent_power')|float(0)|round(1)) ~ ', "pf": ' ~ (states('sensor.' ~ slug ~ '_power_factor')|float(0)|round(2)) ~ ', "pf_pct": ' ~ (states('sensor.' ~ slug ~ '_power_factor')|float(0)*100)|round(0) ~ ', "today_kwh": ' ~ (today|round(3)) ~ ', "today_cost": ' ~ ((today * r)|round(2)) ~ ', "total_kwh": ' ~ (tot|round(3)) ~ ', "total_cost": ' ~ ((tot * r)|round(2)) ~ ', "avg_kwh": ' ~ (avg|round(3)) ~ ', "year_cost": ' ~ ((avg * r * 365)|round(0)) ~ ', "hours": ' ~ (hrs|round(1)) ~ ', "onstate": "' ~ states('select.' ~ slug ~ '_power_on_state') ~ '", "uptime": "' ~ up ~ '"}'] %}
                      {% endfor %}
                      {"total": {{ ns.total|round(1) }}, "rate": {{ r }}, "items": [{{ ns.rows|join(',') }}]}
                  template: |
                    {{ $pct := mul (div (.JSON.Float "total") ${toString powerRefW}) 100.0 }}
                    <div class="pw">
                      <div class="pw-hero">
                        <div><span class="pw-big">{{ printf "%.1f" (.JSON.Float "total") }}</span><span class="pw-big-unit">W</span></div>
                        <div class="pw-trail">
                          combined draw, {{ len (.JSON.Array "items") }} machines<br>
                          {{ printf "$%.4f" (.JSON.Float "rate") }}/kWh balance rate
                        </div>
                      </div>
                      <div class="pw-bar">
                        <div class="pw-bar-fill" style="width: {{ if gt $pct 100.0 }}100{{ else }}{{ printf "%.1f" $pct }}{{ end }}%"></div>
                      </div>
                      <div class="pw-scale">
                        <span>0 W</span>
                        <span>{{ printf "%.0f" ${toString powerRefW} }} W ref</span>
                      </div>

                      <div class="pw-cards">
                        {{ range .JSON.Array "items" }}
                        <details class="pw-card">
                          <summary class="pw-card-head">
                            <span class="pw-card-top">
                              <span class="pw-chev"></span>
                              <span class="pw-card-name">{{ .String "name" }}</span>
                              <span class="pw-pill {{ if eq (.String "state") "on" }}pw-on{{ else }}pw-off{{ end }}" data-ha-pill="{{ .String "entity" }}">{{ .String "state" }}</span>
                            </span>
                            <span class="pw-card-sub">{{ .String "sub" }}</span>
                            <span class="pw-card-stats">
                              <span class="pw-mini"><span class="pw-k">Now</span><span class="pw-v">{{ printf "%.1f" (.Float "power") }} <span class="pw-v-sub">W</span></span></span>
                              <span class="pw-mini"><span class="pw-k">Avg Daily</span><span class="pw-v">{{ printf "%.2f" (.Float "avg_kwh") }} <span class="pw-v-sub">kWh</span></span></span>
                              <span class="pw-mini"><span class="pw-k">Cost / Year</span><span class="pw-v">{{ printf "$%.0f" (.Float "year_cost") }}</span></span>
                            </span>
                          </summary>

                          <div class="pw-card-body">
                            <div>
                              <div class="pw-sec-title">Electrical</div>
                              <div class="pw-grid pw-grid-bare">
                                <div class="pw-cell"><div class="pw-k">Voltage</div><div class="pw-v">{{ printf "%.1f" (.Float "voltage") }} <span class="pw-v-sub">V</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Current</div><div class="pw-v">{{ printf "%.3f" (.Float "current") }} <span class="pw-v-sub">A</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Apparent</div><div class="pw-v">{{ printf "%.1f" (.Float "apparent") }} <span class="pw-v-sub">VA</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Power Factor</div><div class="pw-v">{{ printf "%.2f" (.Float "pf") }}</div></div>
                              </div>
                            </div>

                            {{ if gt (.Float "apparent") 0.0 }}
                            <div>
                              <div class="pw-sec-title">Real vs Apparent</div>
                              <div class="pw-pf-bar">
                                <div class="pw-pf-fill" style="width: {{ printf "%.0f" (.Float "pf_pct") }}%"></div>
                              </div>
                              <div class="pw-legend" style="margin-top: 8px;">
                                <span class="pw-lg-real">{{ printf "%.1f" (.Float "power") }} W real</span>
                                <span class="pw-lg-reactive">{{ printf "%.1f" (.Float "apparent") }} VA drawn</span>
                              </div>
                            </div>
                            {{ end }}

                            <div>
                              <div class="pw-sec-title">Energy</div>
                              <div class="pw-grid pw-grid-bare">
                                <div class="pw-cell"><div class="pw-k">Used Today</div><div class="pw-v">{{ printf "%.3f" (.Float "today_kwh") }} <span class="pw-v-sub">kWh</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Cost Today</div><div class="pw-v">{{ printf "$%.2f" (.Float "today_cost") }}</div></div>
                                <div class="pw-cell"><div class="pw-k">Avg Daily</div><div class="pw-v">{{ printf "%.2f" (.Float "avg_kwh") }} <span class="pw-v-sub">kWh</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Overall</div><div class="pw-v">{{ printf "%.3f" (.Float "total_kwh") }} <span class="pw-v-sub">kWh</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Counting Since</div><div class="pw-v" style="font-size: var(--font-size-h5);"><span {{ .String "uptime" | parseTime "rfc3339" | toRelativeTime }}></span></div></div>
                                <div class="pw-cell"><div class="pw-k">On Power Loss</div><div class="pw-v" style="font-size: var(--font-size-h5);">{{ .String "onstate" }}</div></div>
                              </div>
                            </div>

                            <div class="pw-actions">
                              <button class="pw-toggle" disabled title="Locked in the bridge allowlist, not just here">Toggle — locked</button>
                              <span class="pw-action-note">
                                Running machine. The bridge refuses this entity outright, so a
                                stray request cannot cut it mid-write either.
                              </span>
                            </div>

                            <div class="pw-caveat">
                              "Overall" is not a lifetime total — the plug's counter restarts on
                              every power-cycle, so it measures the {{ printf "%.1f" (.Float "hours") }}h
                              since "Counting Since". "Avg Daily" is derived from that window and
                              firms up as it runs.
                            </div>
                          </div>
                        </details>
                        {{ end }}
                      </div>
                    </div>

                # ── Power switches ─────────────────────────────────────────
                # The three lamp plugs, individually and as one group. The group
                # is switch.living_room_lights, a `group` platform switch defined
                # in Modules/Server/home-assistant.nix — a real entity, so it works from
                # the HA app and automations too, not just this page.
                #
                # Buttons POST to ha-bridge on :9556; the head script wires them
                # by delegation and repaints every pill afterwards, because a
                # group toggle moves its members too.
                - type: custom-api
                  title: Power Switches
                  cache: 30s
                  url: http://localhost:8123/api/template
                  method: POST
                  body-type: json
                  headers:
                    Authorization: Bearer ''${readFileFromEnv:HA_TOKEN_FILE}
                  body:
                    template: |-
                      {% set r = ${toString powerRate} %}
                      {% set devs = [
                        ('Lounge Lamp', 'lounge_room_lamp', 'switch.lounge_room_lamp_switch', 'Standard lamp'),
                        ('Colour Lamp', 'colour_lamp', 'switch.colour_lamp_switch', 'Colour lamp'),
                        ('Christmas Lights', 'christmas_lights', 'switch.christmas_lights_switch', 'Fairy lights')] %}
                      {% set ns = namespace(rows=[], total=0, on=0) %}
                      {% for label, slug, ent, sub in devs %}
                      {% set p = states('sensor.' ~ slug ~ '_power')|float(0) %}
                      {% set tot = states('sensor.' ~ slug ~ '_total_energy')|float(0) %}
                      {% set today = states('sensor.' ~ slug ~ '_total_daily_energy')|float(0) %}
                      {% set up = states('sensor.' ~ slug ~ '_uptime_sensor') %}
                      {% set upd = as_datetime(up) %}
                      {% set hrs = ((now() - upd).total_seconds() / 3600) if upd else 0 %}
                      {% set avg = p * 0.024 %}
                      {% set ns.total = ns.total + p %}
                      {% set ns.on = ns.on + (1 if states(ent) == 'on' else 0) %}
                      {% set ns.rows = ns.rows + ['{"name": "' ~ label ~ '", "sub": "' ~ sub ~ '", "entity": "' ~ ent ~ '", "state": "' ~ states(ent) ~ '", "power": ' ~ (p|round(1)) ~ ', "voltage": ' ~ (states('sensor.' ~ slug ~ '_voltage')|float(0)|round(1)) ~ ', "today_kwh": ' ~ (today|round(3)) ~ ', "total_kwh": ' ~ (tot|round(3)) ~ ', "avg_kwh": ' ~ (avg|round(3)) ~ ', "year_cost": ' ~ ((avg * r * 365)|round(0)) ~ ', "signal": ' ~ (states('sensor.' ~ slug ~ '_wifi_signal_percent')|float(0)|round(0)) ~ ', "ip": "' ~ states('sensor.' ~ slug ~ '_ip_address') ~ '", "onstate": "' ~ states('select.' ~ slug ~ '_power_on_state') ~ '", "uptime": "' ~ up ~ '"}'] %}
                      {% endfor %}
                      {"group_state": "{{ states('switch.living_room_lights') }}",
                       "on_count": {{ ns.on }}, "total": {{ ns.total|round(1) }},
                       "items": [{{ ns.rows|join(',') }}]}
                  template: |
                    {{ $g := eq (.JSON.String "group_state") "on" }}
                    <div class="pw">
                      <div class="pw-groupbar">
                        <span class="pw-groupbar-id">
                          <span class="pw-groupbar-name">Living Room Lights</span>
                          <span class="pw-card-sub" style="margin-left: 0;">
                            {{ .JSON.Int "on_count" }} of {{ len (.JSON.Array "items") }} on · {{ printf "%.1f" (.JSON.Float "total") }} W together
                          </span>
                        </span>
                        <span class="pw-pill {{ if $g }}pw-on{{ else }}pw-off{{ end }}" data-ha-pill="switch.living_room_lights">{{ .JSON.String "group_state" }}</span>
                        <button class="pw-toggle" data-entity="switch.living_room_lights">Toggle all</button>
                      </div>

                      <div class="pw-cards">
                        {{ range .JSON.Array "items" }}
                        <details class="pw-card">
                          <summary class="pw-card-head">
                            <span class="pw-card-top">
                              <span class="pw-chev"></span>
                              <span class="pw-card-name">{{ .String "name" }}</span>
                              <span class="pw-pill {{ if eq (.String "state") "on" }}pw-on{{ else }}pw-off{{ end }}" data-ha-pill="{{ .String "entity" }}">{{ .String "state" }}</span>
                              <button class="pw-toggle" data-entity="{{ .String "entity" }}">Toggle</button>
                            </span>
                            <span class="pw-card-sub">{{ .String "sub" }} · {{ printf "%.1f" (.Float "power") }} W now</span>
                            <span class="pw-card-stats">
                              <span class="pw-mini"><span class="pw-k">Avg Daily</span><span class="pw-v">{{ printf "%.2f" (.Float "avg_kwh") }} <span class="pw-v-sub">kWh</span></span></span>
                              <span class="pw-mini"><span class="pw-k">Overall</span><span class="pw-v">{{ printf "%.3f" (.Float "total_kwh") }} <span class="pw-v-sub">kWh</span></span></span>
                              <span class="pw-mini"><span class="pw-k">Cost / Year</span><span class="pw-v">{{ printf "$%.0f" (.Float "year_cost") }}</span></span>
                            </span>
                          </summary>

                          <div class="pw-card-body">
                            <div>
                              <div class="pw-sec-title">Detail</div>
                              <div class="pw-grid pw-grid-bare">
                                <div class="pw-cell"><div class="pw-k">Draw</div><div class="pw-v">{{ printf "%.1f" (.Float "power") }} <span class="pw-v-sub">W</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Voltage</div><div class="pw-v">{{ printf "%.1f" (.Float "voltage") }} <span class="pw-v-sub">V</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Used Today</div><div class="pw-v">{{ printf "%.3f" (.Float "today_kwh") }} <span class="pw-v-sub">kWh</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Signal</div><div class="pw-v">{{ printf "%.0f" (.Float "signal") }} <span class="pw-v-sub">%</span></div></div>
                                <div class="pw-cell"><div class="pw-k">Address</div><div class="pw-v" style="font-size: var(--font-size-h5);">{{ .String "ip" }}</div></div>
                                <div class="pw-cell"><div class="pw-k">On Power Loss</div><div class="pw-v" style="font-size: var(--font-size-h5);">{{ .String "onstate" }}</div></div>
                              </div>
                            </div>
                          </div>
                        </details>
                        {{ end }}
                      </div>
                    </div>

            - size: small
              widgets:
                # ── Whole-house total across every plug ─────────────────────
                - type: custom-api
                  title: Cost Outlook
                  cache: 5m
                  url: http://localhost:8123/api/template
                  method: POST
                  body-type: json
                  headers:
                    Authorization: Bearer ''${readFileFromEnv:HA_TOKEN_FILE}
                  body:
                    template: |-
                      {% set r = ${toString powerRate} %}
                      {% set slugs = ['server_power', 'eclipse', 'lounge_room_lamp', 'colour_lamp', 'christmas_lights'] %}
                      {% set ns = namespace(avg=0, today=0, now=0) %}
                      {% for slug in slugs %}
                      {% set tot = states('sensor.' ~ slug ~ '_total_energy')|float(0) %}
                      {% set up = states('sensor.' ~ slug ~ '_uptime_sensor') %}
                      {% set upd = as_datetime(up) %}
                      {% set hrs = ((now() - upd).total_seconds() / 3600) if upd else 0 %}
                      {% set ns.today = ns.today + states('sensor.' ~ slug ~ '_total_daily_energy')|float(0) %}
                      {% set ns.now = ns.now + states('sensor.' ~ slug ~ '_power')|float(0) %}
                      {% endfor %}
                      {% set ns.avg = ns.now * 0.024 %}
                      {"now": {{ ns.now|round(1) }},
                       "today_cost": {{ (ns.today * r)|round(2) }},
                       "day": {{ (ns.avg * r)|round(2) }},
                       "week": {{ (ns.avg * r * 7)|round(2) }},
                       "month": {{ (ns.avg * r * 30.44)|round(2) }},
                       "year": {{ (ns.avg * r * 365)|round(0) }},
                       "month_kwh": {{ (ns.avg * 30.44)|round(1) }},
                       "supply_year": {{ (${toString powerSupplyDaily} * 365)|round(0) }},
                       "rate": {{ r }}}
                  template: |
                    <div class="pw-rows">
                      <div class="pw-row pw-row-hi">
                        <span class="pw-k">Per Year</span>
                        <span class="pw-v">{{ printf "$%.0f" (.JSON.Float "year") }}</span>
                      </div>
                      <div class="pw-row"><span class="pw-k">Per Month</span><span class="pw-v">{{ printf "$%.2f" (.JSON.Float "month") }}</span></div>
                      <div class="pw-row"><span class="pw-k">Per Week</span><span class="pw-v">{{ printf "$%.2f" (.JSON.Float "week") }}</span></div>
                      <div class="pw-row"><span class="pw-k">Per Day</span><span class="pw-v">{{ printf "$%.2f" (.JSON.Float "day") }}</span></div>
                      <div class="pw-row"><span class="pw-k">So Far Today</span><span class="pw-v">{{ printf "$%.2f" (.JSON.Float "today_cost") }}</span></div>
                      <div class="pw-row"><span class="pw-k">Monthly Use</span><span class="pw-v">{{ printf "%.1f" (.JSON.Float "month_kwh") }} <span class="pw-v-sub">kWh</span></span></div>
                      <div class="pw-row"><span class="pw-k">All Plugs Now</span><span class="pw-v">{{ printf "%.1f" (.JSON.Float "now") }} <span class="pw-v-sub">W</span></span></div>
                      <div class="pw-row"><span class="pw-k">Rate</span><span class="pw-v">{{ printf "$%.4f" (.JSON.Float "rate") }} <span class="pw-v-sub">/kWh</span></span></div>
                      <div class="pw-row"><span class="pw-k">Supply Charge</span><span class="pw-v">{{ printf "$%.0f" (.JSON.Float "supply_year") }} <span class="pw-v-sub">/yr fixed</span></span></div>
                    </div>

                # ── Radio health for every plug ────────────────────────────
                - type: custom-api
                  title: Plug Health
                  cache: 1m
                  url: http://localhost:8123/api/template
                  method: POST
                  body-type: json
                  headers:
                    Authorization: Bearer ''${readFileFromEnv:HA_TOKEN_FILE}
                  body:
                    template: |-
                      {% set devs = [
                        ('Asgard', 'server_power'), ('Eclipse', 'eclipse'),
                        ('Lounge Lamp', 'lounge_room_lamp'), ('Colour Lamp', 'colour_lamp'),
                        ('Christmas', 'christmas_lights')] %}
                      {% set ns = namespace(rows=[]) %}
                      {% for label, slug in devs %}
                      {% set ns.rows = ns.rows + ['{"name": "' ~ label ~ '", "online": "' ~ states('binary_sensor.' ~ slug ~ '_status') ~ '", "signal": ' ~ (states('sensor.' ~ slug ~ '_wifi_signal_percent')|float(0)|round(0)) ~ ', "rssi": ' ~ (states('sensor.' ~ slug ~ '_wifi_signal_db')|float(0)|round(0)) ~ '}'] %}
                      {% endfor %}
                      {"items": [{{ ns.rows|join(',') }}]}
                  template: |
                    <div class="pw-rows">
                      {{ range .JSON.Array "items" }}
                      <div class="pw-row">
                        <span class="pw-k">{{ .String "name" }}</span>
                        <span class="pw-v">
                          {{ printf "%.0f" (.Float "signal") }}<span class="pw-v-sub">%</span>
                          <span class="pw-v-sub">{{ printf "%.0f" (.Float "rssi") }} dBm</span>
                        </span>
                      </div>
                      {{ end }}
                    </div>
    '';
  in
  {

# ══════════════════════════════════════════════════════════════════════════════
# DASHBOARD — Glance (port 8888)
# ══════════════════════════════════════════════════════════════════════════════

    # ── Glance — native systemd service for host-level server-stats ──
    #
    # Both secrets reach the widgets through Glance's `readFileFromEnv` config
    # variable: LoadCredential copies each root-only (0400) sops secret into
    # this unit's private credentials dir (readable by the DynamicUser, nobody
    # else), an env var points at the copy, and Glance substitutes the file's
    # contents when it loads the config. That keeps them out of the Nix store
    # AND off every other local uid:
    #   • SABNZBD_API_KEY_FILE — full control of SABnzbd (Downloads widgets)
    #   • HA_TOKEN_FILE        — an ADMIN Home Assistant token (Monitoring page).
    #     It used to be read with Glance's ''${secret:ha-token}, which reads
    #     /run/secrets directly and so forced the secret to 0444 (later a 0440
    #     group stopgap). Anything holding it can switch.toggle Asgard's own
    #     mains feed, bypassing ha-bridge's allowlist. Declared by the
    #     home-assistant module (Modules/Server/home-assistant.nix).
    #
    # Glance substitutes these as plain text over the whole config file before
    # parsing it, so they work in any value — the HA widgets use the token
    # inside a `headers:` map.
    #
    # ⚠ Glance resolves config variables at STARTUP and refuses to start if one
    # cannot be read, so a missing credential takes the whole dashboard down,
    # not just the widgets that use it.
    systemd.services.glance = {
      description = "Glance Dashboard";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        SABNZBD_API_KEY_FILE = "/run/credentials/glance.service/sabnzbd-api-key";
        HA_TOKEN_FILE = "/run/credentials/glance.service/ha-token";
      };
      serviceConfig = {
        ExecStart = "${pkgs.glance}/bin/glance --config ${glanceConfig}";
        Restart = "on-failure";
        DynamicUser = true;
        LoadCredential = [
          "sabnzbd-api-key:${config.sops.secrets."sabnzbd-api-key".path}"
          "ha-token:${config.sops.secrets."ha-token".path}"
        ];
      };
    };

  };
}
