#!/bin/sh
SINK="http://192.168.0.226:9557/"
read_rx() { grep -E "^ *eth0" /proc/net/dev | awk '{print $2}'; }

echo "=== BASELINE (Kodi only, 8s) ==="
a=$(read_rx); sleep 8; b=$(read_rx)
BASE=$(( (b-a)*8/8/1000000 ))
echo "kodi alone: ${BASE} Mbps"

echo "=== + 4 PARALLEL CURL STREAMS (12s) ==="
for i in 1 2 3 4; do
  ( end=$(( $(date +%s) + 12 ))
    while [ $(date +%s) -lt $end ]; do
      curl -s -o /dev/null -m 12 "$SINK" 2>/dev/null
    done ) &
done
sleep 1
a=$(read_rx); sleep 10; b=$(read_rx)
TOT=$(( (b-a)*8/10/1000000 ))
wait
echo "aggregate (kodi + 4 streams): ${TOT} Mbps"
echo "=> extra capacity found: $(( TOT - BASE )) Mbps"

echo "=== SINGLE-STREAM curl rate ==="
curl -s -o /dev/null -m 15 -w 'single stream: %{speed_download} B/s\n' "$SINK"
