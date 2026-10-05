#!/bin/sh
rx() { grep -E "^ *eth0" /proc/net/dev | sed 's/.*eth0: *//' | awk '{print $1}'; }
SINK="http://192.168.0.226:9557/"
echo "sanity: rx counter = $(rx)"
for i in 1 2 3 4 5 6; do
  ( n=0; while [ $n -lt 12 ]; do curl -s -o /dev/null -m 14 "$SINK" 2>/dev/null; n=$((n+1)); done ) &
done
sleep 1
A=$(rx); sleep 10; B=$(rx)
echo "aggregate (6 streams): $(( (B-A)*8/10/1000000 )) Mbps"
wait
echo "--- single stream again ---"
curl -s -o /dev/null -m 25 -w 'single: %{speed_download} B/s\n' "$SINK"
