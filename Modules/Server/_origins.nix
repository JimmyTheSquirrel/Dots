# ══════════════════════════════════════════════════════════════════════════
# Dashboard origins — the only web pages allowed to drive Asgard's little
# control backends cross-origin:
#
#   ha-bridge        :9556  (Modules/Server/home-assistant.nix)  — light toggles
#   eclipse-control  :9554  (Modules/Server/eclipse.nix)         — TV-box actions
#   network-panel    :9555  (Modules/Server/network.nix)         — speed-test trigger
#
# Plain data, imported by path (the "/_" keeps import-tree off it). A function
# of Asgard's tailnet facts so the IP and MagicDNS name are read from the one
# definition in Modules/Server/default.nix (options.asgard) instead of being
# typed out again here — every caller passes `config.asgard` straight in:
#
#   origins = import ./_origins.nix config.asgard;
#
# Why this list exists at all: those backends take body-less, unauthenticated
# POSTs, and they used to answer `Access-Control-Allow-Origin: *`. A CORS
# wildcard plus a "simple" request (no custom headers) means ANY web page open in
# a browser on the tailnet could fire /toggle/… or /act/reboot with a plain
# fetch(). Each backend now refuses a POST that lacks `X-Dash: 1` — a custom
# header, so a cross-origin caller must pass a CORS preflight first — and the
# preflight only succeeds for an origin listed here. Same-origin callers (MarsBar
# via `tailscale serve`, the eclipse panel's own page) need no entry: they never
# preflight.
#
# The main Glance builds its API URLs from location.hostname, so every name it
# is opened by needs an entry. The MarsBar ones only matter if a MarsBar page is
# ever made to call a backend directly instead of through its /…-api mounts.
#
# ha-bridge reads this from its JSON config; eclipse-control.py and
# network-panel.py get it as DASH_ORIGINS (comma-separated) from their units.
# Their built-in default is a copy of this list for running them by hand —
# the units always pass the real one in.
{ tailnetIp, tailnetFqdn, ... }:
let
  # "asgard.tailb54b82.ts.net" → [ "asgard" "tailb54b82.ts.net" ]. MarsBar is
  # its own node (`marsbar`) on the same tailnet, so its FQDN shares the suffix.
  parts = builtins.match "([^.]+)\\.(.+)" tailnetFqdn;
  host = builtins.elemAt parts 0;
  tailnet = builtins.elemAt parts 1;
in
[
  # Glance on :8888 (Modules/Server/glance.nix), by short name, FQDN and IP.
  "http://${host}:8888"
  "http://${tailnetFqdn}:8888"
  "http://${tailnetIp}:8888"
  # MarsBar's serve port (Modules/Server/marsbar.nix).
  "http://marsbar:1111"
  "http://marsbar.${tailnet}:1111"
]
