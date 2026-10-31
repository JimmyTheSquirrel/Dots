# ══════════════════════════════════════════════════════════════════════════
# Smart-plug inventory — the ONE place a plug is listed.
#
# Plain data, not a module. The leading underscore is what keeps import-tree
# from loading it (it skips every path containing "/_"), so each consumer
# imports it by path:
#
#   Modules/Server/home-assistant.nix → ha-bridge's ALLOWED + watch list, and the
#                                members of the Living Room Lights group
#   Modules/Server/marsbar.nix        → her light tiles
#   Modules/Server/glance.nix         → the main Glance: the home page's light
#                                tiles, the Power page's chart, cards and
#                                switches, Plug Health, and the one Jinja query
#                                behind them all
#
# Before this file the same five plugs were spelled out in about eight places —
# Jinja tuples on the old Monitoring page, the bridge allowlist, the HA group, the
# MarsBar list — and they had already drifted (three different display names for
# the fairy lights, two different orders). Add a plug HERE and everything that
# should know about it does; nothing else needs touching.
#
# builtins only, no lib, so `import ./_plugs.nix` works from anywhere without
# arguments.
# ══════════════════════════════════════════════════════════════════════════
let
  # Every plug is an Athom Plug V3 on ESPHome, so every entity hangs off one
  # device slug: switch.<slug>_switch, sensor.<slug>_power, sensor.<slug>_voltage,
  # sensor.<slug>_total_daily_energy, binary_sensor.<slug>_status, … — the
  # Power page's Jinja (plugQuery in glance.nix) builds all of those from
  # `slug` alone.
  #
  # Fields:
  #   slug    ESPHome device prefix (see above)
  #   entity  the relay. Written out rather than derived from slug so it greps.
  #   name    label on the admin dashboard
  #   short   label where space is tight (Plug Health rows); defaults to name
  #   sub     admin dashboard sub-line
  #   room    where it physically is — the light tiles' sub-line (lights only)
  #   icon    light tile glyph, on both dashboards (lights only)
  #   light   true  → a lamp: toggleable from both dashboards, a member of the
  #                   Living Room Lights group, drawn on MarsBar
  #           false → a running MACHINE. Monitored, never toggleable: these
  #                   relays are mains feeds and cutting one is an unclean stop.
  #   her     optional overrides for MarsBar's tile ({ name; sub; })
  #
  # List order is display order, on both dashboards.
  plugs = [
    {
      slug = "server_power";
      entity = "switch.server_power_switch";
      name = "Asgard";
      sub = "Server · Athom Plug V3";
      # ⚠ Asgard's OWN mains feed. Flipping it cuts the server mid-write.
      light = false;
    }
    {
      slug = "eclipse";
      entity = "switch.eclipse_switch";
      name = "Eclipse";
      sub = "Pi 5 TV box · Athom Plug V3";
      light = false;
    }
    {
      slug = "colour_lamp";
      entity = "switch.colour_lamp_switch";
      name = "Colour Lamp";
      sub = "Colour lamp";
      room = "Living room";
      icon = "◐";
      light = true;
    }
    {
      slug = "lounge_room_lamp";
      entity = "switch.lounge_room_lamp_switch";
      name = "Lounge Lamp";
      sub = "Standard lamp";
      room = "Lounge room";
      icon = "◑";
      light = true;
    }
    {
      slug = "christmas_lights";
      entity = "switch.christmas_lights_switch";
      name = "Christmas Lights";
      short = "Christmas";
      sub = "Fairy lights";
      room = "Living room";
      icon = "❅";
      light = true;
      # Display name only — the HA entity id stays christmas_lights_switch, so
      # this does NOT need a matching change anywhere else.
      her = { name = "Fairy Lights"; };
    }
  ];


  # ── Bedside bulbs (the bedroom touch lamps) ─────────────────────────────
  # Athom RGBCW bulbs on ESPHome. NOT plugs, and deliberately absent from
  # `plugs`: they have no relay and no power/voltage/current/energy sensors at
  # all, so they must never reach the Power page's 24 h chart, its per-device
  # cards or Plug Health — every one of those is generated from `plugs` and
  # would render blank rows. They are lights in the two senses that matter:
  # toggleable from both dashboards, and colour-controllable.
  #
  # ⚠ NOT members of `group` either. That group is the living-room/lounge
  # lamps; an "All Lights" tap at 11pm must not come on in the bedroom.
  #
  # ── Why a bulb carries three extra entities ────────────────────────────
  # These sit in TOUCH LAMPS: the base cuts mains. So the bulb reboots every
  # time the lamp is switched off and on, HA sees it go `unavailable`, and the
  # live colour/brightness attributes are gone when it comes back.
  #
  #   powerOn  select.<slug>_power_on_state — what the bulb does when mains
  #            returns. Options: "Always Off" / "Always On" /
  #            "Restore Power Off State". It ships as **Always Off**, which is
  #            why a touch lamp boots dark and "won't keep its settings".
  #            home-assistant.nix holds it at `restoreState` below.
  #   preset   input_select.<slug>_preset     — the remembered colour, by name
  #   bright   input_number.<slug>_brightness — the remembered brightness, %
  #
  # The last two are the bulb's memory, and they live in HA rather than in the
  # bulb because HA is what survives the power cut. The restore automation
  # re-applies them when the bulb reappears, and both dashboards read them back
  # to light the right swatch and position the slider — all over ha-bridge's
  # ordinary state stream, since an input_select/input_number state is just a
  # string like any relay's.
  #
  # Fields otherwise as for a plug (slug, entity, name, short, room, icon, her).
  bulbs = [
    {
      slug = "caitlin_bedside_lamp";
      entity = "light.caitlin_bedside_lamp_rgbcw_bulb";
      name = "Caitlin's Lamp";
      short = "Caitlin";
      room = "Bedroom";
      icon = "◉";
    }
    {
      slug = "rhys_bedside_table";
      entity = "light.rhys_bedside_table_rgbcw_bulb";
      name = "Rhys's Lamp";
      short = "Rhys";
      room = "Bedroom";
      icon = "◉";
    }
  ];

  # The one value `powerOn` may hold. Anything else and a touch lamp comes back
  # dark (Always Off) or back at firmware-default white (Always On) — only
  # "Restore Power Off State" brings it back as it was. Spelled exactly as the
  # ESPHome select offers it; a typo makes HA's select.select_option a no-op.
  restoreState = "Restore Power Off State";

  # ── The colour presets ──────────────────────────────────────────────────
  # THE one place a bedroom colour is defined: the input_select's options, the
  # swatches on both dashboards, what ha-bridge sends HA, and what the restore
  # automation re-applies after a power cut all come from here. `name` is the
  # key everywhere — it is the input_select option value AND the dashboards'
  # data-ha-preset — so one list keeps the four in step.
  #
  # ── Why these are rgbww and not hue/saturation or kelvin ───────────────────
  # The bulb has FIVE dies: red, green, blue, a 6500 K cold white and a 3000 K
  # warm white. Two facts about them shaped this table:
  #
  #   1. The warm die is a 3000 K WHITE. Colour temperature physically cannot
  #      reach a yellow on this hardware, no matter how far the warmth slider
  #      goes — which is why the warm end always looked "close to white".
  #   2. Athom ship the firmware with `color_interlock: true`, which forbids
  #      the RGB dies and the white dies being lit at the same time. That left
  #      exactly two possibilities — bright-and-white, or amber-but-dim, with
  #      NOTHING in between, because the firmware refused the mix.
  #
  # Fault 2 is now fixed in the firmware (Resources/ESPHome/bedside-bulb.yaml,
  # flashed 2026-10-31), so all five channels run together and HA sees one
  # combined `rgbww` mode. A soft amber is therefore warm-white-at-full with
  # red laid OVER it: bright and deep at once, which neither mode could do
  # alone. That is what the `rgbww` numbers below are.
  #
  # ⚠ These values only work on the reflashed firmware. On a factory bulb HA
  # would silently convert them back into one mode or the other and the old
  # problem returns — so if a bulb is ever replaced, reflash it before
  # wondering why its amber went dark again.
  #
  #   rgbww  [red, green, blue, cold-white, warm-white], each 0-255.
  #          The white pair is capped by the firmware's `constant_brightness`
  #          so the two of them together never exceed one channel's output;
  #          the RGB three are not capped, which is what lets amber sit on top
  #          of white instead of replacing it.
  #   css    what the swatch looks like on the dashboards. A literal colour is
  #          correct here and is the one exception to the "never a literal"
  #          rule in CLAUDE.md: a swatch stands for a real light colour, not
  #          for dashboard chrome, so it must NOT follow the viewer's theme.
  #
  # Order is warmest first — it is the order the swatches appear in, and it
  # reads as one ladder from candlelight to daylight. `Honey` is the rung that
  # was missing entirely before the reflash.
  # ⚠⚠⚠ THESE NUMBERS WERE TUNED ON THE ACTUAL LAMPS. DON'T "CORRECT" THEM. ⚠⚠⚠
  #
  # Every attempt to DERIVE these from theory failed, three times running, and
  # each failure looked like a different bug. What finally worked was bisecting
  # against rock's own eyes, one variable at a time, on the real hardware.
  #
  # The measured anchors, with the white lift removed so hue was the only
  # variable (all at r = 255):
  #
  #     green 110  →  "dark orange"
  #     green 122  →  AMBER. the one he picked.
  #     green 140  →  past it
  #     green 160  →  "a really light green colour"
  #     green 189  →  "yellow kinda green"
  #
  # Note how violently it turns: 110 is orange and 160 is green. Two reasons,
  # and both have to be in your head before you touch a number:
  #
  #   1. `gamma_correct: 2.8` in the firmware — duty = (value/255)^2.8. Mid-range
  #      values collapse. g = 122 is NOT "about half", it drives ~12 %.
  #   2. The green die is several times more luminous than the red die at equal
  #      drive — green LEDs are efficient and the eye peaks near 555 nm. So ~12 %
  #      green already balances 100 % red.
  #
  # Then the white lift, judged separately once the hue was fixed:
  #
  #     warm white  85  →  too dark      135  →  too washed
  #     warm white 110  →  right. the halfway point he asked for.
  #
  # ⭐ To retune: change ONE channel, set it on a real lamp, look at it. The two
  # bulbs are identical, so putting a different value on each and comparing side
  # by side is worth ten minutes of arithmetic.
  #
  # ⚠ Values below ~96 green go red rather than warm; above ~160 they go green,
  # not yellow. The whole warm range lives in green 96-160.
  presets = [
    { name = "Candle";  css = "#ff5410"; rgbww = [ 255  96   0   0  35 ]; }
    { name = "Ember";   css = "#ff6a18"; rgbww = [ 255 104   0   0 155 ]; }
    { name = "Amber";   css = "#ff8c24"; rgbww = [ 255 122   0   0 110 ]; }
    { name = "Honey";   css = "#ffa43a"; rgbww = [ 255 138   0   0 140 ]; }
    { name = "Gold";    css = "#ffbe5c"; rgbww = [ 255 152  15   0 175 ]; }
    { name = "Warm";    css = "#ffd8a0"; rgbww = [ 255 168  70   0 215 ]; }
    { name = "Neutral"; css = "#ffe8d2"; rgbww = [   0   0   0 120 255 ]; }
    { name = "Cool";    css = "#eef3ff"; rgbww = [   0   0   0 255  50 ]; }
  ];

  # ── Custom: mix your own ────────────────────────────────────────────────
  # A ninth swatch whose colour is NOT fixed here — it is whatever the five
  # sliders below currently say. The sliders are ordinary HA input_numbers, so
  # the mix persists across reboots, shows up in the HA app, and rides the same
  # ha-bridge stream as everything else.
  #
  # Deliberately ONE shared mix rather than one per bulb: two lamps either side
  # of the same bed want the same colour, and ten sliders is not a control panel
  # anybody would use. Tapping Custom on either bulb applies the current mix.
  #
  # `defaultValue` is only the cold-start value — see the no-`initial:` note in
  # home-assistant.nix for why these are not re-applied on every restart. It is
  # set to the tuned Amber so an untouched Custom is a sane colour, not black.
  customName = "Custom";
  #
  # ⚠ ORDER IS LOAD-BEARING. This list IS an rgbww tuple: red, green, blue,
  # COLD white, WARM white — the same order the `rgbww` values above use and
  # the order HA's rgbww_color expects. Everything zips against it positionally
  # (the bridge writing the sliders, the restore automation's Jinja, the
  # dashboard rows), so listing warm before cold silently swaps those two
  # channels everywhere at once. It was written that way first and the endpoint
  # test caught it — keep the test if you touch this.
  customChannels = [
    { key = "red";   entity = "input_number.bedroom_custom_red";   label = "Red";        icon = "mdi:invert-colors"; defaultValue = 255; }
    { key = "green"; entity = "input_number.bedroom_custom_green"; label = "Green";      icon = "mdi:invert-colors"; defaultValue = 122; }
    { key = "blue";  entity = "input_number.bedroom_custom_blue";  label = "Blue";       icon = "mdi:invert-colors"; defaultValue = 0; }
    { key = "cold";  entity = "input_number.bedroom_custom_cold";  label = "Cool white"; icon = "mdi:snowflake"; defaultValue = 0; }
    { key = "warm";  entity = "input_number.bedroom_custom_warm";  label = "Warm white"; icon = "mdi:white-balance-sunny"; defaultValue = 110; }
  ];

  # What a bulb comes back as before anyone has touched a swatch.
  defaultPreset = "Amber";
  defaultBrightness = 70;

  # ── The room sensor ─────────────────────────────────────────────────────
  # An ESPHome temp/humidity sensor sitting with Asgard, reading the AIR of the
  # room — not the hardware. Asgard's own CPU and drive temperatures come from
  # asgard-stats reading the machine; this is the other half of the pair, and
  # the useful number is the DIFFERENCE between them: a CPU at 70 °C in a 22 °C
  # room is a healthy server, and the same CPU in a 34 °C room is a cupboard
  # with no airflow. The dashboard draws both rings side by side for exactly
  # that reason, and spells the delta out underneath.
  #
  # It lives in this file because the dashboard reads it through the same
  # ha-bridge stream as the lights, and `watched` is the list of what the
  # bridge is allowed to publish — a sensor that is not in `watched` cannot
  # appear on any dashboard, which is precisely why this one was invisible.
  #
  # ⚠ READ-ONLY. It must never appear in `toggleable` or `colourable`.
  # `light.asgard_temp_humidity_sensor_light` is the sensor's own status LED,
  # not a lamp — keep it off the light tiles too.
  room = {
    slug = "asgard_temp_humidity_sensor";
    name = "Server room";
    temp = "sensor.asgard_temp_humidity_sensor_temperature";
    humidity = "sensor.asgard_temp_humidity_sensor_humidity";
    online = "binary_sensor.asgard_temp_humidity_sensor_status";
    # Where the dashboard's room ring starts and ends, and when it says "hot".
    # Not arbitrary: 10-40 °C is the band a living space actually moves in, so
    # the arc uses its whole sweep instead of sitting still near the bottom.
    # The thresholds are a first guess to be replaced by measurement once
    # Asgard is actually in the cupboard — Claude/next-up.md.
    floor = 10;
    ceiling = 40;
    warn = 30;
    bad = 35;
  };

  withDefaults = p: {
    short = p.name;
    room = "";
    icon = "•";
    her = { };
    power = "sensor.${p.slug}_power";
  } // p;

  all = map withDefaults plugs;
  lights = builtins.filter (p: p.light) all;

  # A bulb's derived entity ids. Written out from `slug` the same way the Power
  # page builds a plug's sensors, so adding a bulb above needs nothing else.
  bulbDefaults = b: {
    short = b.name;
    room = "";
    icon = "•";
    her = { };
    powerOn = "select.${b.slug}_power_on_state";
    preset = "input_select.${b.slug}_preset";
    bright = "input_number.${b.slug}_brightness";
    online = "binary_sensor.${b.slug}_status";
  } // b;

  allBulbs = map bulbDefaults bulbs;

  # ── Living Room Lights ──────────────────────────────────────────────────
  # A `group` platform switch in Home Assistant (Modules/Server/home-assistant.nix),
  # so it is a real entity — one thing to toggle from either dashboard, the HA
  # app and automations alike, on if any member is on. Members are exactly the
  # `light = true` plugs; the machines can never end up in it, because a group
  # toggle that also cut the server would be a spectacular way to lose an array.
  #
  # ⚠ HA derives the entity id from `name`. Renaming it renames the entity
  # (switch.<slugified name>) and silently breaks every dashboard reference, so
  # change `entity` in the same edit.
  group = {
    entity = "switch.living_room_lights";
    name = "Living Room Lights";
    members = map (p: p.entity) lights;
    her = { name = "All Lights"; sub = "Everything at once"; icon = "✦"; };
  };
