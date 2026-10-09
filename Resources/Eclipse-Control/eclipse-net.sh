#!/bin/sh
# eclipse-net.sh — switch Eclipse between the cable and Wi-Fi, and undo it by
# itself if it can't get online.
#
# Runs ON THE PI. eclipse-control (Asgard) sends it over ssh before every switch
# and starts it detached (systemd-run --unit=eclipse-net), because the link the
# dashboard talks over is the very one being switched: the dashboard can't watch
# it finish, and a half-done switch on a headless box means a trip to the TV.
# Nothing here is installed on the Pi permanently; see Claude/eclipse.md → Network.
#
#   eclipse-net.sh wired - - <token>
#       Wired only (home). Exactly the 2026-10-09 fix in Resources/Eclipse-Box/
#       network/: connman keeps ONE technology (SingleConnectedTechnology, wired
#       first) and NO saved Wi-Fi joins by itself — not even if the cable comes
#       out. Needs a cable.
#   eclipse-net.sh wifi <service> old <token>
#       Wi-Fi (away). Connect <service>, a network the Pi already has saved. From
#       now on every saved Wi-Fi joins by itself — so it gets back on after a
#       restart, wherever it is — and the cable stays first: plug one in and it
#       takes over, so this mode can never strand the box.
#   eclipse-net.sh wifi <service> new <token>
#       The same, for a network joined just now: pending.config (written by
#       eclipse-control through ssh's stdin — a passphrase never goes on a
#       command line) is installed as a connman provisioning file first, and
#       removed again if the join fails, so a wrong password is not kept.
#
# The deadman: after switching it waits ~30 s for connman to say "online", or the
# new gateway to answer a ping. If neither, it puts back exactly what was there
# (every saved network's AutoConnect, and the link that was carrying traffic).
#
# Outcome → /storage/.cache/eclipse-net/result: "<epoch> <token> <ok|reverted|fail> <message>"
# Log     → /storage/.cache/eclipse-net/log (last ~400 lines)
#
# Busybox sh: no bashisms. Every argument is checked again here even though
# eclipse-control has already validated it.

set -u
MODE=${1:-}; SVC=${2:--}; NEW=${3:-old}; TOKEN=${4:-none}
C=/storage/.cache/connman                 # connman's STORAGEDIR on LibreELEC
W=/storage/.cache/eclipse-net
CONF=/storage/.config/connman_main.conf   # connman-setup prefers this over /etc's

mkdir -p "$W"
if [ -f "$W/log" ]; then tail -n 400 "$W/log" > "$W/log.tmp" && mv "$W/log.tmp" "$W/log"; fi
exec >>"$W/log" 2>&1

say() { echo "$(date '+%F %T') $*"; }
finish() {   # finish <ok|reverted|fail> <message>
  printf '%s %s %s %s\n' "$(date +%s)" "$TOKEN" "$1" "$2" > "$W/result.tmp"
  mv "$W/result.tmp" "$W/result"
  rm -f "$W/pending.config"
  say "=> $1: $2"
  exit 0
}

say "=== $MODE $SVC $NEW ($TOKEN)"
case "$TOKEN" in *[!0-9a-f]*|'') TOKEN=none; finish fail "bad token" ;; esac
case "$SVC" in -|wifi_*) ;; *) finish fail "bad service" ;; esac
case "$SVC" in *[!a-z0-9_-]*) finish fail "bad service" ;; esac
case "$MODE:$SVC" in wired:-|wifi:wifi_*) ;; *) finish fail "bad arguments" ;; esac
case "$NEW" in old|new) ;; *) finish fail "bad arguments" ;; esac
if [ "$NEW" = new ] && [ ! -s "$W/pending.config" ]; then finish fail "no network details were sent"; fi

# The SSID part of a Wi-Fi service id: wifi_<mac>_<ssid hex>_managed_<security>
hex_of() { echo "$1" | cut -d_ -f3; }
name_of() {
  n=$(connmanctl services "$1" 2>/dev/null | sed -n 's/^ *Name = //p' | head -1)
  [ -n "$n" ] && echo "$n" || echo "$1"
}

svcs() { connmanctl services 2>/dev/null; }
# What carries traffic now: an online service first, else a ready one.
current() {
  svcs | awk '{ f = substr($0, 1, 3); id = $NF }
              f ~ /O/ && o == "" { o = id }
              f ~ /R/ && r == "" { r = id }
              END { if (o != "") print o; else if (r != "") print r }'
}
state_of() { connmanctl services "$1" 2>/dev/null | sed -n 's/^ *State = //p' | head -1; }
seen() { svcs | awk -v s="$1" '$NF == s { f = 1 } END { exit !f }'; }

# Online = connman's own internet check passed, or the gateway answers.
online() {
  st=$(state_of "$1")
  [ "$st" = online ] && return 0
  [ "$st" = ready ] || return 1
  gw=$(ip route show default 2>/dev/null | awk '{ print $3; exit }')
  [ -n "$gw" ] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1
}
wait_online() {   # ~30 s
  i=0
  while [ $i -lt 15 ]; do online "$1" && return 0; sleep 2; i=$((i + 1)); done
  return 1
}
wait_seen() {     # ~25 s; Wi-Fi gets a scan to speed it up
  case "$1" in wifi_*) connmanctl scan wifi >/dev/null 2>&1 ;; esac
  i=0
  while [ $i -lt 25 ]; do seen "$1" && return 0; sleep 1; i=$((i + 1)); done
  return 1
}
wired_id() {
  i=0
  while [ $i -lt 20 ]; do
    id=$(svcs | awk '$NF ~ /^ethernet_/ { print $NF; exit }')
    [ -n "$id" ] && { echo "$id"; return 0; }
    sleep 1; i=$((i + 1))
  done
  return 1
}

