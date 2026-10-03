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
#                                tiles, the Monitoring page's power cards and
#                                switches, Plug Health, and the one Jinja query
#                                behind them all
#
# Before this file the same five plugs were spelled out in about eight places —
# Jinja tuples on the Monitoring page, the bridge allowlist, the HA group, the
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
  # Monitoring page's Jinja (plugQuery in glance.nix) builds all of those from
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

  withDefaults = p: {
    short = p.name;
    room = "";
    icon = "•";
    her = { };
    power = "sensor.${p.slug}_power";
  } // p;

  all = map withDefaults plugs;
  lights = builtins.filter (p: p.light) all;

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

  # ── What ha-bridge may toggle ───────────────────────────────────────────
  # THE safety boundary for every dashboard, not a UI hint: anything on the
  # tailnet can POST to the bridge, so the machines' relays being absent from
  # this list is what actually keeps them unflippable. The group and its lamps
  # only — derived from `light`, so a newly added machine is safe by default.
  toggleable = [ group.entity ] ++ group.members;

  # ── What ha-bridge watches and streams ──────────────────────────────────
  # Every relay (machines included — read-only is still worth seeing) plus each
  # plug's live draw, so a dashboard can show watts moving without polling HA.
  watched =
    [ group.entity ]
    ++ map (p: p.entity) all
    ++ map (p: p.power) all;
}