in
{
  plugs = all;
  inherit lights group;
  machines = builtins.filter (p: !p.light) all;

  # The bedside bulbs and their colours — see the long note above `bulbs`.
  # Separate from `plugs` on purpose: nothing power-related may iterate these.
  bulbs = allBulbs;
  inherit presets restoreState defaultPreset defaultBrightness;

  # The room temp/humidity sensor — see the note above `room`. Read-only.
  inherit room;

  # The ninth swatch and the five sliders behind it — see `customChannels`.
  inherit customName customChannels;

  # ── What ha-bridge may toggle ───────────────────────────────────────────
  # THE safety boundary for every dashboard, not a UI hint: anything on the
  # tailnet can POST to the bridge, so the machines' relays being absent from
  # this list is what actually keeps them unflippable. The group, its lamps and
  # the bedside bulbs only — derived from `light`, so a newly added machine is
  # safe by default.
  toggleable = [ group.entity ] ++ group.members ++ map (b: b.entity) allBulbs;

  # ── What ha-bridge may recolour ─────────────────────────────────────────
  # The same kind of boundary for POST /light: only these entities accept a
  # colour, and only to one of `presets`. Each carries the two helper entities
  # the bridge writes the choice into, so the restore automation and every open
  # dashboard see it — nothing else in HA is reachable through that verb.
  colourable = map (b: {
    inherit (b) entity preset bright;
  }) allBulbs;

  # ── What ha-bridge watches and streams ──────────────────────────────────
  # Every relay (machines included — read-only is still worth seeing), each
  # plug's live draw, and the rest of what the Power page shows — volts, amps,
  # today's energy, wifi signal, and whether the plug itself answers — so every
  # figure on that page moves live instead of being a page-load snapshot.
  # Read-only: watching is not the same as ALLOWED (toggleable, above).
  #
  # Each bulb adds its light, its power-on-state select (so a bulb that has
  # drifted off "Restore Power Off State" is visible), and its two remembered
  # values — which is how a swatch lights up and a slider finds its position
  # without the bridge ever having to stream light attributes.
  watched =
    [ group.entity ]
    ++ map (p: p.entity) all
    ++ builtins.concatMap (p: [
      p.power
      "sensor.${p.slug}_voltage"
      "sensor.${p.slug}_current"
      "sensor.${p.slug}_total_daily_energy"
      "sensor.${p.slug}_wifi_signal_percent"
      "sensor.${p.slug}_wifi_signal_db"
      "binary_sensor.${p.slug}_status"
    ]) all
    ++ builtins.concatMap (b: [
      b.entity
      b.powerOn
      b.preset
      b.bright
      b.online
      "sensor.${b.slug}_wifi_signal_percent"
    ]) allBulbs
    # The room sensor. Without these three in `watched` the bridge does not
    # publish them and the dashboard cannot draw the room at all.
    ++ [ room.temp room.humidity room.online ]
    # The custom-colour sliders, so both dashboards show the live mix and a
    # change made on one appears on the other.
    ++ map (c: c.entity) customChannels;
}
