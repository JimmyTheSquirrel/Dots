# ══════════════════════════════════════════════════════════════════════════
# Dashboard origins — the only web pages allowed to drive Asgard's little
# control backends cross-origin:
#
#   ha-bridge        :9556  (Modules/Server/home-assistant.nix)  — light toggles
#   eclipse-control  :9554  (Resources/Eclipse-Control)   — TV-box actions
#   network-panel    :9555  (Resources/Network-Panel)     — speed-test trigger
#
# Plain data, imported by path (the "/_" keeps import-tree off it).
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
# The same list is the DEFAULT baked into eclipse-control.py and network-panel.py
# (DASH_ORIGINS), so they behave identically before their units pass it in.
# Keep the two in step.
[
  "http://asgard:8888"
  "http://asgard.tailb54b82.ts.net:8888"
  "http://100.126.205.100:8888"
  "http://marsbar:1111"
  "http://marsbar.tailb54b82.ts.net:1111"
]
