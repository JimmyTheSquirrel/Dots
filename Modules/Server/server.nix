{ self, inputs, ... }: {

  flake.nixosModules.server = { config, pkgs, lib, activeUser, ... }:
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
    # Nix store. The two that Glance needs are pulled in by Glance itself when it
    # loads the config: `secret:ha-token` from /run/secrets, and the SABnzbd API
    # key via `readFileFromEnv` (see systemd.services.glance below).
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
                  fetch(API + "/run", { method: "POST" })
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

                fetch(API + "/toggle/" + encodeURIComponent(entity), { method: "POST" })
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
        # `ha-token`. `''${secret:ha-token}` is Glance's OWN secret-file syntax
        # (reads /run/secrets/ha-token at request time) — the token never
        # touches the Nix store. See Modules/Server/home-assistant.nix for the
        # sops.secrets declaration (mode 0444 — Glance is a DynamicUser, so
        # there's no static user to own the file).
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
                    Authorization: Bearer ''${secret:ha-token}
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
                    Authorization: Bearer ''${secret:ha-token}
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
                    Authorization: Bearer ''${secret:ha-token}
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
                    Authorization: Bearer ''${secret:ha-token}
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

    imports = [ inputs.nixflix.nixosModules.default ];

# ══════════════════════════════════════════════════════════════════════════════
# NIXFLIX — Arr Stack + Jellyfin + SABnzbd
# Auto-wires: Prowlarr ↔ Sonarr/Radarr/Lidarr, Seerr ↔ Jellyfin/Sonarr/Radarr
# All API keys pre-generated and stored in sops — fully reproducible on deploy.
#
# Port reference (Tailscale-only unless noted):
#   Sonarr     8989  |  Radarr    7878  |  Lidarr   8686
#   Prowlarr   9696  |  SABnzbd  8080
#   Jellyfin   8096  (+ Cloudflare tunnel at jellyfin.bifrost-vault.com)
#   Jellyseerr 5055  (+ Cloudflare tunnel at requests.bifrost-vault.com)
# ══════════════════════════════════════════════════════════════════════════════

    nixflix = {
      enable = true;
      mediaDir    = "/data/media";
      downloadsDir = "/downloads";
      stateDir    = "/data/.state/services";

      sonarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."sonarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      radarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."radarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      lidarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."lidarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      prowlarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."prowlarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
          indexers = [
            # Usenet (primary)
            {
              name = "Miatrix";
              apiKey._secret = config.sops.secrets."indexer-api-keys/Miatrix".path;
            }
            {
              name = "NZBgeek";
              apiKey._secret = config.sops.secrets."indexer-api-keys/NZBGeek".path;
            }
            {
              name = "NzbPlanet";
              apiKey._secret = config.sops.secrets."indexer-api-keys/NZBPlanet".path;
            }
          ];
        };
      };

      jellyfin = {
        enable = true;
        apiKey._secret = config.sops.secrets."jellyfin-api-key".path;
        users.admin = {
          password._secret = config.sops.secrets."jellyfin-admin-password".path;
          policy.isAdministrator = true;
        };

        network = {
          # Off-site clients reach us through the Cloudflare tunnel, and
          # cloudflared connects to Jellyfin over loopback — so every remote
          # session presented as 127.0.0.1 and Jellyfin classified it as LAN,
          # where bandwidth is assumed unlimited. It therefore never adapted
          # anything: a 35 Mbit 4K HEVC remux was shipped to a TV behind a
          # 30 Mbit shaped uplink, stalling every few seconds.
          #
          # Trusting the proxy's X-Forwarded-For restores the real client IP,
          # which is what makes remoteClientBitrateLimit below fire at all.
          # localNetworkSubnets stays empty (= all RFC1918 is local), so LAN
          # clients are still uncapped and direct-play as before.
          knownProxies = [ "127.0.0.1" ];
        };

        # Bits per second. Raised from the original 12 Mbps on 2026-09-11 when
        # Eclipse (the Pi 5 TV box) became a permanent remote client after
        # moving to a second house — 12 Mbps forced every remux into an HLS
        # transcode, which turned out not even to be the main problem (see
        # wan-egress-shaping below), but a stricter cap than Eclipse's typical
        # ~15-20 Mbps HEVC remuxes need is still real quality loss for what is
        # now a primary device, not an occasional public share.
        #
        # Trade-off, accepted deliberately: 40 Mbps is most of the 30 Mbit WAN
        # egress cap on its own, so this no longer comfortably fits "two
        # concurrent remote streams" the way 12 Mbps did. A second simultaneous
        # remote/CF-tunnel viewer while Eclipse is direct-streaming will
        # contend for the same shaped pipe. Revisit if that starts happening.
        system.remoteClientBitrateLimit = 40000000;

        # Intel QuickSync on i5-14400 (UHD 730) — /dev/dri/renderD128
        encoding = {
          hardwareAccelerationType = "qsv";
          qsvDevice = "/dev/dri/renderD128";
          enableHardwareEncoding = true;
          allowHevcEncoding = true;
          hardwareDecodingCodecs = [ "h264" "hevc" "mpeg2video" "vc1" "vp9" "av1" ];
          enableTonemapping = true;
          enableVppTonemapping = true;

          # Unthrottled, ffmpeg transcodes to the end of the film regardless of
          # playback position and nothing reaps the output — a single 4K title
          # nine minutes in had already left 34 GB / 1399 segments in
          # /var/cache/jellyfin/transcodes. Throttle once the encoder is far
          # enough ahead, and drop segments the client has already fetched.
          enableThrottling = true;
          enableSegmentDeletion = true;
        };
      };

      # Jellyseerr — media request portal (exposed via Cloudflare tunnel)
      seerr = {
        enable = true;
        package = pkgs.jellyseerr;
        apiKey._secret = config.sops.secrets."jellyseerr-api-key".path;
      };

      # SABnzbd usenet download client
      usenetClients.sabnzbd = {
        enable = true;
        settings = {
          misc = {
            api_key._secret  = config.sops.secrets."sabnzbd-api-key".path;
            nzb_key._secret  = config.sops.secrets."sabnzbd-nzb-key".path;
            port = 8080;
            par2_multicore = 1;
            par2_threads = 12;
            abort_max_missing = 10;
            fail_hopeless_jobs = true;
            pause_on_pwrar = 2;            # 0=warn, 1=pause, 2=abort. Abort → Failed status → Decluttarr blocklists + Sonarr/Radarr re-search. Prevents jobs stalling forever on encrypted/corrupt RARs.
            host_whitelist = "asgard,asgard.tailb54b82.ts.net,100.119.193.77,host.containers.internal,10.200.1.2";
            inet_exposure = 4;
            x_frame_options = 0;
            web_color = "Night";
            web_compact = true;
            web_fullscreen = true;
            web_tabbed = true;

            # Performance
            article_cache_size = "1G";     # RAM cache — reduces disk thrashing
            enable_par_cleanup = true;     # delete par2 files after successful repair
            pause_on_post_processing = false; # keep downloading while post-processing

            # Direct Unpack — KEEP OFF. Known SAB bug: starts unrar before deobfuscation
            # completes on obfuscated NZBs → partial extracts → jobs marked failed with full
            # MKV sitting in _FAILED_ folder (forum t=27128). Must set BOTH keys: SAB's
            # test_disk_performance() in directunpacker.py forces direct_unpack=True on any
            # disk >100 MB/s when direct_unpack_tested=False. Setting tested=True skips that.
            direct_unpack = false;
            direct_unpack_tested = true;

            # Cleanup hygiene — SAB doesn't auto-delete partial files by default.
            # delete_failed makes SAB nuke incomplete folder when job transitions to failed
            # (won't catch .1 races or _FAILED_ bug #2840 — the zombie sweeper handles those).
            delete_failed = true;
            history_retention = "30";
            history_retention_option = "days-archive";

            # Skip pre-download article verification. With pre_check=1 SAB scans every
            # article on the server before download starts — adds the "Checking" phase
            # that clogs the queue UI for minutes. Real download already checks article
            # CRCs (verify_xff_header path), pre_check is redundant.
            pre_check = false;

            # SAB upstream default. Was set to 3 from a now-rolled-back perf-tuning attempt.
            max_art_tries = 5;
          };
          servers = [
            {
              name = "FrugalUsenet";
              host = "aunews.frugalusenet.com";
              port = 563;
              username._secret = config.sops.secrets."usenet/frugalusenet/username".path;
              password._secret = config.sops.secrets."usenet/frugalusenet/password".path;
              connections = 60;
              ssl = true;
              priority = 0;
              timeout = 30;
              required = true;
            }
            {
              name = "Newshosting";
              host = "news.newshosting.com";
              port = 563;
              username._secret = config.sops.secrets."usenet/newshosting/username".path;
              password._secret = config.sops.secrets."usenet/newshosting/password".path;
              connections = 30;
              ssl = true;
              priority = 0;
              timeout = 30;
              optional = false;
            }
          ];
        };
      };

    };


    # unrar in SABnzbd service PATH — required for RAR-packed NZBs
    systemd.services.sabnzbd.path = [ pkgs.unrar ];


    # Completes the Jellyseerr setup wizard declaratively:
    # logs in via Jellyfin creds, syncs + enables all libraries, marks initialized.
    # Uses session cookie auth (same as nixflix's seerr-setup) — idempotent.
    systemd.services.seerr-library-setup = {
      description = "Activate all Jellyfin libraries in Jellyseerr";
      after    = [ "seerr.service" "seerr-setup.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        COOKIE="/tmp/seerr-library-setup-cookie"

        # Wait up to 2 minutes for Jellyseerr
        for i in $(seq 1 24); do
          if curl -sf "$SEERR/api/v1/status" > /dev/null 2>&1; then break; fi
          echo "Waiting for Jellyseerr... ($i/24)"
          sleep 5
        done

        # Skip if already initialized
        if curl -s "$SEERR/api/v1/settings/public" | jq -e '.initialized == true' > /dev/null; then
          echo "Jellyseerr already initialized — nothing to do."
          exit 0
        fi

        # Log in with credentials only (no server config — Jellyfin is already wired by nixflix)
        echo "Logging in..."
        ADMIN_PASS=$(cat ${config.sops.secrets."jellyfin-admin-password".path})
        LOGIN_CODE=$(curl -s -c "$COOKIE" -X POST \
          -H "Content-Type: application/json" \
          -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" \
          -w "%{http_code}" -o /dev/null \
          "$SEERR/api/v1/auth/jellyfin")

        if [ "$LOGIN_CODE" != "200" ] && [ "$LOGIN_CODE" != "201" ]; then
          echo "Login failed (HTTP $LOGIN_CODE)" >&2; exit 1
        fi
        echo "Logged in."

        # Sync libraries from Jellyfin and enable all of them
        echo "Syncing libraries..."
        LIBS=$(curl -s -b "$COOKIE" "$SEERR/api/v1/settings/jellyfin/library?sync=true")
        echo "Found: $(echo "$LIBS" | jq -r '.[].name' | tr '\n' ' ')"
        LIBRARY_IDS=$(echo "$LIBS" | jq -r '.[].id' | paste -sd,)

        if [ -n "$LIBRARY_IDS" ]; then
          curl -sf -b "$COOKIE" \
            "$SEERR/api/v1/settings/jellyfin/library?enable=$LIBRARY_IDS" > /dev/null
          echo "Libraries enabled: $LIBRARY_IDS"
        else
          echo "Warning: no libraries found"
        fi

        # Mark setup as complete (dismisses wizard permanently)
        curl -sf -b "$COOKIE" -X POST "$SEERR/api/v1/settings/initialize" > /dev/null

        rm -f "$COOKIE"
        echo "Jellyseerr setup complete."
      '';
    };


# ══════════════════════════════════════════════════════════════════════════════
# BOOKS — Audiobookshelf (server) + Shelfarr (request portal)
# Audiobookshelf: port 13378 — serves ebooks + audiobooks (Jellyfin-style UI)
# Shelfarr:       port 5056  — Jellyseerr-style request portal for books
#   Connects to Prowlarr (search) + SABnzbd (download) → delivers to ABS
#
# Post-boot (one-time): open Shelfarr at localhost:5056 → Admin → Settings:
#   Prowlarr: http://localhost:9696 + prowlarr-api-key (from sops)
#   SABnzbd:  http://localhost:8080 + sabnzbd-api-key (from sops)
#   ABS:      http://localhost:13378 + key from ABS Settings → API Keys
# ══════════════════════════════════════════════════════════════════════════════

    # Audiobookshelf — ebook + audiobook server
    virtualisation.oci-containers.containers.audiobookshelf = {
      image = "ghcr.io/advplyr/audiobookshelf:latest";
      ports = [ "13378:80" ];
      volumes = [
        "/var/lib/audiobookshelf/config:/config"
        "/var/lib/audiobookshelf/metadata:/metadata"
        "/data/media/audiobooks:/audiobooks"
        "/data/media/books:/ebooks"
      ];
      environment = {
        TZ = "Australia/Sydney";
      };
      autoStart = true;
    };

    # Shelfarr — Jellyseerr-style book request portal
    # RAILS_MASTER_KEY is auto-generated on first run and stored in /var/lib/shelfarr.
    # As long as the volume persists, the key is preserved across rebuilds.
    virtualisation.oci-containers.containers.shelfarr = {
      image = "ghcr.io/pedro-revez-silva/shelfarr:latest";
      ports = [ "5056:4000" ];
      volumes = [
        "/var/lib/shelfarr:/rails/storage"
        "/data/media/audiobooks:/audiobooks"
        "/data/media/books:/ebooks"
        "/downloads:/downloads"
      ];
      environment = {
        PUID                = "1000";
        PGID                = "1001";
        SOLID_QUEUE_IN_PUMA = "1";
        HTTP_PORT           = "4000";  # Go proxy port — must differ from Rails/Puma (3000)
      };
      autoStart = true;
    };


# ══════════════════════════════════════════════════════════════════════════════
# MANGA — Suwayomi (headless Tachiyomi/Mihon server), port 4567
# Tracks ongoing series from web sources and auto-downloads new chapters as they
# release. Mihon on the phone/tablet connects over the tailnet and reads from here.
#
# Native NixOS module (services.suwayomi-server), not a container — so everything
# except the per-library source/series picks is declarative. Those live in
# Suwayomi's own DB and are genuinely UI state, like noctalia's settings.toml.
#
# TWO PATHS ON PURPOSE:
#   dataDir       /var/lib/suwayomi-server  — H2 database + config, on the NVMe
#   downloadsPath /data/media/manga         — the chapters themselves, on the pool
# The database must NOT sit on /data/media: that is mergerfs (FUSE), and SQLite/H2
# on FUSE is the locking-corruption trap this repo already dodges for the arrs via
# the /data/.state bind mount. Only the media goes on the pool.
# ══════════════════════════════════════════════════════════════════════════════

    # ── FlareSolverr — Cloudflare challenge solver (port 8191) ────────────────
    # A headless-Chrome proxy: other services hand it a URL, it clears the
    # Cloudflare interstitial and hands back the response + cookies.
    #
    # Added because Comick and Manganato both failed in Suwayomi with a bare
    # "Cloudflare bypass currently disabled", which silently removed a large
    # share of usable manga sources — MangaFire and MangaDex were carrying
    # everything on their own.
    #
    # Shared by three consumers, which is why it lives at the top level rather
    # than inside any one of them:
    #   Suwayomi  — native service on the host  -> http://localhost:8191
    #   Shelfarr  — container                   -> http://host.containers.internal:8191
    #   Prowlarr  — could use it as an indexer proxy (NOT configured; see below)
    #
    # It runs a real browser, so it is the heaviest thing in the stack per
    # request (~500 MB resident under load). Asgard has ~22 GB free, so this is
    # noted rather than a concern.
    virtualisation.oci-containers.containers.flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      ports = [ "8191:8191" ];
      environment = {
        LOG_LEVEL = "info";
        TZ = "Australia/Sydney";
      };
      autoStart = true;
    };

    services.suwayomi-server = {
      enable = true;

      # ⚠️ Version override is LOAD-BEARING, not a routine bump.
      #
      # nixpkgs pins 2.1.1867 (Jul 2025), which only understands the LEGACY flat
      # `index.min.json` extension-repo format. Keiyoushi — the community successor
      # to the archived Tachiyomi repo, and effectively the only source repo that
      # matters — migrated to the Mihon 0.20.1+ manifest (`index.pb`, protobuf) and
      # now serves the old path as a TWO-ENTRY DEPRECATION STUB ("Outdated App",
      # "Update to Mihon 0.20.1+").
      #
      # On 2.1 that means the service starts, reports active, answers HTTP 200, and
      # finds exactly ZERO usable sources — a textbook healthy-looking dead end.
      # This was confirmed live on Asgard, not inferred: /api/v1/extension/list
      # returned precisely those two stubs.
      #
      # 2.3.x added the new format (NetworkExtensionStore, @ProtoNumber) while
      # keeping a legacy path. Jar sha256 821141b3… was cross-checked against
      # upstream's published Checksums.sha256 before pinning.
      #
      # Drop this whole override once nixpkgs ships >= 2.3 — and when you do, re-read
      # the note on `extensionStores` below, because the key name moved in the same
      # jump.
      package = pkgs.suwayomi-server.overrideAttrs (_: {
        version = "2.3.2243";
        src = pkgs.fetchurl {
          url = "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v2.3.2243/Suwayomi-Server-v2.3.2243.jar";
          hash = "sha256-ghFBsy4XDUoC08vf7Vd+2PB70iOD/19BMuu1rkDpjdU=";
        };
      });

      # Primary group `media` (gid 1001) is what grants write access to
      # /data/media/manga. The module still creates the `suwayomi` user itself —
      # only the group is overridden, so it does not try to create `media` twice.
      group = "media";

      # tailnet-only; tailscale0 is already in trustedInterfaces, so no port opens.
      openFirewall = false;

      settings.server = {
        ip = "0.0.0.0";

        # 4567 is Suwayomi's own default. The NixOS module defaults to 8080, which
        # on this box is SABnzbd's socat proxy — leaving it at the module default
        # would collide with a live service.
        port = 4567;

        downloadsPath = "/data/media/manga";
        # CBZ so the files stay portable — Mihon, Komga, Kavita and plain readers
        # all open them. The default (loose images in a folder) does not travel.
        downloadAsCbz = true;

        # --- auto-download ---
        autoDownloadNewChapters = true;
        # Upstream defaults this to `true`, which skips auto-download for any entry
        # that still has an unread chapter — i.e. exactly the ongoing series this
        # exists for. Left at the default, the feature does almost nothing.
        excludeEntryWithUnreadChapters = false;
        autoDownloadNewChaptersLimit = 0; # 0 = no cap

        # --- updater: what gets checked for new chapters ---
        globalUpdateInterval = 6; # hours — 6 is the minimum the server accepts
        # Both of these default to `true` and both would exclude ongoing series:
        # a series not opened yet counts as "not started", and any series with a
        # backlog has unread chapters. Completed series really have nothing left
        # to fetch, so that one exclusion stays on.
        excludeNotStarted = false;
        excludeUnreadChapters = false;
        excludeCompleted = true;

        # Suwayomi ships with NO sources at all. Without at least one store there is
        # nothing to search or download, and the UI looks healthy while being empty.
        #
        # ⚠️ The key is `extensionStores` on 2.3 — it was `extensionRepos` on 2.1 and
        # renamed in the same release that added the new format. server.conf is HOCON
        # and unknown keys are silently ignored, so the OLD name fails without a word.
        # The NixOS module still declares the old `extensionRepos` option (it targets
        # 2.1), so that key is also emitted, harmlessly, as an empty list.
        #
        # This is the `.pb` URL Keiyoushi documents for Mihon 0.20.1+. The legacy
        # `…/repo/index.min.json` also resolves on 2.3 — it reads `repo.json` and
        # follows its `index_v2` pointer here — but pointing straight at the real
        # index skips a redirect that only exists for old clients.
        extensionStores = [
          "https://github.com/keiyoushi/extensions/raw/repo/index.pb"
        ];

        # --- Cloudflare ---
        # Without this, Comick and Manganato fail every search with
        # "Cloudflare bypass currently disabled" — the sources install and look
        # fine, they just never return a result. localhost works because
        # Suwayomi is a native host service, not a container.
        flareSolverrEnabled = true;
        flareSolverrUrl = "http://localhost:8191";
        flareSolverrTimeout = 60;      # seconds
        flareSolverrSessionName = "suwayomi";
        flareSolverrSessionTtl = 15;   # minutes
        # Only route through FlareSolverr when a request actually hits a
        # challenge, rather than sending every request through a browser.
        flareSolverrAsResponseFallback = true;
      };
    };


    # ── books-setup.service ───────────────────────────────────────────────────
    # Makes the ebook pipeline reproducible. Until 2026-09-17 this was a
    # "Post-boot (one-time)" comment telling you to click through two web UIs —
    # and it had never been done, so Audiobookshelf sat uninitialised and
    # Shelfarr had zero indexers for three months while Glance showed both
    # green. A running container is not a working pipeline.
    #
    # Idempotent, runs on every rebuild, converges a fresh install:
    #   1. Audiobookshelf — create the root user, then the two libraries
    #   2. Audiobookshelf — mint an API key for Shelfarr
    #   3. Shelfarr       — point it at Prowlarr, SABnzbd and Audiobookshelf
    #
    # ⚠️ Shelfarr's config MUST go through `bin/rails runner`, never sqlite3.
    # `AcquisitionProvider` and `DownloadClient` declare `encrypts :api_key`, so
    # a raw SQL insert stores the key in plaintext and Rails then throws on
    # decrypt. The ActiveRecord::Encryption keys live in the storage volume
    # (`.encryption_keys`), alongside `.secret_key_base` — both are generated by
    # the container's entrypoint on first run and must be sourced before
    # `bin/rails` will even boot.
    #
    # ⚠️ Prowlarr is NOT an `AcquisitionProvider`. That model is for *custom*
    # direct-download providers and its `test_connection` returns false for a
    # Prowlarr URL. Prowlarr is configured through `Setting` rows
    # (`indexer_provider` / `prowlarr_url` / `prowlarr_api_key`) instead. Getting
    # this wrong looks like a working config that silently finds nothing.
    #
    # ⚠️ `prowlarr_url` is `http://10.200.1.1:9696` — the veth host address —
    # and is deliberately DIFFERENT from every other URL here.
    # Shelfarr builds each result's download_url from it and gives SABnzbd
    # `mode=addurl`, so SAB fetches the NZB itself. SAB lives in the Mullvad
    # network namespace and is *not* a podman container, so it cannot resolve
    # `host.containers.internal`. 10.200.1.1 is the one address reachable from
    # both the Shelfarr container and the VPN namespace (both verified 302).
    # Symptom when wrong: the item sits in SAB at 0% showing "Fetch NZB from
    # URL" with an exponentially growing WAIT, and never fails outright.
    # This also needs `veth-vpn-br` in `firewall.trustedInterfaces` (see below),
    # without which the namespace can ping the host but every TCP connect drops.
    #
    # ⚠️ QUOTING: the Ruby below is passed as `bin/rails runner "..."` nested
    # inside `sh -c '...'`. Inside that Ruby block you must avoid **double
    # quotes**, **backticks** and **apostrophes** — a double quote ends the
    # runner argument, a backtick becomes command substitution, and an
    # apostrophe ends the sh -c string. All three produce confusing build-time
    # or run-time syntax errors far from the real edit. Keep commentary that
    # needs punctuation out here, at Nix level, where it never reaches a shell.
    systemd.services.books-setup = {
      description = "Configure Audiobookshelf + Shelfarr (idempotent)";
      after = [ "podman-shelfarr.service" "podman-audiobookshelf.service" "podman-flaresolverr.service" ];
      wants = [ "podman-shelfarr.service" "podman-audiobookshelf.service" "podman-flaresolverr.service" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = [ "/data/media" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
        StartLimitBurst = 5;
      };
      path = with pkgs; [ curl gnugrep gnused coreutils podman ];
      script = ''
        set -uo pipefail
        ABS=http://localhost:13378

        # ── wait for Audiobookshelf ──
        for i in $(seq 1 60); do
          curl -sf --max-time 5 "$ABS/status" >/dev/null 2>&1 && break
          sleep 5
        done

        U=$(cat ${config.sops.secrets."admin-username".path})
        P=$(cat ${config.sops.secrets."admin-password".path})

        # ── 1. root user (only if the server has never been initialised) ──
        if ! curl -sf --max-time 10 "$ABS/status" | grep -q '"isInit":true'; then
          echo "ABS: initialising root user"
          curl -sf --max-time 20 -X POST "$ABS/init" -H 'Content-Type: application/json' \
            -d "{\"newRoot\":{\"username\":\"$U\",\"password\":\"$P\"}}" >/dev/null
        fi

        TOK=$(curl -sf --max-time 20 -X POST "$ABS/login" -H 'Content-Type: application/json' \
          -d "{\"username\":\"$U\",\"password\":\"$P\"}" \
          | grep -oE '"(accessToken|token)":"[^"]+"' | head -1 | sed 's/.*:"//;s/"//')
        [ -n "$TOK" ] || { echo "ABS: login failed"; exit 1; }

        # ── 2. libraries, keyed by name so a re-run never duplicates them ──
        LIBS=$(curl -sf --max-time 20 -H "Authorization: Bearer $TOK" "$ABS/api/libraries")
        mklib() { # $1 = name, $2 = container path, $3 = icon
          echo "$LIBS" | grep -q "\"name\":\"$1\"" && return 0
          echo "ABS: creating library $1 -> $2"
          curl -sf --max-time 20 -X POST "$ABS/api/libraries" \
            -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
            -d "{\"name\":\"$1\",\"folders\":[{\"fullPath\":\"$2\"}],\"mediaType\":\"book\",\"icon\":\"$3\"}" >/dev/null
        }
        mklib Ebooks /ebooks book
        mklib Audiobooks /audiobooks audiobookshelf

        LIBS=$(curl -sf --max-time 20 -H "Authorization: Bearer $TOK" "$ABS/api/libraries")
        libid() { echo "$LIBS" | sed 's/},{/}\n{/g' | grep "\"name\":\"$1\"" \
          | grep -oE '"id":"[^"]+"' | head -1 | sed 's/.*:"//;s/"//'; }
        EBOOK_LIB=$(libid Ebooks)
        AUDIO_LIB=$(libid Audiobooks)

        # ── 3. API key for Shelfarr ──
        # The key's plaintext is only ever returned at creation, so it cannot be
        # re-read later. Only mint a new one when Shelfarr has no usable key.
        HAVE=$(podman exec shelfarr sh -c '. /rails/storage/.encryption_keys; export SECRET_KEY_BASE=$(cat /rails/storage/.secret_key_base); cd /rails && ./bin/rails runner "print Setting.find_by(key: %q(audiobookshelf_api_key))&.value.to_s.length"' 2>/dev/null || echo 0)
        if [ "''${HAVE:-0}" -lt 20 ]; then
          MYID=$(curl -sf --max-time 20 -H "Authorization: Bearer $TOK" "$ABS/api/me" \
            | grep -oE '"id":"[^"]+"' | head -1 | sed 's/.*:"//;s/"//')
          ABS_KEY=$(curl -sf --max-time 20 -X POST "$ABS/api/api-keys" \
            -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
            -d "{\"name\":\"shelfarr\",\"userId\":\"$MYID\",\"isActive\":true}" \
            | grep -oE '"apiKey":"[^"]+"' | head -1 | sed 's/.*:"//;s/"//')
          echo "ABS: minted a new API key for Shelfarr"
        else
          ABS_KEY=""   # keep whatever Shelfarr already holds
          echo "ABS: Shelfarr already holds an API key, leaving it alone"
        fi

        # ── 4. Shelfarr ──
        podman exec \
          -e PROWLARR_KEY="$(cat ${config.sops.secrets."prowlarr-api-key".path})" \
          -e SAB_KEY="$(cat ${config.sops.secrets."sabnzbd-api-key".path})" \
          -e ABS_KEY="$ABS_KEY" \
          -e ABS_URL="http://host.containers.internal:13378" \
          -e ABS_EBOOK_LIB="$EBOOK_LIB" \
          -e ABS_AUDIO_LIB="$AUDIO_LIB" \
          shelfarr sh -c '. /rails/storage/.encryption_keys; export SECRET_KEY_BASE=$(cat /rails/storage/.secret_key_base); cd /rails && ./bin/rails runner "
            H = %q(http://host.containers.internal)
            d = DownloadClient.find_or_initialize_by(name: %q(SABnzbd))
            d.assign_attributes(client_type: %q(sabnzbd), url: %(#{H}:8080),
              api_key: ENV.fetch(%q(SAB_KEY)), category: %q(books),
              download_path: %q(/downloads), enabled: true, priority: 0)
            changed = 0
            # api_key is encrypted non-deterministically, so re-assigning the
            # same plaintext still reports as changed. Counting it would bounce
            # the container on every single rebuild, so ignore that one field.
            changed += 1 if d.new_record? || d.changed.any? { |a| a != %q(api_key) }
            d.save!
            vals = {
              %q(indexer_provider)  => %q(prowlarr),

              # veth host address, NOT host.containers.internal. See the note
              # above the service definition - do not change without reading it.
              %q(prowlarr_url)      => %q(http://10.200.1.1:9696),
              %q(prowlarr_api_key)  => ENV.fetch(%q(PROWLARR_KEY)),
              %q(audiobookshelf_url) => ENV.fetch(%q(ABS_URL)),
              %q(audiobookshelf_ebook_library_id)     => ENV.fetch(%q(ABS_EBOOK_LIB)),
              %q(audiobookshelf_audiobook_library_id) => ENV.fetch(%q(ABS_AUDIO_LIB)),
              # Container -> host, so NOT localhost. Shelfarr uses this for
              # Cloudflare-protected book indexers the same way Suwayomi does
              # for manga sources.
              %q(flaresolverr_url) => %(#{H}:8191),

              # Jellyseerr-style behaviour: a request should grab on its own.
              # Upstream ships this OFF, which leaves every request parked at
              # status=pending forever waiting for someone to hand-pick a
              # release in the UI — it looks like the download silently failed.
              %q(auto_select_enabled) => %q(true),

              # Upstream puts torrent FIRST (see the Nix note above). SABnzbd is
              # the only download client here, so that order makes Shelfarr
              # prefer releases it physically cannot fetch. Built via to_json so
              # no literal double quotes appear in this block.
              %q(preferred_download_types) => [%q(usenet), %q(direct)].to_json,

              # Upstream threshold is 90 and nothing reached it: the best real
              # match for a book scored 88, so every request stalled awaiting
              # manual selection. 85 clears it while still refusing junk.
              %q(auto_select_confidence_threshold) => %q(85),

              # Ships empty, which leaves format unscored. Naming the formats
              # lifted the winning result from 88 to 100, and is what makes the
              # threshold comfortable rather than marginal. epub first so the
              # Audiobookshelf reader and Moon+ both get their best case.
              %q(ebook_preferred_formats) => [%q(epub), %q(mobi), %q(azw3)].to_json
            }
            k = ENV[%q(ABS_KEY)].to_s
            vals[%q(audiobookshelf_api_key)] = k unless k.empty?
            vals.each { |key, v| s = Setting.find_or_initialize_by(key: key); s.value = v; changed += 1 if s.changed?; s.save! }
            IndexerClient.reset_all_connections!
            puts %(SETTINGS_CHANGED=#{changed})
            puts %(shelfarr: indexer=#{IndexerClient.provider} ok=#{IndexerClient.test_connection} sab=#{DownloadClient.first.adapter.test_connection})
          "' | tee /tmp/books-setup-out

        # ── 5. Restart Shelfarr if anything actually changed ───────────────────
        # Settings are read ONCE at boot and cached in the long-lived Puma and
        # SolidQueue processes. Writing the DB from a short-lived `rails runner`
        # updates the row but NOT the running app — and
        # `IndexerClient.reset_all_connections!` only resets the runner process,
        # not the workers that serve requests.
        #
        # Without this restart the service reports success, the DB looks right,
        # and the app keeps emitting the OLD value indefinitely. That is exactly
        # how a corrected `prowlarr_url` kept producing unreachable NZB URLs and
        # books kept stalling in SAB on "Fetch NZB from URL".
        #
        # Conditional so a no-op rebuild does not bounce the container.
        if grep -qE 'SETTINGS_CHANGED=[1-9]' /tmp/books-setup-out; then
          echo "books-setup: settings changed, restarting shelfarr to clear its cache"
          ${pkgs.systemd}/bin/systemctl restart podman-shelfarr

          for i in $(seq 1 24); do
            curl -sf -o /dev/null --max-time 5 http://localhost:5056/session/new && break
            sleep 5
          done

          # Stored `SearchResult.download_url` rows keep whatever prowlarr_url
          # was in effect when that search ran. A URL change therefore strands
          # every in-flight request on a dead link — and because SAB retries a
          # bad fetch forever with a growing WAIT rather than failing, it looks
          # identical to the bug having never been fixed. Drop them and reset
          # those requests so the app re-searches and rebuilds the links.
          podman exec shelfarr sh -c '. /rails/storage/.encryption_keys; export SECRET_KEY_BASE=$(cat /rails/storage/.secret_key_base); cd /rails && ./bin/rails runner "
            good = Setting.find_by(key: %q(prowlarr_url))&.value.to_s
            stale = SearchResult.where.not(download_url: nil).reject { |s| s.download_url.start_with?(good) }
            if stale.any?
              reqs = stale.map(&:request_id).uniq
              stale.each(&:destroy)
              Request.where(id: reqs).where.not(status: %q(completed)).update_all(status: %q(pending))
              # Resetting to pending is not enough on its own — nothing re-scans
              # pending requests, so they would sit there forever looking like a
              # silent failure. Re-enqueue the search for each one.
              Request.where(id: reqs, status: %q(pending)).each { |q| SearchJob.perform_later(q.id) }
              puts %(books-setup: purged #{stale.size} stale-host search results, re-queued #{reqs.size} requests)
            end
          "' || true
        fi
        rm -f /tmp/books-setup-out
      '';
    };


    # Homepage removed — replaced by Glance (port 8888)


# ══════════════════════════════════════════════════════════════════════════════
# AUTOMATION — Decluttarr queue cleaner
# Polls arr service APIs to remove stalled/failed downloads automatically.
# DEFERRED until first boot (needs arr API keys generated by services).
# After first boot:
#   1. Retrieve API keys from each service (Settings → General → API Key)
#   2. Add to sops: sops ~/Dots/Secrets/secrets.yaml
#        decluttarr-env: |
#          SONARR_URL=http://localhost:8989
#          SONARR_KEY=<key>
#          RADARR_URL=http://localhost:7878
#          RADARR_KEY=<key>
#          LIDARR_URL=http://localhost:8686
#          LIDARR_KEY=<key>
#          SABNZBD_URL=http://localhost:8080
#          SABNZBD_KEY=<key>
#          REMOVE_STALLED=True
#          REMOVE_FAILED_IMPORTS=True
#          REMOVE_FAILED=True
#          REMOVE_METADATA_MISSING=True
#          REMOVE_ORPHANS=True
#   3. Un-comment container and add `sops.secrets."decluttarr-env" = {};` below
#   4. Rebuild Asgard
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# QUALITY — Recyclarr (TRaSH Guides quality profile sync)
# Syncs quality profiles + custom formats to Sonarr + Radarr on boot + daily.
#   Sonarr: WEB-1080p + WEB-2160p + Asgard - TV (default, see below)
#   Radarr: Remux-1080p + Remux-2160p + Asgard - Movies (default, see below)
# This fixes grab issues like "only getting Redux" — proper CF scoring applied.
#
# "Asgard - Movies" / "Asgard - TV" (2026-08-16): custom (non-trash_id) merged
# profiles — best compressed quality first (4K, no remux), falling back down
# to whatever's actually available, in one ladder. Remuxes were causing real
# problems (Eclipse's Pi decoder choking on 4K HDR remuxes, WAN bandwidth
# saturation for remote streams — see Claude/eclipse.md) for negligible
# perceptible quality gain. Set as Jellyseerr's default via
# seerr-radarr-profile / seerr-sonarr-profile below, so every user's request
# uses these without having to pick a profile manually.
# ══════════════════════════════════════════════════════════════════════════════

    # ── Missing content search ─────────────────────────────────────────────────
    # Radarr: daily search for all monitored movies without files.
    # Persistent = true → runs immediately on boot if the 4am window was missed.
    systemd.services.radarr-missing-search = {
      description = "Search all missing monitored movies in Radarr";
      after    = [ "radarr.service" ];
      requires = [ "radarr.service" ];
      # Fail closed if the media pool is not mounted — an empty /data/media would make Radarr
      # consider the entire library missing and trigger a mass re-download.
      unitConfig.RequiresMountsFor = [ "/data/media" "/data/.state" ];
      path     = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        curl -sf -X POST \
          -H "X-Api-Key: $RADARR_KEY" \
          -H "Content-Type: application/json" \
          -d '{"name":"MissingMoviesSearch"}' \
          http://localhost:7878/api/v3/command
        echo "Radarr missing movies search triggered."
      '';
    };

    systemd.timers.radarr-missing-search = {
      description = "Radarr missing movies search — on boot + daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnCalendar = "04:00:00";
        Persistent = true;
      };
    };

    # Sonarr: daily search for all monitored episodes without files.
    systemd.services.sonarr-missing-search = {
      description = "Search all missing monitored episodes in Sonarr";
      after    = [ "sonarr.service" ];
      requires = [ "sonarr.service" ];
      # Fail closed if the media pool is not mounted — an empty /data/media would make Sonarr
      # consider the entire library missing and trigger a mass re-download.
      unitConfig.RequiresMountsFor = [ "/data/media" "/data/.state" ];
      path     = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        curl -sf -X POST \
          -H "X-Api-Key: $SONARR_KEY" \
          -H "Content-Type: application/json" \
          -d '{"name":"MissingEpisodeSearch"}' \
          http://localhost:8989/api/v3/command
        echo "Sonarr missing episodes search triggered."
      '';
    };

    systemd.timers.sonarr-missing-search = {
      description = "Sonarr missing episodes search — on boot + daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnCalendar = "04:00:00";
        Persistent = true;
      };
    };

    # Sets Jellyseerr's default Radarr quality profile to "Asgard - Movies"
    # (created by Recyclarr — best-compressed-quality-first, remux excluded).
    # Runs 12min after boot so Recyclarr (5min) has had time to create the
    # profile first. Idempotent — safe to re-run.
    systemd.services.seerr-radarr-profile = {
      description = "Set Jellyseerr default Radarr profile to Asgard - Movies";
      after    = [ "seerr.service" "seerr-setup.service" "radarr.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" "radarr.service" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
      # See the Sonarr sibling below: this retried 2665 times before it was
      # caught. Fail after 5 attempts instead.
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst = 5;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        RADARR="http://localhost:7878"
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        SEERR_KEY=$(cat ${config.sops.secrets."jellyseerr-api-key".path})

        # Wait up to 2min for Jellyseerr
        for i in $(seq 1 24); do
          if curl -sf "$SEERR/api/v1/status" > /dev/null 2>&1; then break; fi
          echo "Waiting for Jellyseerr... ($i/24)"
          sleep 5
        done

        # Find the "Asgard - Movies" profile ID in Radarr
        PROFILE_ID=$(curl -s -H "X-Api-Key: $RADARR_KEY" "$RADARR/api/v3/qualityprofile" | \
          jq -r '.[] | select(.name == "Asgard - Movies") | .id')

        if [ -z "$PROFILE_ID" ]; then
          echo "Asgard - Movies profile not found in Radarr — Recyclarr may not have run yet." >&2
          exit 1
        fi

        # API key, not a Jellyfin session cookie — the `admin` Jellyfin
        # account is a plain REQUEST-only user in Jellyseerr, so the old
        # cookie flow 403'd on every settings call. See the Sonarr sibling.
        CFG=$(curl -sf -H "X-Api-Key: $SEERR_KEY" "$SEERR/api/v1/settings/radarr")
        INSTANCE_ID=$(echo "$CFG" | jq -r '.[0].id')
        CURRENT_PROFILE=$(echo "$CFG" | jq -r '.[0].activeProfileId')

        if [ "$CURRENT_PROFILE" = "$PROFILE_ID" ]; then
          echo "Jellyseerr already using correct profile — nothing to do."
          exit 0
        fi

        # Update the profile
        UPDATED=$(echo "$CFG" | jq --argjson pid "$PROFILE_ID" \
          '.[0] | .activeProfileId = $pid | .activeProfileName = "Asgard - Movies" | del(.id)')
        curl -sf -X PUT -H "X-Api-Key: $SEERR_KEY" \
          -H "Content-Type: application/json" \
          -d "$UPDATED" \
          "$SEERR/api/v1/settings/radarr/$INSTANCE_ID" > /dev/null

        echo "Jellyseerr Radarr profile updated to Asgard - Movies (ID: $PROFILE_ID)"
      '';
    };

    systemd.timers.seerr-radarr-profile = {
      description = "Set Jellyseerr Radarr profile after Recyclarr runs";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "12min";
        Persistent = true;
      };
    };

    systemd.services.seerr-sonarr-profile = {
      description = "Set Jellyseerr default Sonarr profile to Asgard - TV";
      after    = [ "seerr.service" "seerr-setup.service" "sonarr.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" "sonarr.service" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
      # Give up instead of retrying forever. The cookie-auth version below
      # failed every 30s from 2026-07-31 to 2026-08-23 and reached restart
      # counter 2665 — thousands of journal entries, and every
      # `nixos-rebuild switch` exited 4 because of it.
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst = 5;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        SONARR="http://localhost:8989"
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        SEERR_KEY=$(cat ${config.sops.secrets."jellyseerr-api-key".path})

        for i in $(seq 1 24); do
          if curl -sf "$SEERR/api/v1/status" > /dev/null 2>&1; then break; fi
          echo "Waiting for Jellyseerr... ($i/24)"
          sleep 5
        done

        # Auth is the API KEY, not a Jellyfin session cookie. The old cookie
        # flow logged in as the Jellyfin `admin` account, which Jellyseerr
        # imported as an ORDINARY user (permissions: 32 = REQUEST only, not
        # ADMIN). Login returned 200, then every /settings/ call returned
        # 403 as a JSON object, and `.[0]` on it produced the long-running
        # "jq: Cannot index object with number" failure. The API key carries
        # full rights and needs no session at all.
        QP=$(curl -s -H "X-Api-Key: $SONARR_KEY" "$SONARR/api/v3/qualityprofile")
        TV_ID=$(echo "$QP"    | jq -r '.[] | select(.name == "Asgard - TV")    | .id')
        ANIME_ID=$(echo "$QP" | jq -r '.[] | select(.name == "Asgard - Anime") | .id')

        if [ -z "$TV_ID" ] || [ -z "$ANIME_ID" ]; then
          echo "Asgard profiles not found in Sonarr — Recyclarr may not have run yet." >&2
          exit 1
        fi

        CFG=$(curl -sf -H "X-Api-Key: $SEERR_KEY" "$SEERR/api/v1/settings/sonarr")
        INSTANCE_ID=$(echo "$CFG" | jq -r '.[0].id')
        CUR_TV=$(echo "$CFG"      | jq -r '.[0].activeProfileId')
        CUR_ANIME=$(echo "$CFG"   | jq -r '.[0].activeAnimeProfileId')

        if [ "$CUR_TV" = "$TV_ID" ] && [ "$CUR_ANIME" = "$ANIME_ID" ]; then
          echo "Jellyseerr already using correct Sonarr profiles — nothing to do."
          exit 0
        fi

        # Anime requests get the anime profile — Jellyseerr keeps a separate
        # activeAnimeProfileId, which the old version pointed at the TV
        # profile too, so anime was never scored with the fansub tiers.
        UPDATED=$(echo "$CFG" | jq --argjson tv "$TV_ID" --argjson an "$ANIME_ID" \
          '.[0] | .activeProfileId = $tv | .activeProfileName = "Asgard - TV"
               | .activeAnimeProfileId = $an | .activeAnimeProfileName = "Asgard - Anime"
               | del(.id)')
        curl -sf -X PUT -H "X-Api-Key: $SEERR_KEY" \
          -H "Content-Type: application/json" \
          -d "$UPDATED" \
          "$SEERR/api/v1/settings/sonarr/$INSTANCE_ID" > /dev/null

        echo "Jellyseerr Sonarr profiles set: TV=$TV_ID anime=$ANIME_ID"
      '';
    };

    systemd.timers.seerr-sonarr-profile = {
      description = "Set Jellyseerr Sonarr profile after Recyclarr runs";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "12min";
        Persistent = true;
      };
    };

    systemd.services.recyclarr-config = {
      description = "Generate Recyclarr config from sops secrets";
      before   = [ "recyclarr-sync.service" ];
      wantedBy = [ "recyclarr-sync.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/recyclarr
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        # TRaSH's config-templates repo deleted includes.json in 2026-07 and renamed everything;
        # `include: - template: …` no longer resolves ANYTHING (there are no include templates any
        # more) and recyclarr hard-errors, so the sync silently did nothing from 2026-07-11 until
        # this was migrated on 2026-08-11.
        #
        # The replacements are whole-config templates, not includes, so their contents are inlined
        # here by trash_id instead. That is deliberate: trash_ids are stable content hashes, whereas
        # template *names* have now churned twice. Scores and CF definitions still come live from
        # the guide on every sync — only the selection is pinned.
        #
        # Equivalent to the old templates: radarr-remux-web-1080p + radarr-remux-web-2160p and
        # sonarr web-1080p + web-2160p, merged into one instance per service (matching how the old
        # include list put both profiles on one instance).
        #
        # Verified 2026-08-11 by diffing every profile before/after: allowed qualities, cutoffs,
        # cutoffFormatScore (10000), minUpgradeFormatScore (1) and upgradeAllowed are all
        # IDENTICAL — the profiles did not get looser. The only change is a month of TRaSH audio
        # scoring (TrueHD ATMOS +5000, DTS X +4500, FLAC/PCM/DD+ …) plus new negatives
        # (Bad Dual Groups, Line/Mic Dubbed, Black and White Editions at -10000). Sonarr's manual
        # "Any 1080p" profile is not managed here and was untouched.
        cat > /var/lib/recyclarr/recyclarr.yml << EOF
sonarr:
  sonarr-main:
    base_url: http://localhost:8989
    api_key: $SONARR_KEY
    quality_definition:
      type: series
    quality_profiles:
      # The stock TRaSH "WEB-1080p" and "WEB-2160p" profiles were REMOVED from
      # this list on 2026-08-23 and deleted from Sonarr by arr-policy.service.
      # They must stay out of here: recyclarr recreates any profile it is
      # told to manage, so leaving the trash_ids would resurrect them on the
      # next sync and put them back in Jellyseerr's dropdown. Everything now
      # sits on the Asgard profiles below.
      # Custom (not trash_id-based) — mirrors "Asgard - Movies": one ladder,
      # best quality first, remux excluded. Deeper fallback than the stock
      # WEB-only profiles above (which allow WEB and nothing else) because
      # older/catalog shows (Voyager, Kitchen Nightmares back-catalog) often
      # only exist as Bluray-1080p, HDTV, or even DVD/SDTV — a WEB-only
      # profile just never grabs them. Upgrading stays on, so anything
      # grabbed low will get replaced automatically if a better release
      # (still non-remux) shows up later.
      - name: Asgard - TV
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: WEB 2160p
        quality_sort: bottom
        qualities:
          - name: WEB 2160p
            qualities:
              - WEBDL-2160p
              - WEBRip-2160p
          - name: Bluray-2160p
          - name: WEB 1080p
            qualities:
              - WEBDL-1080p
              - WEBRip-1080p
          - name: Bluray-1080p
          - name: HDTV-1080p
          - name: WEB 720p
            qualities:
              - WEBDL-720p
              - WEBRip-720p
          - name: Bluray-720p
          - name: HDTV-720p
          - name: DVD
          - name: SDTV
      # Custom (not trash_id-based) — "Asgard - TV" with every 2160p tier
      # removed. For shows whose ONLY 4K source is a Blu-ray remaster rather
      # than a WEB-DL: there the "upgrade to 4K" is a huge size jump for a
      # disc rip, not a like-for-like swap. Measured 2026-08-23 on Game of
      # Thrones — 3.4 GB/ep on disk vs a 17.1 GB/ep median 2160p release
      # (5x), which alone would have added ~1 TB. Everything else that has
      # real 4K WEB-DLs costs only +1.6 to +8.8 GB/ep and stays on Asgard - TV.
      # Assign this per-series; it is not a default for anything.
      - name: Asgard TV - 1080p
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: WEB 1080p
        quality_sort: bottom
        qualities:
          - name: WEB 1080p
            qualities:
              - WEBDL-1080p
              - WEBRip-1080p
          - name: Bluray-1080p
          - name: HDTV-1080p
          - name: WEB 720p
            qualities:
              - WEBDL-720p
              - WEBRip-720p
          - name: Bluray-720p
          - name: HDTV-720p
          - name: DVD
          - name: SDTV
      # Custom (not trash_id-based) — anime needs its own profile because
      # scoring is fundamentally different: release quality is judged by
      # FANSUB/BD GROUP reputation (the Anime Release Groups CFs below), not
      # by resolution/source the way normal TV is. Structure mirrors TRaSH's
      # own "[Anime] Remux-1080p" guide profile (1080p BD as the top tier,
      # HDTV/WEB-1080p merged into a middle tier, 720p as final fallback) —
      # deliberately DROPPING remux from the top tier (TRaSH merges
      # "Bluray-1080p Remux" + "Bluray-1080p" into one tier and lets the
      # Remux Tier custom format bias toward remux; we just don't allow
      # remux at all, same as Asgard - Movies / Asgard - TV). Anime rarely
      # has meaningful 2160p releases, so no 2160p tier here.
      - name: Asgard - Anime
        reset_unmatched_scores:
          enabled: true
        # ENGLISH DUB IS A HARD REQUIREMENT for anime — no dub, no download.
        #
        # Scoring "Anime Dual Audio" highly is NOT enough on its own, which
        # was proved empirically on 2026-08-23: Sonarr ranks QUALITY TIER
        # ahead of custom-format score, so a Japanese Bluray-1080p (score 0)
        # beat a WEB-DL 720p dual-audio release (score 4100) and was grabbed.
        # CF score only breaks ties WITHIN one quality tier.
        #
        # A minimum score is the only lever that rejects non-dubs outright.
        # 2000 is chosen to sit in the gap between the two populations:
        #   best possible non-dub = WEB Tier 01 1700 + boosts 150 + repack 7 = 1857
        #   any dub               = Anime Dual Audio 2000, before any tier
        # Raising the tier scores above ~1990 would close that gap and break
        # this — keep the arithmetic in mind before editing scores below.
        #
        # Consequence, accepted deliberately: an episode with no dub on the
        # indexers stays MISSING rather than grabbing a sub. For a currently
        # airing season the dub can lag the sub by weeks.
        min_format_score: 2000
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
        quality_sort: bottom
        qualities:
          # NO 2160p TIER — deliberate, and re-confirmed 2026-08-23.
          #
          # It was briefly added that day and then removed the same evening.
          # The reasoning for adding it was wrong: JUJUTSU KAISEN S1 looked
          # like it only had English dubs at 2160p, but that was an artefact
          # of the x265 penalty (see the TV-only block above) suppressing the
          # real 1080p dual-audio releases. Once x265 was un-penalised and
          # "Dubs Only" was added, 1080p dubs were plentiful — S01E02 alone
          # had 150 dual-audio releases including Bluray-1080p and WEBDL-1080p.
          #
          # More importantly there is no 4K master to rip. TV anime is
          # mastered at 1080p (often 720p); native 4K anime is essentially
          # nonexistent, and a WEB-DL cannot exceed what the platform
          # streamed. The "2160p B-Global WEB-DL" files were 2.03 GB against
          # 1.54 GB for the native 1080p Crunchyroll rips already on disk —
          # 4x the pixels for 32% more data, i.e. an upscale. TRaSH's own
          # anime profile has no 2160p tier at all and tops out at
          # Bluray-1080p Remux.
          #
          # Do not re-add this because a show "only has dubs at 4K" — check
          # whether a scoring rule is hiding the 1080p ones first.
          - name: Bluray-1080p
          - name: 1080p
            qualities:
              - HDTV-1080p
              - WEBDL-1080p
              - WEBRip-1080p
          - name: 720p
            qualities:
              - HDTV-720p
              - WEBDL-720p
              - WEBRip-720p
    custom_format_groups:
      add:
        - trash_id: 158188097a58d7687dee647e04af0da3  # [Optional] Golden Rule HD
        - trash_id: e3f37512790f00d0e89e54fe5e790d1c  # [Optional] Golden Rule UHD
        - trash_id: 74aff4168620ed49dcc67e92b2c2a5b4  # [Optional] Language Profiles
        - trash_id: f206572b1147d0221bb1c96765b349e8  # [Release Groups] Anime
        - trash_id: 4d3dc16c3ab3adc640afb8d6e3dc2266  # [Optional] Anime Optional (dual audio, uncensored, 10bit)
        - trash_id: 4b196eed652c65ea98d615212040ebe2  # [Required] Anime Versions (v0-v4)
        - trash_id: 85fae4a2294965b75710ef2989c850eb  # [Streaming Services] HD/UHD boost
        - trash_id: 59c3af66780d08332fdc64e68297098f  # [Unwanted] Unwanted Formats
        - trash_id: bad5bc85573a0134e1e1987c46f67e98  # [Optional] Accessibility (WiTH AD/ASL/BASL/BSL)
    # Explicit scores for Asgard - TV / Asgard - Anime (custom, non-trash_id
    # profiles). NEEDED — custom_format_groups.add only creates the formats,
    # it does NOT score them for a non-trash_id profile; reset_unmatched_scores
    # then zeroes everything. This is what let 100+ fake "AI Upscale" Star
    # Trek Voyager releases through on 2026-08-17 before it was caught.
    # Every trash_id/score below is the real trash-guide default, fetched
    # directly from TRaSH-Guides/Guides docs/json/sonarr/cf/*.json — not
    # guessed. Re-verify against that repo if these ever look wrong.
    custom_formats:
      - trash_ids:
          - 23297a736ca77c0fc8e70f8edd7ee56c  # Upscaled
          - 9c11cd3f07101cdba90a2d81cf0e56b4  # LQ
          - e2315f990da2e2cbfc9fa5b7a6fcfe48  # LQ (Release Title)
          - 85c61753df5da1fb2aab6f2a47426b09  # BR-DISK
          - 32b367365729d530ca1c124a0b180c64  # Bad Dual Groups
          - fbcb31d8dabd2a319072b84fc0b7249c  # Extras
          # AV1 — on TRaSH's anime unwanted list, and a hard playback
          # constraint here: Eclipse is a Pi 5, which has HEVC hardware
          # decode but NO AV1 decoder, so AV1 falls back to software and
          # struggles. Added 2026-08-23 after raising the dub scores caused
          # Sonarr to grab three [Breeze] "[1080p.AV1][Dual.Audio]" releases
          # — they satisfied "has English audio" and nothing objected.
          - 15a05bc7c1a36e2b57fd628f8977e2fc  # AV1
        score: -10000
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      # Accessibility variants — releases where the ONLY audio track is an
      # alternate accessibility mix, not the normal one. Added 2026-08-28
      # after Mythic Quest was found unwatchable: 15 of its episodes were
      # Kitsune "with Audio Description" releases, and ffprobe confirmed they
      # carry exactly ONE audio stream, titled "Descriptive" — there is no
      # normal English track to switch to in the player, so the narrator
      # talks over the whole episode. All the Light We Cannot See (4 eps) and
      # Invincible S04 (4 eps) had the same problem.
      #
      # Nothing else in the config objected: the releases are genuine 1080p
      # WEB-DL DDP5.1 Atmos from a decent group, so they scored *well*.
      #
      # NOTE the mkv disposition flag `visual_impaired` is 0 on these files,
      # so Jellyfin cannot detect or avoid them client-side either. The
      # release title is the only signal, which is exactly what this CF
      # matches. ASL/BASL/BSL are the sign-language equivalents from the same
      # TRaSH group — same problem, same score.
      - trash_ids:
          - 44ccbcbc74506f208973e1463b11705f  # WiTH AD
          - c196536ea8122397c5854040d01f2aa7  # WiTH ASL
          - b40dc2e630723745aab9f1b94f4aab74  # WiTH BASL
          - 0aef382c4ed4c5eb5d40109dfd351b72  # WiTH BSL
        score: -10000
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      # TV-ONLY negatives. Both of these are correct for live-action TV and
      # actively harmful for anime, so they are deliberately NOT assigned to
      # Asgard - Anime. TRaSH's anime profile does not use either.
      #
      # "Language: Not Original" rejects releases whose language is not the
      # series' ORIGINAL language. Right for English-origin TV (blocks
      # foreign dubs); backwards for anime, where the original IS Japanese,
      # so an English-dub-only release trips it and takes -10000.
      #
      # "x265 (HD)" targets wasteful x265 re-encodes of live-action HD.
      # Anime is different: 10-bit x265 is the normal, high-quality format
      # for fansub/BD groups, and TRaSH's anime unwanted list is only
      # Anime Raws / Anime LQ Groups / AV1 / Dubs Only / VOSTFR / v0 — no
      # x265 at all. Applying it here scored real 1080p dual-audio releases
      # at -8000 (e.g. [EMBER] Sakamoto Days S01E03 [1080p] [Dual Audio
      # HEVC WEBRip DDP]), which forced a 720p grab on 2026-08-23 because
      # the only unpenalised dub was 720p.
      - trash_ids:
          - ae575f95ab639ba5d15f663bf019e3e8  # Language: Not Original
          - 47435ece6b99a0b477caf360e79ba0bb  # x265 (HD)
        score: -10000
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
      - trash_ids:
          - d0c516558625b04b363fa6c5c2c7cfd4  # WEB Scene
        score: 1600
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - e6258996055b9fbab7e9cb2f75819294  # WEB Tier 01
        score: 1700
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - 58790d4e2fdcd9733aa7ae68ba2bb503  # WEB Tier 02
        score: 1650
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - d84935abd3f8556dcd51d4f27e22d0a6  # WEB Tier 03
        score: 1600
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - 218e93e5702f44a68ad9e3c6ba87d2f0  # HD Streaming Boost
          - 43b3cf48cb385cd3eac608ee6bca7f09  # UHD Streaming Boost
        score: 75
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - ec8fa7296b64e8cd390a1600981f3923  # Repack/Proper
        score: 5
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - eb3d5cc0a2be0db205fb823640db6a3c  # Repack2
        score: 6
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - 44e7c4de10ae50265753082e5dc76047  # Repack3
        score: 7
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      # Anime-only: fansub/BD release-group reputation tiers. This IS the
      # scoring that actually matters for anime — release quality there is
      # judged by which group did the encode, not resolution/source.
      - trash_ids:
          - 949c16fe0a8147f50ba82cc2df9411c9  # Anime BD Tier 01
        score: 1400
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - ed7f1e315e000aef424a58517fa48727  # Anime BD Tier 02
        score: 1300
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 096e406c92baa713da4a72d88030b815  # Anime BD Tier 03
        score: 1200
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 30feba9da3030c5ed1e0f7d610bcadc4  # Anime BD Tier 04
        score: 1100
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 545a76b14ddc349b8b185a6344e28b04  # Anime BD Tier 05
        score: 1000
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 25d2afecab632b1582eaf03b63055f72  # Anime BD Tier 06
        score: 900
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 0329044e3d9137b08502a9f84a7e58db  # Anime BD Tier 07
        score: 800
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - c81bbfb47fed3d5a3ad027d077f889de  # Anime BD Tier 08
        score: 700
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - e0014372773c8f0e1bef8824f00c7dc4  # Anime Web Tier 01
        score: 600
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 19180499de5ef2b84b6ec59aae444696  # Anime Web Tier 02
        score: 500
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - c27f2ae6a4e82373b0f1da094e2489ad  # Anime Web Tier 03
        score: 400
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 4fd5528a3a8024e6b49f9c67053ea5f3  # Anime Web Tier 04
        score: 300
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 29c2a13d091144f63307e4a8ce963a39  # Anime Web Tier 05
        score: 200
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - dc262f88d74c651b12e9d90b39f6c753  # Anime Web Tier 06
        score: 100
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - b4a1b3d705159cdca36d71e57ca86871  # Anime Raws
          - e3515e519f3b1360cbfc17651944354c  # Anime LQ Groups
        score: -10000
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 418f50b10f1907201b6cfdf881f467b7  # Anime Dual Audio (no guide default)
        # DECISIVE, not a nudge. The release-group tiers above top out at
        # 1700, so the old score of 25 was ~50x too small to ever change an
        # outcome — a Japanese-only release from a better fansub group won
        # every time. Audited 2026-08-23: 28 of 162 anime files had no
        # English track at all (JUJUTSU KAISEN S1 was a French Blu-ray rip,
        # SAKAMOTO DAYS had Portuguese and raw-Japanese files). At 2000 a
        # dual-audio release outranks any tier, which is the intended
        # trade — audio language wins over encode quality for this library.
        score: 2000
        assign_scores_to:
          - name: Asgard - Anime
      # "Dubs Only" catches English-dub releases that do NOT advertise dual
      # audio — titles like "Sakamoto Days - 03 [English Dub][1080p]", plus
      # the known dub groups (Yameii, KamiFS, Golumpa, KaiDubs...). The
      # "Anime Dual Audio" CF above cannot match these: its regex looks for
      # a DUAL token or a JA+EN language pair, so a dub-only release scores
      # 0 and is rejected by min_format_score.
      #
      # TRaSH scores this -10000, because their anime guide is written for
      # people who want the ORIGINAL Japanese audio with subs. This library
      # wants the opposite, so the sign is deliberately inverted. Same 2000
      # as dual audio: either one satisfies "has English audio".
      - trash_ids:
          - 9c14d194486c4014d422adc64092d794  # Dubs Only
        score: 2000
        assign_scores_to:
          - name: Asgard - Anime
radarr:
  radarr-main:
    base_url: http://localhost:7878
    api_key: $RADARR_KEY
    quality_definition:
      type: movie
    quality_profiles:
      # "Remux + WEB 1080p" / "Remux + WEB 2160p" were REMOVED here on
      # 2026-08-23 and deleted from Radarr by arr-policy.service — they held
      # zero movies (all 237 are on Asgard - Movies) and only cluttered
      # Jellyseerr. Same rule as the Sonarr block above: if the trash_ids go
      # back in this list, recyclarr recreates the profiles.
      # Custom (not trash_id-based) — no official TRaSH profile spans both
      # resolutions in one ladder. Merges HD Bluray + WEB (d1d67249…) and
      # UHD Bluray + WEB (64fb5f98…) qualities into one profile, remux
      # excluded entirely, so this can never grab/keep a remux release.
      # Upgrading is allowed up to Bluray-2160p, so a 1080p grab will later
      # get replaced by a 4K one if a clean (non-remux) release shows up.
      - name: Asgard - Movies
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: Bluray-2160p
        quality_sort: bottom
        qualities:
          - name: Bluray-2160p
          - name: WEB 2160p
            qualities:
              - WEBRip-2160p
              - WEBDL-2160p
          - name: Bluray-1080p
          - name: WEB 1080p
            qualities:
              - WEBRip-1080p
              - WEBDL-1080p
    custom_format_groups:
      add:
        - trash_id: f8bf8eab4617f12dfdbd16303d8da245  # [Optional] Golden Rule HD
        - trash_id: ff204bbcecdd487d1cefcefdbf0c278d  # [Optional] Golden Rule UHD
        - trash_id: a3ac6af01d78e4f21fcb75f601ac96df  # [Unwanted] Unwanted Formats
        - trash_id: bc3c13e52f2971319bc1748ffa3d1078  # [Optional] Accessibility (WiTH AD/ASL/BASL/BSL)
    # Explicit scores for Asgard - Movies (custom, non-trash_id profile) —
    # see the matching comment under sonarr-main above for why this is
    # necessary. Real trash-guide defaults, fetched directly from
    # TRaSH-Guides/Guides docs/json/radarr/cf/*.json.
    custom_formats:
      - trash_ids:
          - bfd8eb01832d646a0a89c4deb46f8564  # Upscaled
          - 90a6f9a284dff5103f6346090e6280c8  # LQ
          - e204b80c87be9497a8a6eaff48f72905  # LQ (Release Title)
          - ed38b889b31be83fda192888e2286d83  # BR-DISK
          - b6832f586342ef70d9c128d40c07b872  # Bad Dual Groups
          - dc98083864ea246d05a42df0d05f81cc  # x265 (HD)
          - 0a3f082873eb454bde444150b70253cc  # Extras
          - b8cd450cbfa689c0259a01d9e29ba3d6  # 3D
          - 712d74cd88bceb883ee32f773656b1f5  # Sing-Along Versions
          - cc444569854e9de0b084ab2b8b1532b2  # Black and White Editions
          - c465ccc73923871b3eb1802042331306  # Line/Mic Dubbed
          # Accessibility variants — the audio-description / sign-language
          # cuts. No movie had been caught by this yet (the 2026-08-28 sweep
          # found AD releases only in TV), but the failure mode is identical
          # and there is no reason to leave Radarr exposed. See the matching
          # block under sonarr-main for the full write-up.
          - 127bdbadcf3e4463a8c707759fbaad75  # WiTH AD
          - 09c60ba54fadb511c6986a7edec4da4b  # WiTH ASL
          - 41e4baea7b10ddefc6609d52f742dacd  # WiTH BASL
          - e205c5ba6be76b472903f4aec97fdb4b  # WiTH BSL
          # Dolby Vision Profile 5 — no HDR10 fallback. Its base layer is IPT-C2, so any
          # player without DV support decodes it as YCbCr and the picture comes out GREEN.
          # Eclipse (Pi 5 / LibreELEC) has no DV support at all, so P5 is unwatchable there
          # without a server-side transcode. Radarr picked one for Tomorrowland (2026-09-07)
          # because nothing above scores video range: it ranked on TrueHD ATMOS (+5000) and
          # took the DV twin of an otherwise identical release from the same group and WEB
          # source. Full write-up in Claude/eclipse.md.
          # Matches "Dolby Vision AND WEBDL AND NOT HDR", i.e. exactly P5 — releases named
          # DV.HDR (Profile 8.1) carry an HDR10 base layer, direct-play correctly, and are
          # deliberately NOT caught by this.
          - 923b6abef9b17f937fab56cfcf89e1f1  # DV (w/o HDR fallback)
        score: -10000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - c20f169ef63c5f40c2def54abaf4438e  # WEB Tier 01
        score: 1700
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 403816d65392c79236dcb6dd591aeda4  # WEB Tier 02
        score: 1650
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - af94e0fe497124d1f9ce732069ec8c3b  # WEB Tier 03
        score: 1600
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - e7718d7a3ce595f289bfee26adc178f5  # Repack/Proper
        score: 5
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - ae43b294509409a6a13919dedd4764c4  # Repack2
        score: 6
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 5caaaa1c08c1742aa4342d8c4cc463f2  # Repack3
        score: 7
        assign_scores_to:
          - name: Asgard - Movies
      # Audio format hierarchy — real trash-guide defaults
      - trash_ids:
          - 496f355514737f7d83bf7aa4d24f8169  # TrueHD ATMOS
        score: 5000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 2f22d89048b01681dde8afe203bf2e95  # DTS X
        score: 4500
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 1af239278386be2919e1bcee0bde047e  # DD+ ATMOS
        score: 3000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 3cafb66171b47f226146a0770576870f  # TrueHD
        score: 2750
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - dcf3ec6938fa32445f590a4da84256cd  # DTS-HD MA
        score: 2500
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - a570d4a0e56a2874b64e5bfa55202a1b  # FLAC
          - e7c2fcae07cbada050a0af3357491d7b  # PCM
        score: 2250
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 8e109e50e0a0b83a5098b056e13bf6db  # DTS-HD HRA
        score: 2000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 185f1dd7264c4562b9022d963ac37424  # DD+
        score: 1750
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - f9f847ac70a0af62ea4a08280b859636  # DTS-ES
        score: 1500
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 1c1a4c5e823891c75bc50380a6866f73  # DTS
        score: 1250
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 240770601cc226190c367ef59aba7463  # AAC
        score: 1000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - c2998bd0d90ed5621d8df281e839436e  # DD
        score: 750
        assign_scores_to:
          - name: Asgard - Movies
EOF
        chmod 600 /var/lib/recyclarr/recyclarr.yml
      '';
    };

    systemd.services.recyclarr-sync = {
      description = "Sync TRaSH Guides quality profiles via Recyclarr";
      after  = [ "recyclarr-config.service" "sonarr.service" "radarr.service" "network-online.target" ];
      wants  = [ "recyclarr-config.service" "sonarr.service" "radarr.service" "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.recyclarr}/bin/recyclarr sync --config /var/lib/recyclarr/recyclarr.yml";
        # RECYCLARR_APP_DATA was removed upstream — recyclarr now hard-errors on it and the sync
        # never runs. CONFIG_DIR replaces it; DATA_DIR is optional and defaults to CONFIG_DIR.
        Environment = "RECYCLARR_CONFIG_DIR=/var/lib/recyclarr";
      };
    };

    systemd.timers.recyclarr-sync = {
      description = "Daily Recyclarr sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";
      };
    };

    # Per-item state that recyclarr cannot express. Recyclarr owns quality
    # profiles and custom-format SCORES; it has no concept of "which series
    # uses which profile", series type, release profiles, or Jellyfin user
    # settings. Those are per-record database state, so they are applied here
    # over the APIs instead — idempotently, so a fresh install converges to
    # the same place and re-running is a no-op.
    #
    # Ordered after recyclarr-sync: it reads profiles BY NAME and bails out
    # harmlessly if they do not exist yet (first boot, before the first sync).
    systemd.services.arr-policy = {
      description = "Apply per-series / per-user policy to Sonarr, Radarr and Jellyfin";
      # Ordered after the seerr-*-profile units on purpose: Jellyseerr was
      # pointing at the stock "Any" profile (id 1), which this service
      # deletes. Repoint Jellyseerr first, then delete, or requests land on a
      # profile that no longer exists.
      after    = [ "recyclarr-sync.service" "sonarr.service" "radarr.service" "jellyfin.service"
                   "seerr-sonarr-profile.service" "seerr-radarr-profile.service" "network-online.target" ];
      wants    = [ "recyclarr-sync.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -u
        SONARR=http://localhost:8989
        RADARR=http://localhost:7878
        JELLYFIN=http://localhost:8096
        SK=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RK=$(cat ${config.sops.secrets."radarr-api-key".path})
        JK=$(cat ${config.sops.secrets."jellyfin-api-key".path})

        # Wait for Sonarr; everything else is best-effort within this run.
        for i in $(seq 1 30); do
          curl -sf -m 5 -H "X-Api-Key: $SK" $SONARR/api/v3/system/status >/dev/null && break
          sleep 5
        done

        QP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/qualityprofile) || QP="[]"
        TV=$(echo "$QP"     | jq -r '.[]|select(.name=="Asgard - TV")|.id')
        TV1080=$(echo "$QP" | jq -r '.[]|select(.name=="Asgard TV - 1080p")|.id')
        ANIME=$(echo "$QP"  | jq -r '.[]|select(.name=="Asgard - Anime")|.id')

        if [ -z "$TV" ] || [ -z "$TV1080" ] || [ -z "$ANIME" ]; then
          echo "arr-policy: Asgard profiles not present yet (recyclarr has not synced) - skipping"
          exit 0
        fi

        # --- Sonarr: series -> profile + series type -------------------------
        # Anime gets seriesType=anime so absolute episode numbering parses.
        # Game of Thrones is pinned to the 1080p ladder: its only 4K source is
        # a Blu-ray remaster at ~17 GB/ep vs 3.4 GB/ep on disk (measured
        # 2026-08-23), which would have added ~1 TB on its own.
        SERIES=$(curl -sf -m 30 -H "X-Api-Key: $SK" $SONARR/api/v3/series) || SERIES="[]"
        echo "$SERIES" | jq -c '.[]' | while read -r S; do
          ID=$(echo "$S" | jq -r .id)
          TITLE=$(echo "$S" | jq -r .title)
          case "$TITLE" in
            "SAKAMOTO DAYS"|"Good Night World"|"Sword Art Online"|"Solo Leveling"|"JUJUTSU KAISEN")
              WANT_P=$ANIME;  WANT_T=anime ;;
            # The 2005 cartoon was animated for 4:3 SD and remastered no
            # higher than 1080p — there is no 4K master to grab. Pinning it
            # to the 1080p ladder is therefore free, and it doubles as the
            # first line of defence against the 2024 Netflix live-action
            # remake, whose releases are all 2160p (see the block below).
            "Avatar: The Last Airbender"|"Game of Thrones")
              WANT_P=$TV1080; WANT_T=standard ;;
            *)
              WANT_P=$TV;     WANT_T=standard ;;
          esac
          CUR_P=$(echo "$S" | jq -r .qualityProfileId)
          CUR_T=$(echo "$S" | jq -r .seriesType)
          if [ "$CUR_P" != "$WANT_P" ] || [ "$CUR_T" != "$WANT_T" ]; then
            echo "$S" | jq --argjson p "$WANT_P" --arg t "$WANT_T" \
                  '.qualityProfileId=$p | .seriesType=$t' \
              | curl -sf -m 30 -X PUT -H "X-Api-Key: $SK" \
                     -H 'Content-Type: application/json' --data-binary @- \
                     "$SONARR/api/v3/series/$ID" >/dev/null \
              && echo "arr-policy: $TITLE -> profile $WANT_P / $WANT_T" \
              || echo "arr-policy: FAILED to update $TITLE"
          fi
        done

        # --- Sonarr: block the fake-dual-audio group -------------------------
        # "Anime Dual Audio" matches on the literal token DUAL, so a
        # Portuguese+Japanese release like
        #   SAKAMOTO.DAYS.S01E03.1080p.NF.WEB-DL.DDP5.1.H.264.DUAL-sh4down
        # scores as if it were an English dub. TRaSH's own "Bad Dual Groups"
        # list does NOT include sh4down (checked 2026-08-23, all 34 entries),
        # so it is blocked here. A release profile is used rather than a
        # custom format because recyclarr's reset_unmatched_scores would zero
        # a locally-scored CF on its next sync; it does not touch these.
        # "AV1" is also blocked here, NOT only via the AV1 custom format.
        # TRaSH's AV1 CF regex is \bAV1\b, which does not match a title like
        #   [Breeze].Sakamoto.Days-S01E13.1080p.AV1Dual.Audio.weekly
        # because there is no word boundary between AV1 and Dual. That
        # release scored +2000 on Anime Dual Audio alone and was grabbed on
        # 2026-08-23 despite the CF being at -10000. A release-profile
        # ignored term is a plain substring match, so it has no such gap.
        DESIRED='["sh4down","AV1"]'
        RP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/releaseprofile) || RP="[]"
        EXISTING=$(echo "$RP" | jq -c '.[]|select(.name=="Asgard - fake dual audio")')
        if [ -z "$EXISTING" ]; then
          curl -sf -m 15 -X POST -H "X-Api-Key: $SK" -H 'Content-Type: application/json' \
            -d "{\"name\":\"Asgard - fake dual audio\",\"enabled\":true,\"required\":[],\"ignored\":$DESIRED,\"indexerId\":0,\"tags\":[]}" \
            $SONARR/api/v3/releaseprofile >/dev/null \
            && echo "arr-policy: created release profile (sh4down, AV1)" \
            || echo "arr-policy: FAILED to create release profile"
        elif [ "$(echo "$EXISTING" | jq -c '.ignored|sort')" != "$(echo "$DESIRED" | jq -c 'sort')" ]; then
          RPID=$(echo "$EXISTING" | jq -r .id)
          echo "$EXISTING" | jq --argjson ig "$DESIRED" '.ignored=$ig' \
            | curl -sf -m 15 -X PUT -H "X-Api-Key: $SK" \
                   -H 'Content-Type: application/json' --data-binary @- \
                   "$SONARR/api/v3/releaseprofile/$RPID" >/dev/null \
            && echo "arr-policy: updated release profile ignored terms" \
            || echo "arr-policy: FAILED to update release profile"
        fi

        # --- Sonarr: keep the live-action remake out of the 2005 cartoon -----
        # Netflix's 2024 live-action "Avatar: The Last Airbender" has its own
        # TVDB entry, but its releases are titled identically to the cartoon's
        #   Avatar.The.Last.Airbender.S01E02.2024.2160p.NF.WEB-DL...
        # so Sonarr matched them straight onto tvdb 74852 (the 2005 series).
        # Found 2026-08-28: 14 live-action episodes had been imported into the
        # cartoon — S01E02-E08 and S02E01-E07 — and because they filled those
        # slots Sonarr reported both seasons as complete. Runtime is the
        # giveaway: 47-69 min against 23-25 min for real episodes.
        #
        # A TAGGED release profile, not a global one: HHWEB/XEBEC/BYNDR are
        # ordinary groups that do other shows legitimately, so these terms
        # must only ever apply to this one series.
        #
        # The term targets audio, which is the most durable discriminator
        # available: all 14 live-action files carry DDP5.1 Atmos, and a 2005
        # Nickelodeon cartoon will never gain a genuine Atmos mix. Group names
        # and the "2024" token would both drift as new releases appear.
        #
        # Deliberately ONLY "Atmos", not "DDP5.1" — Netflix does carry 5.1
        # audio for parts of the animated series, so blocking DDP5.1 outright
        # risks rejecting a legitimate release. Atmos alone already matches
        # every live-action file observed.
        #
        # "SKST" is a SECOND, unrelated problem that the 2026-08-28 redo
        # exposed. That release set collapses the show's two-parters into one
        # file and then renumbers everything after it, so its episode numbers
        # drift out of step with TVDB:
        #   SKST S03E12 = "The Firebending Masters"  (TVDB E13)
        #   SKST S03E14 = "The Southern Raiders"     (TVDB E16)
        # Sonarr matches on the S/E in the release title and never checks the
        # episode name, so these import into the wrong slots and every episode
        # from the first two-parter onward plays the NEXT one. That is exactly
        # how S02E13-E18 and S03E11-E16 ended up wrong the first time round,
        # and re-searching reproduced it within minutes.
        #
        # The AMZN set (CtrlHD / SiGMA) numbers correctly because it ships
        # two-parters as real multi-episode releases that Sonarr parses into
        # both slots — S02E12E13, S03E10E11, S03E14E15, S03E18E19E20E21 — so
        # blocking SKST leaves a complete, correctly-numbered alternative at
        # the same WEBDL-1080p tier. Verified across all 61 episodes.
        ATLA_ID=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/series \
                  | jq -r '.[]|select(.tvdbId==74852)|.id')
        if [ -n "$ATLA_ID" ] && [ "$ATLA_ID" != "null" ]; then
          TAGID=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/tag \
                  | jq -r '.[]|select(.label=="atla-animated")|.id')
          if [ -z "$TAGID" ] || [ "$TAGID" = "null" ]; then
            TAGID=$(curl -sf -m 15 -X POST -H "X-Api-Key: $SK" \
                      -H 'Content-Type: application/json' \
                      -d '{"label":"atla-animated"}' $SONARR/api/v3/tag | jq -r .id)
          fi
          if [ -n "$TAGID" ] && [ "$TAGID" != "null" ]; then
            # Tag the series (idempotent — only PUTs when the tag is absent).
            ASER=$(curl -sf -m 15 -H "X-Api-Key: $SK" "$SONARR/api/v3/series/$ATLA_ID")
            if [ "$(echo "$ASER" | jq --argjson t "$TAGID" '.tags|index($t)')" = "null" ]; then
              echo "$ASER" | jq --argjson t "$TAGID" '.tags += [$t]' \
                | curl -sf -m 30 -X PUT -H "X-Api-Key: $SK" \
                       -H 'Content-Type: application/json' --data-binary @- \
                       "$SONARR/api/v3/series/$ATLA_ID" >/dev/null \
                && echo "arr-policy: tagged Avatar with atla-animated"
            fi
            ATLA_IGN='["Atmos","SKST"]'
            ARP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/releaseprofile) || ARP="[]"
            AEX=$(echo "$ARP" | jq -c '.[]|select(.name=="Asgard - ATLA live-action block")')
            if [ -z "$AEX" ]; then
              curl -sf -m 15 -X POST -H "X-Api-Key: $SK" -H 'Content-Type: application/json' \
                -d "{\"name\":\"Asgard - ATLA live-action block\",\"enabled\":true,\"required\":[],\"ignored\":$ATLA_IGN,\"indexerId\":0,\"tags\":[$TAGID]}" \
                $SONARR/api/v3/releaseprofile >/dev/null \
                && echo "arr-policy: created ATLA live-action release profile" \
                || echo "arr-policy: FAILED to create ATLA release profile"
            elif [ "$(echo "$AEX" | jq -c '.ignored|sort')" != "$(echo "$ATLA_IGN" | jq -c 'sort')" ] \
              || [ "$(echo "$AEX" | jq -c '.tags')" != "[$TAGID]" ]; then
              ARPID=$(echo "$AEX" | jq -r .id)
              echo "$AEX" | jq --argjson ig "$ATLA_IGN" --argjson t "$TAGID" \
                    '.ignored=$ig | .tags=[$t]' \
                | curl -sf -m 15 -X PUT -H "X-Api-Key: $SK" \
                       -H 'Content-Type: application/json' --data-binary @- \
                       "$SONARR/api/v3/releaseprofile/$ARPID" >/dev/null \
                && echo "arr-policy: updated ATLA live-action release profile" \
                || echo "arr-policy: FAILED to update ATLA release profile"
            fi
          fi
        fi

        # --- Delete the profiles Jellyseerr should not offer -----------------
        # Deliberately an explicit NAME list, not "everything unused": a
        # profile created later on purpose must not be silently destroyed.
        # Sonarr/Radarr refuse to delete a profile still in use, which is the
        # backstop if the reassignment above did not fully land.
        QP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/qualityprofile) || QP="[]"
        for NAME in "Any" "SD" "HD-720p" "HD-1080p" "Ultra-HD" "HD - 720p/1080p" "Any 1080p" "WEB-1080p" "WEB-2160p"; do
          PID=$(echo "$QP" | jq -r --arg n "$NAME" '.[]|select(.name==$n)|.id')
          if [ -n "$PID" ]; then
            curl -sf -m 15 -X DELETE -H "X-Api-Key: $SK" "$SONARR/api/v3/qualityprofile/$PID" >/dev/null \
              && echo "arr-policy: deleted Sonarr profile $NAME" \
              || echo "arr-policy: kept Sonarr profile $NAME (still in use)"
          fi
        done

        RQP=$(curl -sf -m 15 -H "X-Api-Key: $RK" $RADARR/api/v3/qualityprofile) || RQP="[]"

        # Radarr COLLECTIONS carry their own qualityProfileId, and Radarr
        # counts that as "in use" — so a profile with zero movies still
        # refuses to delete. Found 2026-08-23: 29 collections pinned to
        # "Remux + WEB 1080p" and 19 to "Remux + WEB 2160p", which is why
        # those two survived the first run. Repoint them at Asgard - Movies
        # before the delete loop below.
        MOVIE_P=$(echo "$RQP" | jq -r '.[]|select(.name=="Asgard - Movies")|.id')
        if [ -n "$MOVIE_P" ]; then
          COLS=$(curl -sf -m 30 -H "X-Api-Key: $RK" $RADARR/api/v3/collection) || COLS="[]"
          echo "$COLS" | jq -c '.[]' | while read -r C; do
            CID=$(echo "$C" | jq -r .id)
            CP=$(echo "$C" | jq -r .qualityProfileId)
            if [ "$CP" != "$MOVIE_P" ]; then
              echo "$C" | jq --argjson p "$MOVIE_P" '.qualityProfileId=$p' \
                | curl -sf -m 30 -X PUT -H "X-Api-Key: $RK" \
                       -H 'Content-Type: application/json' --data-binary @- \
                       "$RADARR/api/v3/collection/$CID" >/dev/null \
                && echo "arr-policy: collection $CID -> profile $MOVIE_P" \
                || echo "arr-policy: FAILED to move collection $CID"
            fi
          done
        fi

        for NAME in "Any" "SD" "HD-720p" "HD-1080p" "Ultra-HD" "HD - 720p/1080p" "Remux + WEB 1080p" "Remux + WEB 2160p"; do
          PID=$(echo "$RQP" | jq -r --arg n "$NAME" '.[]|select(.name==$n)|.id')
          if [ -n "$PID" ]; then
            curl -sf -m 15 -X DELETE -H "X-Api-Key: $RK" "$RADARR/api/v3/qualityprofile/$PID" >/dev/null \
              && echo "arr-policy: deleted Radarr profile $NAME" \
              || echo "arr-policy: kept Radarr profile $NAME (still in use)"
          fi
        done

        # --- Jellyfin: make English actually play ----------------------------
        # PlayDefaultAudioTrack=true makes Jellyfin honour the file's default
        # track and IGNORE AudioLanguagePreference entirely. Most anime here
        # ships with Japanese (JUJUTSU KAISEN: French) flagged default, so
        # accounts with a preference set were still getting subs. Rhys is
        # skipped - already configured correctly and left as the control.
        USERS=$(curl -sf -m 15 -H "X-Emby-Token: $JK" $JELLYFIN/Users) || USERS="[]"
        echo "$USERS" | jq -c '.[]' | while read -r U; do
          UNAME=$(echo "$U" | jq -r .Name)
          [ "$UNAME" = "Rhys" ] && continue
          UID_J=$(echo "$U" | jq -r .Id)
          CUR_A=$(echo "$U" | jq -r '.Configuration.AudioLanguagePreference // ""')
          CUR_D=$(echo "$U" | jq -r '.Configuration.PlayDefaultAudioTrack')
          if [ "$CUR_A" != "eng" ] || [ "$CUR_D" != "false" ]; then
            echo "$U" | jq '.Configuration | .AudioLanguagePreference="eng" | .PlayDefaultAudioTrack=false' \
              | curl -sf -m 15 -X POST -H "X-Emby-Token: $JK" \
                     -H 'Content-Type: application/json' --data-binary @- \
                     "$JELLYFIN/Users/$UID_J/Configuration" >/dev/null \
              && echo "arr-policy: Jellyfin user $UNAME -> eng / no default-track override" \
              || echo "arr-policy: FAILED to update Jellyfin user $UNAME"
          fi
        done

        echo "arr-policy: done"
      '';
    };

    # Jellyfin ships with TheMovieDb as the only TV provider, and TMDB models
    # some anime as ONE long season: JUJUTSU KAISEN is a single "Season 1" of
    # 59 episodes there, while TVDB (and therefore Sonarr, and therefore the
    # folder layout) splits the same 59 into 24 / 23 / 12. Jellyfin then looks
    # up "Season 2, Episode 1", finds nothing in TMDB, and degrades badly:
    # no season posters at all, and 300x169 / 9 KB episode thumbnails against
    # 1920x1080 for season 1. Adding TheTVDB fixes every season TMDB cannot
    # describe. Found 2026-08-28.
    #
    # TheTVDB is added BELOW TheMovieDb everywhere, deliberately — TMDB stays
    # authoritative so nothing that already looks right can change, and TVDB
    # only fills the gaps. But it must sit ABOVE "The Open Movie Database",
    # "Embedded Image Extractor" and "Screen Grabber" in the episode image
    # order: those are what were producing the 300x169 images, so a TVDB entry
    # below them would never win.
    #
    # EnableEmbeddedTitles is forced off. It is on by default and makes
    # Jellyfin take the episode name from the mkv container title tag, which
    # release groups stuff with their own naming — the JJK season 2/3 files
    # carry titles like "Jujutsu Kaisen (2023) - S02E01 - Hidden Inventory"
    # and "[AnoZu] JUJUTSU KAISEN - S03E01 - Execution", and those were being
    # shown verbatim in the UI. Season 1's files happen to have an empty title
    # tag, which is the only reason that season looked correct.
    systemd.services.jellyfin-providers = {
      description = "Install TheTVDB and pin Jellyfin TV metadata/image provider order";
      after    = [ "jellyfin.service" "network-online.target" ];
      wants    = [ "jellyfin.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq pkgs.coreutils pkgs.systemd ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -u
        JF=http://localhost:8096
        JK=$(cat ${config.sops.secrets."jellyfin-api-key".path})
        AUTH="Authorization: MediaBrowser Token=$JK"

        wait_for_jf() {
          for _ in $(seq 1 60); do
            curl -sf -m 5 -H "$AUTH" $JF/System/Info >/dev/null && return 0
            sleep 5
          done
          return 1
        }

        wait_for_jf || { echo "jellyfin-providers: Jellyfin never came up - skipping"; exit 0; }

        # --- TheTVDB plugin ------------------------------------------------
        # Installing it needs a restart before the fetcher becomes selectable,
        # so do that first and re-wait. Guarded so this is a no-op after the
        # first successful run.
        if ! curl -sf -m 15 -H "$AUTH" $JF/Plugins | jq -e '.[]|select(.Name=="TheTVDB")' >/dev/null; then
          # Pick the newest catalogue version whose targetAbi the running
          # server satisfies, rather than pinning a version that will rot.
          SRV=$(curl -sf -m 15 -H "$AUTH" $JF/System/Info | jq -r .Version)
          PKG=$(curl -sf -m 30 -H "$AUTH" $JF/Packages | jq -r --arg s "$SRV" '
            def norm: split(".")|map(tonumber)|(.+[0,0,0,0])[0:4];
            .[] | select(.name=="TheTVDB")
            | .guid as $g
            | [ .versions[] | select((.targetAbi|norm) <= ($s|norm)) ][0]
            | select(.!=null) | "\(.version) \($g)"')
          if [ -n "$PKG" ]; then
            set -- $PKG
            if curl -sf -m 60 -X POST -H "$AUTH" \
                 "$JF/Packages/Installed/TheTVDB?version=$1&assemblyGuid=$2" >/dev/null; then
              echo "jellyfin-providers: installed TheTVDB $1, restarting Jellyfin"
              sleep 10
              systemctl restart jellyfin
              wait_for_jf || { echo "jellyfin-providers: Jellyfin did not return after restart"; exit 0; }
            else
              echo "jellyfin-providers: FAILED to install TheTVDB"
            fi
          else
            echo "jellyfin-providers: no TheTVDB build compatible with $SRV"
          fi
        fi

        # --- Library options -----------------------------------------------
        VF=$(curl -sf -m 15 -H "$AUTH" $JF/Library/VirtualFolders) || exit 0
        echo "$VF" | jq -c '.[]|select(.CollectionType=="tvshows")' | while read -r LIB; do
          NAME=$(echo "$LIB" | jq -r .Name)
          WANT=$(echo "$LIB" | jq -c '{Id:.ItemId, LibraryOptions:(.LibraryOptions
            | .EnableEmbeddedTitles=false
            | .TypeOptions|=map(
                if .Type=="Series" then
                  .MetadataFetchers=["TheMovieDb","TheTVDB","The Open Movie Database"]
                  | .MetadataFetcherOrder=["TheMovieDb","TheTVDB","The Open Movie Database"]
                  | .ImageFetchers=["TheMovieDb","TheTVDB"]
                  | .ImageFetcherOrder=["TheMovieDb","TheTVDB"]
                elif .Type=="Season" then
                  .MetadataFetchers=["TheMovieDb","TheTVDB"]
                  | .MetadataFetcherOrder=["TheMovieDb","TheTVDB"]
                  | .ImageFetchers=["TheMovieDb","TheTVDB"]
                  | .ImageFetcherOrder=["TheMovieDb","TheTVDB"]
                elif .Type=="Episode" then
                  .MetadataFetchers=["TheMovieDb","TheTVDB","The Open Movie Database"]
                  | .MetadataFetcherOrder=["TheMovieDb","TheTVDB","The Open Movie Database"]
                  | .ImageFetchers=["TheMovieDb","TheTVDB","The Open Movie Database","Embedded Image Extractor","Screen Grabber"]
                  | .ImageFetcherOrder=["TheMovieDb","TheTVDB","The Open Movie Database","Embedded Image Extractor","Screen Grabber"]
                else . end))}')
          # Only POST when something actually differs — this unit runs on every
          # boot and a no-op must stay a no-op.
          CUR=$(echo "$LIB" | jq -c '{Id:.ItemId, LibraryOptions:.LibraryOptions}')
          if [ "$CUR" != "$WANT" ]; then
            echo "$WANT" | curl -sf -m 30 -X POST -H "$AUTH" \
                   -H 'Content-Type: application/json' --data-binary @- \
                   "$JF/Library/VirtualFolders/LibraryOptions" >/dev/null \
              && echo "jellyfin-providers: updated provider order on library $NAME" \
              || echo "jellyfin-providers: FAILED to update library $NAME"
          fi
        done

        echo "jellyfin-providers: done"
      '';
    };


    systemd.services.decluttarr-config = {
      description = "Generate Decluttarr YAML config from sops secrets";
      wantedBy = [ "podman-decluttarr.service" ];
      before   = [ "podman-decluttarr.service" ];
      partOf   = [ "podman-decluttarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/decluttarr/config
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        LIDARR_KEY=$(cat ${config.sops.secrets."lidarr-api-key".path})
        SABNZBD_KEY=$(cat ${config.sops.secrets."sabnzbd-api-key".path})
        cat > /var/lib/decluttarr/config/config.yaml << EOF
instances:
  sonarr:
    - base_url: http://host.containers.internal:8989
      api_key: $SONARR_KEY
  radarr:
    - base_url: http://host.containers.internal:7878
      api_key: $RADARR_KEY
  lidarr:
    - base_url: http://host.containers.internal:8686
      api_key: $LIDARR_KEY
download_clients:
  sabnzbd:
    - name: SABnzbd
      base_url: http://host.containers.internal:8080
      api_key: $SABNZBD_KEY
jobs:
  remove_stalled: true
  remove_failed_imports: true
  remove_failed_downloads: true
  remove_metadata_missing: true
  remove_orphans: false
EOF
        chmod 600 /var/lib/decluttarr/config/config.yaml
      '';
    };

    virtualisation.oci-containers.containers.decluttarr = {
      image = "ghcr.io/manimatter/decluttarr:latest";
      volumes = [ "/var/lib/decluttarr/config:/app/config" ];
      autoStart = true;
    };


# ══════════════════════════════════════════════════════════════════════════════
# NETWORKING — Tailscale VPN + Cloudflare Tunnel
# Native NixOS services (not containers).
#
# Tailscale: run `sudo tailscale up` after first boot to authenticate.
#
# Cloudflare tunnel setup (one-time before first build):
#   1. dash.cloudflare.com → Zero Trust → Networks → Tunnels → Create tunnel
#   2. Name it "asgard", copy the Tunnel UUID shown on the detail page
#   3. Download/copy the credentials JSON shown during creation
#   4. sops ~/Dots/Secrets/secrets.yaml
#        cloudflare-tunnel: '<full credentials JSON>'
#   5. Replace TUNNEL-UUID-HERE below with the actual UUID
#
# Public URLs (bifrost-vault.com):
#   jellyfin.bifrost-vault.com  → localhost:8096
#   requests.bifrost-vault.com  → localhost:5055
#   photos.bifrost-vault.com    → localhost:2283
# ══════════════════════════════════════════════════════════════════════════════

    # --- Tailscale ---
    services.tailscale = {
      enable = true;
      openFirewall = true;
    };

    # Tailscale status API proxy — exposes node status for Glance dashboard
    # Queries tailscaled Unix socket and serves JSON on localhost:9553
    systemd.services.tailscale-status-proxy = {
      description = "Tailscale status HTTP proxy for Glance";
      after = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.curl pkgs.jq pkgs.python3 ];
      script = ''
        python3 -c '
import http.server, subprocess, json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            raw = subprocess.check_output([
                "curl", "-sf", "--unix-socket",
                "/var/run/tailscale/tailscaled.sock",
                "http://local-tailscaled.sock/localapi/v0/status"
            ])
            data = json.loads(raw)
            result = {
                "self": {
                    "name": data["Self"]["HostName"],
                    "ip": data["Self"]["TailscaleIPs"][0],
                    "online": data["Self"]["Online"]
                },
                "peers": [
                    {
                        "name": p["HostName"],
                        "ip": p["TailscaleIPs"][0] if p.get("TailscaleIPs") else "",
                        "online": p.get("Online", False)
                    }
                    for p in data.get("Peer", {}).values()
                ]
            }
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(result).encode())
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())
    def log_message(self, *args):
        pass

