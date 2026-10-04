# ══════════════════════════════════════════════════════════════════════════
# liveCard — a Glance widget whose content is drawn in the browser from a
# stream (dash.js + stats.js / net.js / eclipse.js), shared by both
# dashboards (glance.nix, marsbar.nix) so the markup the scripts look for is
# the same in both.
#
# Plain function, not a module — the leading underscore keeps import-tree off
# it. Use: liveCard = import ./_livecard.nix lib;
#
# Glance's `html` widget emits its source raw — no card, no title — so each
# one carries Glance's own widget markup and inherits that dashboard's card
# styling. The skeleton holds the card's height until the first event
# (≈instant: every stream sends its state on connect), so nothing jumps.
#   id     the element the script paints (#ags-host, #nw, #ec-main, …)
#   acc    the card's accent: green or red (→ acc-green / acc-red)
#   rune   the Elder Futhark rune heading it (→ rune-*, Resources/Glance/runes/;
#          the admin dashboard's — MarsBar's cards have her crown blossom instead)
#   badge  id of a live/reconnecting badge in the header, for the script
#   link   { href; text; } — a header link out to the service's own UI
# ══════════════════════════════════════════════════════════════════════════
lib:
{ id, title, acc ? null, rune ? null, badge ? null, link ? null }: {
  type = "html";
  source = ''
    <div class="widget widget-type-asgard-stats${lib.optionalString (acc != null) " acc-${acc}"}${lib.optionalString (rune != null) " rune-${rune}"}">
      <div class="widget-header"><h2 class="uppercase">${title}</h2>${
        lib.optionalString (badge != null) ''<span class="ags-live" id="${badge}">connecting</span>''}${
        lib.optionalString (link != null) ''<a class="ags-open" href="${link.href}" target="_blank" rel="noopener">${link.text} ↗</a>''}</div>
      <div class="widget-content"><div id="${id}"><div class="ags-skel"></div></div></div>
    </div>
  '';
}