# ── the settings these modes are made of. connman rewrites its files when it
# exits, so they are only ever edited with it stopped (wired-only-apply.sh does
# the same), and `connmanctl config --autoconnect` can't reach a network that is
# out of range anyway.
wifi_auto() {     # true|false on every saved Wi-Fi
  for d in "$C"/wifi_*/; do
    [ -f "$d/settings" ] || continue
    if grep -q '^AutoConnect=' "$d/settings"; then
      sed -i "s/^AutoConnect=.*/AutoConnect=$1/" "$d/settings"
    else
      echo "AutoConnect=$1" >> "$d/settings"
    fi
  done
}
wired_auto() {    # the cable always joins by itself, in both modes
  for d in "$C"/ethernet_*/; do
    [ -f "$d/settings" ] && sed -i 's/^AutoConnect=false/AutoConnect=true/' "$d/settings"
  done
}
one_link() {      # the override wired-only-apply.sh installs; put back if a re-flash lost it
  grep -q '^SingleConnectedTechnology *= *true' "$CONF" 2>/dev/null && return 0
  mkdir -p /storage/.config
  cp /etc/connman/main.conf "$CONF"
  sed -i 's/^# *SingleConnectedTechnology *= *false/SingleConnectedTechnology = true/' "$CONF"
  grep -q '^SingleConnectedTechnology *= *true' "$CONF" || echo 'SingleConnectedTechnology = true' >> "$CONF"
  say "installed $CONF (SingleConnectedTechnology = true)"
}

# What to put back: every saved network's AutoConnect line, and the link in use.
PREV=$(current)
: > "$W/auto.bak"
for d in "$C"/wifi_*/ "$C"/ethernet_*/; do
  [ -f "$d/settings" ] || continue
  echo "$d $(sed -n 's/^AutoConnect=//p' "$d/settings" | head -1)" >> "$W/auto.bak"
done
say "before: ${PREV:-nothing connected}"

restore_auto() {
  while read -r d v; do
    [ -f "$d/settings" ] || continue
    case "$v" in true|false) sed -i "s/^AutoConnect=.*/AutoConnect=$v/" "$d/settings" ;; esac
  done < "$W/auto.bak"
}

PROV=""
go_wired() {
  systemctl stop connman; sleep 2
  wifi_auto false; wired_auto; one_link
  systemctl start connman
  eth=$(wired_id) || { say "no wired service — is the cable in?"; return 1; }
  connmanctl connect "$eth" >/dev/null 2>&1     # already up by itself, usually
  wait_online "$eth"
}
go_wifi() {       # go_wifi <service>
  systemctl stop connman; sleep 2
  wifi_auto true; wired_auto; one_link
  if [ "$NEW" = new ] && [ "$1" = "$SVC" ]; then
    PROV="$C/eclipse-$(hex_of "$SVC").config"
    cp "$W/pending.config" "$PROV" && chmod 600 "$PROV"
  fi
  systemctl start connman
  sleep 2
  connmanctl enable wifi >/dev/null 2>&1          # the radio was once found off (Claude/eclipse.md)
  wait_seen "$1" || { say "$1 is not in range"; return 1; }
  # A connect the user asked for: with one link allowed, connman drops the cable for it.
  connmanctl connect "$1" 2>&1 | tail -2
  wait_online "$1"
}

if [ "$MODE" = wired ]; then
  [ "$(cat /sys/class/net/eth0/carrier 2>/dev/null)" = 1 ] || finish fail "no cable in Eclipse"
  if go_wired; then finish ok "on the cable — wired only, Wi-Fi never joins by itself"; fi
  WHAT="the cable"
else
  if go_wifi "$SVC"; then
    finish ok "on Wi-Fi: $(name_of "$SVC") — saved networks rejoin by themselves"
  fi
  WHAT="$(name_of "$SVC")"
fi

# ── deadman ──────────────────────────────────────────────────────────────────
say "not online on $WHAT — putting back ${PREV:-the old settings}"
[ -n "$PROV" ] && rm -f "$PROV"            # connman drops that network and its saved settings
systemctl stop connman; sleep 2
restore_auto
systemctl start connman
sleep 2
case "$PREV" in
  wifi_*)
    wait_seen "$PREV" && connmanctl connect "$PREV" >/dev/null 2>&1
    wait_online "$PREV" && finish reverted "couldn't get online on $WHAT — back on $(name_of "$PREV")" ;;
  ethernet_*)
    connmanctl connect "$PREV" >/dev/null 2>&1
    wait_online "$PREV" && finish reverted "couldn't get online on $WHAT — back on the cable" ;;
esac
finish fail "couldn't get online on $WHAT, and ${PREV:-the old link} didn't come back either"