http.server.HTTPServer(("127.0.0.1", 9553), Handler).serve_forever()
        '
      '';
      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
      };
    };

    # Eclipse control endpoint — button panel + status JSON, embedded in Glance
    # as an iframe. Drives the LibreELEC TV box (100.80.62.3) over SSH.
    #
    # SSH not Kodi JSON-RPC on purpose: the headline action is "restart Kodi when
    # it has wedged", and a wedged Kodi cannot answer its own API. Kodi's HTTP
    # server is disabled on Eclipse anyway. See Claude/eclipse.md.
    # LAN data sink for the Eclipse speed test, scoped to the LAN interface.
    #
    # The panel itself (9554) stays OFF the LAN deliberately — it carries every
    # /act/ verb including `reboot`, and tailscale0 being a trustedInterface is
    # what keeps it reachable to us and nobody else. 9557 serves a zero-filled
    # payload and nothing else (SpeedtestHandler in eclipse-control.py), so the
    # worst anything on the wifi can do with it is waste bandwidth.
    #
    # Needed because a LAN speed test has to talk to a LAN-reachable port: the
    # test used to always run over Tailscale and reported ~19 Mbps of WireGuard
    # overhead even with Jellyfin in LAN mode.
    networking.firewall.interfaces."enp3s0".allowedTCPPorts = [ 9557 ];

    systemd.services.eclipse-control = {
      description = "Eclipse (LibreELEC) control endpoint for Glance";
      after = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.openssh ];
      environment = {
        ECLIPSE_HOST = "100.80.62.3";
        ECLIPSE_KEY = config.sops.secrets."eclipse-ssh-key".path;
        ECLIPSE_PORT = "9554";
        # Glance renders in JetBrains Mono but embeds the font in its Go binary
        # and lives on another port, so the iframe can't borrow it cross-origin.
        # Serve our own copy to keep the panel typographically native.
        ECLIPSE_FONT_DIR = "${pkgs.jetbrains-mono}/share/fonts/WOFF2";
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../../Resources/Eclipse-Control/eclipse-control.py}";
        Restart = "always";
        RestartSec = 5;
      };
    };

    # ── Internet speed test ─────────────────────────────────────────────────────
    # Ookla's official CLI, not speedtest-cli/librespeed — it is the number the
    # ISP will actually argue about, and it needs no server-list curation.
    #
    # Reading the result: DOWNLOAD is the honest line rate. UPLOAD is not — every
    # WAN-bound packet goes through the 30 Mbit htb class in wan-egress-shaping
    # below, so this reports ~30 on a 50 Mbit uplink **by design**. The widget
    # says so next to the figure; don't go hunting for a broken uplink.
    #
    # The download figure is only honest because the run pauses SABnzbd first
    # (see the script). Ookla measures whatever capacity is spare, so before that
    # was added the timer happily fired mid-download and published the leftovers:
    # 47.8 Mb/s against 421 on the same link twenty seconds later.
    systemd.services.speedtest = {
      description = "Internet speed test (Ookla) → /var/lib/speedtest/latest.json";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        # Not optional. The CLI does std::string(getenv("HOME")) unguarded, so
        # with no HOME it aborts on `basic_string::_M_construct null not valid`
        # and dumps core before it ever touches the network. It keeps its
        # license-acceptance flag under $HOME/.config/ookla.
        HOME = "/var/lib/speedtest";
      };
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "speedtest";
        # A test takes ~30s, plus 11s of settling before it; a hung one must not
        # wedge the timer forever.
        TimeoutStartSec = "5m";
        # The queue is resumed here rather than at the end of the script so it
        # happens on *any* stop — including the unit being killed on
        # TimeoutStartSec, which is exactly the case where a script-level trap
        # would be least reliable. The marker is what authorises the resume, so a
        # queue that was already paused by hand is never silently restarted.
        ExecStopPost = pkgs.writeShellScript "speedtest-resume-sab" ''
          [ -e /var/lib/speedtest/.sab-paused ] || exit 0
          ${pkgs.coreutils}/bin/rm -f /var/lib/speedtest/.sab-paused
          key=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."sabnzbd-api-key".path})
          ${pkgs.curl}/bin/curl -fsS --max-time 10 \
            "http://localhost:8080/api?apikey=$key&output=json&mode=resume" >/dev/null
        '';
      };
      # Written to a temp file and renamed, so a failed or half-written run never
      # replaces a good result — the panel keeps showing the last known-good one.
      script = ''
        out=/var/lib/speedtest/latest.json
        tmp=$(${pkgs.coreutils}/bin/mktemp /var/lib/speedtest/.latest.XXXXXX)
        raw=$(${pkgs.coreutils}/bin/mktemp /var/lib/speedtest/.raw.XXXXXX)

        # Ookla measures spare capacity, not link capacity, so the line has to be
        # quiet or the result is meaningless — SABnzbd alone will happily sit on
        # 245 Mb/s of a 425 Mb/s link and drag the figure down to a fifth of it.
        #
        # set_pause is a pause with a deadline: if this unit dies hard enough
        # that ExecStopPost never runs, SAB resumes by itself after 6 minutes
        # (one past TimeoutStartSec), so a failure here can never strand the
        # queue. Every step fails open — no key, no SAB, no answer, no pause, and
        # the test still runs.
        #
        # The marker is deliberately not cleared here. One left behind means a
        # previous run was killed before ExecStopPost, so letting it survive into
        # this run is what gets the queue resumed at the end of it.
        key=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."sabnzbd-api-key".path} || true)
        sab="http://localhost:8080/api?apikey=$key&output=json"
        if ${pkgs.curl}/bin/curl -fsS --max-time 10 "$sab&mode=queue" \
             | ${pkgs.gnugrep}/bin/grep -q '"paused":false'; then
          if ${pkgs.curl}/bin/curl -fsS --max-time 10 \
               "$sab&mode=config&name=set_pause&value=6" >/dev/null; then
            ${pkgs.coreutils}/bin/touch /var/lib/speedtest/.sab-paused
          fi
        fi

        # Let the in-flight NNTP connections drain, then log what is *still* on
        # the wire. SAB is the only thing this unit can pause; if a Jellyfin
        # stream or an arr import is running, the figures below are leftovers
        # again and this line is the only way to tell after the fact.
        ${pkgs.coreutils}/bin/sleep 8
        rx1=$(${pkgs.coreutils}/bin/cat /sys/class/net/enp3s0/statistics/rx_bytes)
        ${pkgs.coreutils}/bin/sleep 3
        rx2=$(${pkgs.coreutils}/bin/cat /sys/class/net/enp3s0/statistics/rx_bytes)
        echo "background traffic at test start: $(( (rx2 - rx1) * 8 / 3 / 1000000 )) Mb/s down"

        if ${lib.getExe pkgs.ookla-speedtest} \
             --format=json --accept-license --accept-gdpr > "$raw"; then
          # On the first run of a fresh machine the EULA goes to stdout *ahead*
          # of the JSON, so this takes the result line rather than the whole
          # stream — otherwise latest.json is a licence notice.
          ${pkgs.gnugrep}/bin/grep -m1 '^{' "$raw" > "$tmp" || true
        fi

        if [ -s "$tmp" ]; then
          ${pkgs.coreutils}/bin/mv "$tmp" "$out"
          ${pkgs.coreutils}/bin/rm -f "$raw"
        else
          ${pkgs.coreutils}/bin/rm -f "$tmp" "$raw"
          exit 1
        fi
      '';
    };

    systemd.timers.speedtest = {
      description = "Run an internet speed test every 6 hours";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00/6:05:00";
        # Catch up after downtime, so the panel is never showing a result from
        # before the last reboot with no explanation.
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };

    # ── Network panel endpoint (port 9555, Tailscale-only) ─────────────────────
    # Backs the Network group on the Glance main page: live throughput sampled
    # from /proc/net/dev plus the last speed-test result, and a POST /run that
    # triggers a fresh test from the "Run now" button.
    #
    # Replaced `flow` inside a second read-only ttyd on :7682. ttyd kills its
    # child whenever the websocket drops — a backgrounded tab was enough — and
    # xterm.js then painted its reconnect banner over the panel, which is what it
    # spent most of its life showing. See Resources/Network-Panel/network-panel.py.
    #
    # Runs as root purely so POST /run can `systemctl start speedtest.service`.
    # It is not exposed beyond the tailnet: 9555 is deliberately absent from
    # allowedTCPPorts and only reachable via trusted tailscale0.
    systemd.services.network-panel = {
      description = "Network throughput + speed test endpoint for Glance";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.systemd ];
      environment = {
        NETPANEL_IFACE = "enp3s0";
        NETPANEL_PORT = "9555";
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../../Resources/Network-Panel/network-panel.py}";
        Restart = "always";
        RestartSec = 5;
      };
    };

    # mergerfs provides mount.fuse.mergerfs, needed to mount the /data/media pool (see below)
    environment.systemPackages = [ pkgs.kitty.terminfo pkgs.mergerfs pkgs.tmux ];

    # Intel QSV / VAAPI runtime for Jellyfin hardware transcoding (UHD 730 / Gen13).
    # Without these, ffmpeg's "vaapi=va:/dev/dri/renderD128,driver=iHD" fails with
    # "unknown libva error" and clients see "fatal playback error".
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver        # iHD VAAPI driver (required by QSV)
        intel-compute-runtime     # OpenCL — needed for tonemapping filters
        vpl-gpu-rt                # Intel oneVPL runtime (modern QSV)
        libvdpau-va-gl
      ];
    };

    services.cloudflared = {
      enable = true;
      tunnels = {
        "804d54a8-e7ad-4f34-812d-3052cf862c47" = {
          credentialsFile = config.sops.secrets."cloudflare-tunnel".path;
          default = "http_status:404";
          ingress = {
            "jellyfin.bifrost-vault.com"  = "http://localhost:8096";
            "requests.bifrost-vault.com"  = "http://localhost:5055";
            "photos.bifrost-vault.com"    = "http://localhost:2283";
          };
        };
      };
    };

    # ── Mullvad VPN namespace for SABnzbd ──────────────────────────────────────
    # Creates an isolated network namespace with a WireGuard tunnel to Mullvad.
    # SABnzbd runs inside this namespace — all Usenet traffic goes through the VPN.
    # A veth pair bridges the namespace to the host so the SABnzbd web UI (port 8080)
    # remains accessible from Tailscale/LAN.
    #
    # If the VPN goes down, SABnzbd has no network — acts as a kill switch.

    # 1. Create the "vpn" network namespace
    systemd.services."netns-vpn" = {
      description = "VPN network namespace";
      before = [ "network.target" "wg-mullvad.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.iproute2}/bin/ip netns add vpn";
        ExecStop = "${pkgs.iproute2}/bin/ip netns del vpn";
      };
    };

    # 2. WireGuard interface inside the namespace
    systemd.services.wg-mullvad = {
      description = "WireGuard tunnel (Mullvad) in vpn namespace";
      bindsTo = [ "netns-vpn.service" ];
      requires = [ "network-online.target" ];
      after = [ "netns-vpn.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        # Create WireGuard interface and move it into the namespace
        ${pkgs.iproute2}/bin/ip link add wg0 type wireguard
        ${pkgs.iproute2}/bin/ip link set wg0 netns vpn

        # Configure WireGuard with Mullvad credentials
        ${pkgs.iproute2}/bin/ip netns exec vpn \
          ${pkgs.wireguard-tools}/bin/wg set wg0 \
            private-key ${config.sops.secrets."mullvad-wg-private-key".path} \
            peer 4JpfHBvthTFOhCK0f5HAbzLXAVcB97uAkuLx7E8kqW0= \
            allowed-ips 0.0.0.0/0,::/0 \
            endpoint 146.70.200.2:51820 \
            persistent-keepalive 25

        # Assign addresses and bring up
        ${pkgs.iproute2}/bin/ip -n vpn address add 10.66.10.54/32 dev wg0
        ${pkgs.iproute2}/bin/ip -n vpn -6 address add fc00:bbbb:bbbb:bb01::3:a35/128 dev wg0
        ${pkgs.iproute2}/bin/ip -n vpn link set wg0 up
        ${pkgs.iproute2}/bin/ip -n vpn route add default dev wg0
        ${pkgs.iproute2}/bin/ip -n vpn -6 route add default dev wg0

        # Bring up loopback inside namespace
        ${pkgs.iproute2}/bin/ip -n vpn link set lo up
      '';
      preStop = ''
        ${pkgs.iproute2}/bin/ip -n vpn link del wg0 || true
      '';
    };

    # 3. Veth pair — bridges SABnzbd web UI from vpn namespace to host
    #    Host side: veth-vpn-br 10.200.1.1/24
    #    VPN side:  veth-vpn    10.200.1.2/24
    systemd.services.veth-vpn = {
      description = "Veth bridge to vpn namespace (SABnzbd web UI)";
      bindsTo = [ "wg-mullvad.service" ];
      after = [ "wg-mullvad.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        ${pkgs.iproute2}/bin/ip link add veth-vpn-br type veth peer name veth-vpn
        ${pkgs.iproute2}/bin/ip link set veth-vpn netns vpn

        # Host side
        ${pkgs.iproute2}/bin/ip address add 10.200.1.1/24 dev veth-vpn-br
        ${pkgs.iproute2}/bin/ip link set veth-vpn-br up

        # VPN namespace side
        ${pkgs.iproute2}/bin/ip -n vpn address add 10.200.1.2/24 dev veth-vpn
        ${pkgs.iproute2}/bin/ip -n vpn link set veth-vpn up

        # Allow namespace to reach host (for arr API callbacks)
        ${pkgs.iproute2}/bin/ip netns exec vpn \
          ${pkgs.iproute2}/bin/ip route add 10.200.1.1/32 dev veth-vpn
      '';
      preStop = ''
        ${pkgs.iproute2}/bin/ip link del veth-vpn-br || true
      '';
    };

    # 3b. socat proxy — exposes SABnzbd (inside vpn namespace) on host port 8080
    # All access goes through this: web UI, arr callbacks, Glance's queue
    # widgets, Tailscale.
    systemd.services.sabnzbd-proxy = {
      description = "SABnzbd proxy (host:8080 → vpn namespace)";
      bindsTo = [ "veth-vpn.service" ];
      after = [ "veth-vpn.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:8080,fork,reuseaddr,bind=0.0.0.0 TCP:10.200.1.2:8080";
        Restart = "always";
        RestartSec = 2;
      };
    };

    # 4. DNS inside the vpn namespace — Mullvad's DNS server
    environment.etc."netns/vpn/resolv.conf".text = "nameserver 10.64.0.1\n";

    # 4b. WG watchdog — wg-mullvad is a oneshot, so when Mullvad's peer route
    # flaps it doesn't recover on its own (SAB sees "No route to host" until
    # the upstream heals minutes later). This pings the VPN gateway every 60s
    # inside the netns and restarts wg-mullvad on 3 consecutive failures.
    systemd.services.wg-mullvad-watchdog = {
      description = "Restart wg-mullvad when tunnel unreachable";
      after = [ "wg-mullvad.service" ];
      wants = [ "wg-mullvad.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Restart = "always";
        RestartSec = 30;
      };
      script = ''
        FAILS=0
        while true; do
          if ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iputils}/bin/ping -c1 -W3 10.64.0.1 > /dev/null 2>&1; then
            FAILS=0
          else
            FAILS=$((FAILS + 1))
            echo "wg-mullvad ping failed ($FAILS/3)"
            if [ "$FAILS" -ge 3 ]; then
              echo "wg-mullvad unreachable — restarting tunnel"
              ${pkgs.systemd}/bin/systemctl restart wg-mullvad.service
              FAILS=0
              sleep 30
            fi
          fi
          sleep 60
        done
      '';
    };

    # 5. Bind SABnzbd to the vpn namespace
    systemd.services.sabnzbd = {
      bindsTo = [ "wg-mullvad.service" ];
      after = [ "veth-vpn.service" "wg-mullvad.service" ];
      serviceConfig = {
        PrivateNetwork = lib.mkForce false;  # disable nixflix's PrivateNetwork — we use NetworkNamespacePath instead
        NetworkNamespacePath = "/var/run/netns/vpn";
        BindReadOnlyPaths = [ "/etc/netns/vpn/resolv.conf:/etc/resolv.conf" ];
      };
    };



# ══════════════════════════════════════════════════════════════════════════════
# UTILITIES — File Browser
# Port 8081: FileBrowser — full filesystem browser (downloads, media, photos)
#   Credentials managed via sops: admin-username / admin-password
#   filebrowser-credentials.service syncs them on every boot.
# Tailscale-only, not exposed via Cloudflare tunnel.
# ══════════════════════════════════════════════════════════════════════════════

    # Always writes config.yaml on every rebuild — port and sources are
    # infrastructure, not user settings. User prefs live in the database.
    systemd.services.filebrowser-init = {
      description = "Write FileBrowser Quantum config";
      before   = [ "podman-filebrowser.service" ];
      wantedBy = [ "podman-filebrowser.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/filebrowser
        printf 'server:\n  port: 8080\n  sources:\n    - path: /downloads\n      name: downloads\n    - path: /media\n      name: media\n    - path: /photos\n      name: photos\n' \
          > /var/lib/filebrowser/config.yaml
      '';
    };

    virtualisation.oci-containers.containers.filebrowser = {
      image = "ghcr.io/gtsteffaniak/filebrowser:latest";
      ports = [ "8081:8080" ];
      volumes = [
        "/downloads:/downloads"
        "/data/media:/media"
        "/data/photos:/photos"
        "/var/lib/filebrowser:/home/filebrowser/data"
      ];
      user = "root";
      autoStart = true;
    };

    # Syncs admin credentials from sops on every boot.
    # Tries the sops password first (handles already-changed installs),
    # then falls back to "admin" (handles first run with default password).
    systemd.services.filebrowser-credentials = {
      description = "Seed FileBrowser admin credentials from sops";
      after    = [ "podman-filebrowser.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        USERNAME=$(cat ${config.sops.secrets."admin-username".path})
        PASSWORD=$(cat ${config.sops.secrets."admin-password".path})
        BASE="http://localhost:8081"

        # Wait up to 60s for FileBrowser to accept connections
        for i in $(seq 1 30); do
          if curl -s "$BASE" > /dev/null 2>&1; then break; fi
          echo "Waiting for FileBrowser... ($i/30)"
          sleep 2
        done

        # Authenticate — try sops password first, fall back to default "admin"
        # || true on every jq call prevents set -e from exiting on parse errors
        TOKEN=""
        for CURRENT_PASS in "$PASSWORD" "admin"; do
          RESP=$(curl -s -X POST "$BASE/api/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"admin\",\"password\":\"$CURRENT_PASS\"}" 2>/dev/null) || true
          TOKEN=$(printf '%s' "$RESP" | jq -r '.token // empty' 2>/dev/null) || true
          [ -n "$TOKEN" ] && break
        done

        if [ -z "$TOKEN" ]; then
          echo "FileBrowser: could not authenticate — skipping credential sync" >&2
          exit 0
        fi

        # Fetch current user object, patch username + password, write back
        USER_DATA=$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE/api/users/1" 2>/dev/null) || true
        UPDATED=$(printf '%s' "$USER_DATA" | jq \
          --arg u "$USERNAME" --arg p "$PASSWORD" \
          '.username = $u | .password = $p' 2>/dev/null) || true

        if [ -z "$UPDATED" ]; then
          echo "FileBrowser: could not build update payload — skipping" >&2
          exit 0
        fi

        curl -s -X PUT "$BASE/api/users/1" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "$UPDATED" > /dev/null

        echo "FileBrowser credentials synced (user: $USERNAME)."
      '';
    };


# ══════════════════════════════════════════════════════════════════════════════
# PHOTOS — Immich photo server
# Native NixOS module — manages its own PostgreSQL and Redis automatically.
# Public URL: photos.bifrost-vault.com (via Cloudflare tunnel)
# Port: 2283
# Post-boot: create admin account at http://localhost:2283 on first visit.
# ══════════════════════════════════════════════════════════════════════════════

    services.immich = {
      enable = true;
      mediaLocation = "/data/photos";
      host = "0.0.0.0";
      openFirewall = false;
    };

    # Immich 2.7+ expects .immich marker files in each subdirectory — create them
    # before the service starts so verifyReadAccess doesn't fail on fresh /data.
    systemd.services.immich-server.serviceConfig.ExecStartPre = lib.mkBefore [
      (pkgs.writeShellScript "immich-init-dirs" ''
        for dir in encoded-video thumbs upload backups library profile; do
          mkdir -p /data/photos/$dir
          touch /data/photos/$dir/.immich
        done
      '')
    ];

    # Seeds the Immich admin account from sops on first boot.
    # /api/auth/admin-signup is only available before any admin exists — idempotent.
    systemd.services.immich-admin-seed = {
      description = "Create Immich admin account from sops";
      after    = [ "immich-server.service" "network.target" ];
      wants    = [ "immich-server.service" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        USERNAME=$(cat ${config.sops.secrets."admin-username".path})
        PASSWORD=$(cat ${config.sops.secrets."admin-password".path})
        BASE="http://localhost:2283"

        # Wait up to 2 minutes for Immich
        for i in $(seq 1 24); do
          if curl -sf "$BASE/api/server/ping" > /dev/null 2>&1; then break; fi
          echo "Waiting for Immich... ($i/24)"
          sleep 5
        done

        CODE=$(curl -s -o /dev/null -w "%{http_code}" \
          -X POST "$BASE/api/auth/admin-signup" \
          -H "Content-Type: application/json" \
          -d "{\"email\":\"$USERNAME@asgard.local\",\"password\":\"$PASSWORD\",\"name\":\"$USERNAME\"}" 2>/dev/null) || true

        if [ "$CODE" = "201" ]; then
          echo "Immich admin created."
        elif [ "$CODE" = "400" ]; then
          echo "Immich admin already exists — skipping."
        else
          echo "Immich admin-signup returned HTTP $CODE" >&2
        fi
      '';
    };


# ══════════════════════════════════════════════════════════════════════════════
# DASHBOARD — Glance (port 8888) + ttyd web terminal (port 7681)
# ══════════════════════════════════════════════════════════════════════════════

    # ── Glance — native systemd service for host-level server-stats ──
    #
    # The SABnzbd API key reaches the Downloads widgets through Glance's
    # `readFileFromEnv` config variable: LoadCredential copies the 0400 sops
    # secret into this unit's private credentials dir (readable by the
    # DynamicUser, nobody else), SABNZBD_API_KEY_FILE points at it, and Glance
    # substitutes the file's contents when it loads the config. That keeps the
    # key out of the Nix store AND avoids making it world-readable — the 0444
    # trade-off `ha-token` has to make for its /run/secrets lookup would hand
    # full control of SABnzbd to every local user.
    #
    # ⚠ Glance resolves config variables at STARTUP and refuses to start if one
    # cannot be read, so a missing credential takes the whole dashboard down,
    # not just the two widgets.
    systemd.services.glance = {
      description = "Glance Dashboard";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment.SABNZBD_API_KEY_FILE = "/run/credentials/glance.service/sabnzbd-api-key";
      serviceConfig = {
        ExecStart = "${pkgs.glance}/bin/glance --config ${glanceConfig}";
        Restart = "on-failure";
        DynamicUser = true;
        LoadCredential = [ "sabnzbd-api-key:${config.sops.secrets."sabnzbd-api-key".path}" ];
      };
    };

    # ── ttyd — web terminal (port 7681, Tailscale-only) ─────────────────────────
    # Embedded as the "Terminal" page in Glance. Default entrypoint is `login`
    # (runs as root), so the browser gets a real login prompt — no unauthenticated
    # shell exposed to the tailnet.
    services.ttyd = {
      enable = true;
      port = 7681;
      writeable = true;
    };

    # ttyd sessions die when the browser tab loses focus or closes — the websocket
    # drops and ttyd kills the shell. Detect a ttyd-spawned shell by walking up the
    # process tree, then exec into a persistent tmux session: disconnecting then only
    # kills the tmux client, not the session, so reconnecting reattaches exactly where
    # it left off.
    #
    # This lives HERE, in the Asgard-only server module, and deliberately NOT in the
    # shared Modules/Shell/zsh.nix — that one is imported by every host and this behaviour is
    # only wanted on the server. `programs.zsh.initContent` is a `lines` option, so this
    # concatenates with the shared definition rather than replacing it.
    # tmux itself is installed via environment.systemPackages in this same module.
    home-manager.users.${activeUser}.programs.zsh.initContent = lib.mkAfter ''
      if [[ $- == *i* ]] && [[ -z "$TMUX" ]]; then
        __pid=$$
        for __i in 1 2 3 4 5 6; do
          __ppid=$(ps -o ppid= -p "$__pid" 2>/dev/null | tr -d ' ')
          [[ -z "$__ppid" || "$__ppid" -eq 1 ]] && break
          if [[ "$(ps -o comm= -p "$__ppid" 2>/dev/null)" == "ttyd" ]]; then
            exec tmux new-session -A -s ttyd
          fi
          __pid=$__ppid
        done
        unset __pid __ppid __i
      fi
    '';


# ══════════════════════════════════════════════════════════════════════════════
# INFRASTRUCTURE — Podman, media group, data directories, sops secrets
# ══════════════════════════════════════════════════════════════════════════════

    # --- Podman (OCI backend for the containers: Audiobookshelf, Shelfarr,
    # FlareSolverr, FileBrowser, Decluttarr). Glance is NOT one of them — it runs
    # as a native unit so server-stats can read the host's /proc and /sys. ---
    #
    # No dockerSocket: its only consumer was cAdvisor, removed along with the
    # rest of the metrics stack, and the socket is root-equivalent for anyone in
    # the podman group.
    virtualisation.oci-containers.backend = "podman";
    virtualisation.podman = {
      enable = true;
    };
    # Allow containers to reach host-bound services (arr, immich, etc.)
    # tailscale0 trusted so all services are reachable from any tailnet device by hostname
    # `veth-vpn-br` is the HOST side of the veth pair into the Mullvad namespace.
    # Without it trusted, the namespace can ping the host but every TCP connection
    # is dropped — which silently breaks any download client in the namespace that
    # has to fetch from a host service.
    #
    # Concretely: SABnzbd lives in that namespace, and Shelfarr's SAB adapter only
    # speaks `mode=addurl` — it hands SAB a Prowlarr URL and expects SAB to fetch
    # the NZB itself. SAB could not reach Prowlarr, so every book sat in the queue
    # at 0% showing "Fetch NZB from URL" with an exponentially growing WAIT and
    # never failed outright. Sonarr/Radarr are unaffected because they push the
    # NZB contents themselves rather than passing a URL.
    #
    # Safe: the only peer on this link is the VPN namespace, which contains just
    # SABnzbd and is not reachable from outside the host.
    networking.firewall.trustedInterfaces = [ "podman0" "cni-podman0" "tailscale0" "veth-vpn-br" ];
    networking.firewall.allowedTCPPorts = [
      8096 # Jellyfin — open to LAN so home devices connect directly (no CF tunnel / upload round-trip)
    ]; # everything else accessed via Tailscale (trustedInterfaces)

    # --- WAN egress shaping ---
    # Jellyfin's transcoder delivers segments in on/off bursts that momentarily
    # saturate the full 50 Mbit uplink (~180ms latency spikes every ~3s, which
    # rubber-bands game sessions on the LAN). Cap WAN-bound traffic at 30 Mbit
    # so it flows smoothly below line rate; LAN/tailnet destinations (RFC1918)
    # bypass the cap so local direct-play of high-bitrate remuxes is unaffected.
    systemd.services.wan-egress-shaping = {
      description = "Cap WAN-bound upload at 30 Mbit (smooth Jellyfin transcode bursts)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        tc=${pkgs.iproute2}/bin/tc
        dev=enp3s0
        # htb doesn't support in-place change, so "replace" fails on an existing
        # root — tear down and rebuild from scratch (also clears classes/filters)
        $tc qdisc del dev $dev root 2>/dev/null || true
        $tc qdisc add dev $dev root handle 1: htb default 20
        $tc class add dev $dev parent 1: classid 1:1 htb rate 940mbit
        $tc class add dev $dev parent 1:1 classid 1:10 htb rate 910mbit ceil 940mbit
        # burst/cburst explicit — htb's auto-computed default at this rate is
        # ~1600 bytes (one packet), which sounds harmless but isn't: it means
        # every burst above a single packet gets throttled by the token
        # bucket itself, not just rate-limited on average. Discovered
        # 2026-09-11 chasing Eclipse's remote Jellyfin playback "plays a
        # chunk, stalls, plays a chunk" stutter — `tc -s class show` had 190M
        # cumulative overlimits and a token count sitting in permanent
        # deficit. 300KB (~80ms at 30 Mbit) lets Kodi's aggressive read-ahead
        # bursts (filecache readfactor 20x, see Claude/eclipse.md) through
        # smoothly while the long-run average is still capped at 30 Mbit.
        $tc class add dev $dev parent 1:1 classid 1:20 htb rate 30mbit ceil 30mbit burst 300k cburst 300k
        $tc qdisc add dev $dev parent 1:20 fq_codel
        $tc filter add dev $dev parent 1: protocol ip prio 1 u32 match ip dst 192.168.0.0/16 flowid 1:10
        $tc filter add dev $dev parent 1: protocol ip prio 1 u32 match ip dst 10.0.0.0/8 flowid 1:10
        $tc filter add dev $dev parent 1: protocol ip prio 1 u32 match ip dst 172.16.0.0/12 flowid 1:10
      '';
    };

    # DNS inside the VPN namespace (SABnzbd's sandbox) fails due to routing
    # conflicts. Bypass it entirely for the usenet server — /etc/hosts is read
    # first (nsswitch: files before dns), so getaddrinfo() never touches DNS.
    # IPs confirmed reachable via the Mullvad tunnel on port 563.
    networking.hosts = {
      "45.125.247.68"  = [ "aunews.frugalusenet.com" ];
      "45.125.247.108" = [ "aunews.frugalusenet.com" ];
      "85.12.62.251"   = [ "news.newshosting.com" ];
    };

    # IP forwarding — required for veth NAT (SABnzbd web UI from vpn namespace)
    boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault true;

    # --- Claude Code auth ---
    # OAuth credentials live in ~/.claude/.credentials.json (set up via `claude login`).
    # managed-settings intentionally left empty so OAuth takes precedence.

    # --- Shared media group (GID 1001) ---
    # All service users and containers use this group for /data/media access.
    users.groups.media = { gid = 1001; };
    users.users.${activeUser}.extraGroups = [ "media" ];
    users.users.jellyfin.extraGroups = [ "media" "render" "video" ];

    # ══════════════════════════════════════════════════════════════════════════
    # Storage pool — mergerfs unites the 8TB + 12TB into one /data/media
    # ══════════════════════════════════════════════════════════════════════════
    #
    #   /mnt/disk1   8TB  ext4   ─┐
    #                             ├─ mergerfs ──> /data/media
    #   /mnt/disk2   12TB ext4   ─┘
    #
    #   /data/photos  <- bind /mnt/disk1/photos   (Immich)
    #   /data/.state  <- bind /mnt/disk1/.state   (arr SQLite DBs)
    #
    # mergerfs is a UNION filesystem: it merges the directory tree, not blocks. Every file lives
    # whole on exactly one disk, and the pool is a single namespace so each file appears exactly
    # once. Losing a drive costs only that drive's files — the survivor keeps serving. This is
    # why mergerfs and NOT LVM/btrfs-single/RAID0, which span one filesystem across both spindles
    # and lose everything if either disk dies.
    #
    # Only MEDIA is pooled. The arr databases (/data/.state) and Immich's library (/data/photos)
    # stay on real ext4 via bind mounts — SQLite on FUSE is a known source of locking corruption,
    # and those two are only ~3.8G combined, so there is no capacity reason to pool them.
    #
    # Every service path is unchanged by this: nixflix mediaDir/stateDir, the container bind
    # mounts, immich mediaLocation and the tmpfiles rules below all still point at /data/...
    #
    # NOTE: /mnt/disk2/media must exist before the pool can mount — mergerfs errors on a missing
    # branch, and tmpfiles runs too late to help. It was created by hand at install time.
    # (pkgs.mergerfs is added to environment.systemPackages above, next to kitty.terminfo)
    programs.fuse.userAllowOther = true;  # required for allow_other

    fileSystems."/data/media" = {
      device = "/mnt/disk1/media:/mnt/disk2/media";
      fsType = "fuse.mergerfs";
      options = [
        "category.create=mfs"   # new files -> branch with most free space (the 12TB)
        "moveonenospc=true"     # branch fills mid-write -> relocate rather than ENOSPC
        "minfreespace=50G"      # stop choosing a branch below this
        "cache.files=partial"
        "dropcacheonclose=true"
        "allow_other"           # podman containers + non-root services must read it
        "fsname=mediapool"
        "nofail"
        "x-systemd.requires-mounts-for=/mnt/disk1"
        "x-systemd.requires-mounts-for=/mnt/disk2"
      ];
    };

    fileSystems."/data/photos" = {
      device = "/mnt/disk1/photos";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.requires-mounts-for=/mnt/disk1" ];
    };

    fileSystems."/data/.state" = {
      device = "/mnt/disk1/.state";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.requires-mounts-for=/mnt/disk1" ];
    };

    # Hard mount dependencies — SAFETY CRITICAL.
    # If the pool fails to mount, /data/media is an empty directory on the NVMe. Services must
    # refuse to start rather than run against an empty library: Jellyfin would blank the library,
    # and the *-missing-search units would trigger a mass re-download of the entire collection.
    # RequiresMountsFor makes each unit fail closed instead.
    # NOTE: these must be written as dotted paths, not `systemd.services = lib.genAttrs ...`.
    # Nix merges dotted paths into attrset *literals* only — a computed expression collides with
    # the many `systemd.services.<name> = { ... }` definitions elsewhere in this file.
    systemd.services.sonarr.unitConfig.RequiresMountsFor              = [ "/data/media" "/data/.state" ];
    systemd.services.radarr.unitConfig.RequiresMountsFor              = [ "/data/media" "/data/.state" ];
    systemd.services.lidarr.unitConfig.RequiresMountsFor              = [ "/data/media" "/data/.state" ];
    systemd.services.jellyfin.unitConfig.RequiresMountsFor            = [ "/data/media" "/data/.state" ];
    systemd.services.sonarr-rootfolders.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.radarr-rootfolders.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.lidarr-rootfolders.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.jellyfin-libraries.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.podman-audiobookshelf.unitConfig.RequiresMountsFor = [ "/data/media" ];
    systemd.services.podman-shelfarr.unitConfig.RequiresMountsFor     = [ "/data/media" ];
    # Without this, a boot with the pool missing would have Suwayomi happily
    # re-download its whole library onto the NVMe root — the same failure mode
    # sonarr-missing-search is guarded against.
    systemd.services.suwayomi-server.unitConfig.RequiresMountsFor     = [ "/data/media" ];
    systemd.services.podman-filebrowser.unitConfig.RequiresMountsFor  = [ "/data/media" "/data/photos" ];
    systemd.services.immich-server.unitConfig.RequiresMountsFor       = [ "/data/photos" ];

    # --- Data directories ---
    systemd.tmpfiles.rules = [
      "d /data                      0755 root  root  -"
      "d /data/media                0775 root  media -"
      "d /data/media/tv             0775 root  media -"
      "d /data/media/movies         0775 root  media -"
      "d /data/media/music          0775 root  media -"
      "d /data/media/books          0777 root  media -"
      "d /data/media/manga          0775 root  media -"
      "d /downloads                 0775 root  media -"
      "d /downloads/usenet          0775 root  media -"
      "d /data/photos               0775 root  media -"
      "d /data/.state/services      0775 root  media -"
      "d /data/media/audiobooks               0777 root  media -"
      # Container state dirs
      "d /var/lib/audiobookshelf             0775 root  media -"
      "d /var/lib/audiobookshelf/config      0775 root  media -"
      "d /var/lib/audiobookshelf/metadata    0775 root  media -"
      # ⚠️ Must be owned by the container's PUID/PGID (1000/1001), NOT root.
      # Shelfarr's Rails app drops to uid 1000, and its SQLite DBs run in WAL
      # mode — so on every write it may need to CREATE `-wal`/`-shm` files in
      # this directory. With the directory root-owned the existing DB files are
      # still writable (they're owned by rock), so it looks fine, and then any
      # clean shutdown checkpoints the WAL away and the app can never recreate
      # it. Presents as `SQLite3::ReadOnlyException: attempt to write a readonly
      # database` and a hard 500 on EVERY login, because solid_cache writes on
      # the session path. Numeric ids on purpose: gid 1001 has no name on this
      # host (the `media` group is gid 169).
      "d /var/lib/shelfarr                   0755 1000  1001  -"

      "d /var/lib/filebrowser       0775 root  media -"
      "d /var/lib/decluttarr        0755 root  root  -"
      "d /var/lib/decluttarr/config 0755 root  root  -"
      "d /var/lib/recyclarr              0700 root  root  -"
    ];

    # --- Sops secrets ---
    # All secrets live in Secrets/secrets.yaml.
    # Before first build, populate them with:
    #
    #   sops ~/Dots/Secrets/secrets.yaml
    #
    # Add each key as a plain string (generate with: od -An -tx1 -N16 /dev/urandom | tr -d ' \n'):
    #   sonarr-api-key: "<32 hex chars>"
    #   radarr-api-key: "<32 hex chars>"
    #   lidarr-api-key: "<32 hex chars>"
    #   prowlarr-api-key: "<32 hex chars>"
    #   jellyseerr-api-key: "<32 hex chars>"
    #   sabnzbd-api-key: "<32 hex chars>"
    #   sabnzbd-nzb-key: "<32 hex chars>"
    #   jellyfin-api-key: "<32 hex chars>"
    #   jellyfin-admin-password: "<your chosen password>"
    #   cloudflare-tunnel: "<full credentials JSON from Cloudflare dashboard>"
    sops.secrets."sonarr-api-key"           = {};
    sops.secrets."radarr-api-key"           = {};
    sops.secrets."lidarr-api-key"           = {};
    sops.secrets."prowlarr-api-key"         = {};
    sops.secrets."jellyseerr-api-key"       = {};
    # audiobookshelf-api-key: declare here + add to homepage-env once you have the key from ABS Settings → API Keys
    sops.secrets."sabnzbd-api-key"              = {};
    sops.secrets."sabnzbd-nzb-key"              = {};
    sops.secrets."sabnzbd-username"             = {};
    sops.secrets."sabnzbd-password"             = {};
    sops.secrets."usenet/frugalusenet/username"    = {};
    sops.secrets."usenet/frugalusenet/password"    = {};
    sops.secrets."usenet/newshosting/username"     = {};
    sops.secrets."usenet/newshosting/password"     = {};
    sops.secrets."indexer-api-keys/Miatrix"        = {};
    sops.secrets."indexer-api-keys/NZBGeek"        = {};
    sops.secrets."indexer-api-keys/NZBPlanet"      = {};
    sops.secrets."jellyfin-api-key"         = {};
    sops.secrets."jellyfin-admin-password"  = {};
    sops.secrets."cloudflare-tunnel"        = {};
    sops.secrets."mullvad-wg-private-key"       = { mode = "0400"; };
    sops.secrets."admin-username"           = {};
    sops.secrets."admin-password"           = {};
    # Private half of the dedicated Asgard→Eclipse key. Public half lives in
    # Eclipse's /storage/.ssh/authorized_keys (imperative — see Claude/eclipse.md).
    sops.secrets."eclipse-ssh-key"          = { mode = "0400"; };

    # Kernel UDP buffer tuning for smooth streaming over Tailscale
    boot.kernel.sysctl = {
      "net.core.rmem_max"           = lib.mkDefault 26214400;
      "net.core.wmem_max"           = lib.mkDefault 26214400;
      "net.core.netdev_max_backlog" = lib.mkDefault 5000;
    };

  };
}
