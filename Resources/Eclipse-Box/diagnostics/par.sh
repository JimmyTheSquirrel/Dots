#!/bin/sh
SINK="http://192.168.0.226:9557/"
rm -f /tmp/sp.*
for i in 1 2 3 4; do
  ( t=0; n=0
    while [ $n -lt 6 ]; do
      s=$(curl -s -o /dev/null -m 20 -w '%{speed_download}' "$SINK")
      t=$(awk -v a="$t" -v b="$s" 'BEGIN{print a+b}')
      n=$((n+1))
    done
    awk -v t="$t" 'BEGIN{print t/6}' > /tmp/sp.$i ) &
done
wait
awk '{s+=$1} END{printf "parallel total: %.1f Mbps  (across %d streams)\n", s*8/1000000, NR}' /tmp/sp.*
for f in /tmp/sp.*; do awk -v f="$f" '{printf "  %s: %.1f Mbps\n", f, $1*8/1000000}' $f; done
