#!/bin/sh
# Pin Eclipse to wired on the LAN: never let connman auto-swap to Wi-Fi.
# Self-reverting: if the network does not come back, the override is removed.
set -x
LOG=/storage/wired-only-apply.log
exec >>"$LOG" 2>&1
echo "=== run $(date) ==="

systemctl stop connman
sleep 2

# 1. no saved Wi-Fi may auto-connect
for d in /storage/.cache/connman/wifi_*/; do
  [ -f "$d/settings" ] || continue
  if grep -q "^AutoConnect=true" "$d/settings"; then
    sed -i "s/^AutoConnect=true/AutoConnect=false/" "$d/settings"
    echo "autoconnect off: $d"
  fi
done

# 2. connman may hold only ONE technology at a time, ethernet preferred
mkdir -p /storage/.config
cp /etc/connman/main.conf /storage/.config/connman_main.conf
sed -i "s/^# SingleConnectedTechnology = false/SingleConnectedTechnology = true/" \
  /storage/.config/connman_main.conf
grep -n "^SingleConnectedTechnology\|^PreferredTechnologies" /storage/.config/connman_main.conf

systemctl start connman
sleep 25

# 3. deadman — if the LAN is not reachable, undo and go back to the stock config
if ping -c 3 -W 2 192.168.0.1 >/dev/null 2>&1; then
  echo "OK: gateway reachable, override kept"
else
  echo "FAIL: no gateway, REVERTING"
  rm -f /storage/.config/connman_main.conf
  systemctl restart connman
fi
echo "=== done $(date) ==="
