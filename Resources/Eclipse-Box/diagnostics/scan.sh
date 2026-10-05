#!/bin/sh
rx() { grep -E "^ *eth0" /proc/net/dev | sed 's/.*eth0: *//' | awk '{print $1}'; }
echo "=== ECLIPSE LOAD DURING STREAM ==="
echo "uptime: $(uptime)"
vcgencmd measure_temp; vcgencmd get_throttled
echo "--- top processes ---"
top -b -n1 2>/dev/null | head -12 | tail -6
echo
echo "=== STREAM THROUGHPUT (20s) ==="
A=$(rx); sleep 20; B=$(rx)
echo "inbound: $(( (B-A)*8/20/1000000 )) Mbps"
echo
echo "=== LINK QUALITY DURING PLAY (60 pings) ==="
ping -c 60 -i 0.2 192.168.0.13 2>&1 | tail -3
