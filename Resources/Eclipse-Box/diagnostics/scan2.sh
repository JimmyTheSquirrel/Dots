#!/bin/sh
echo "=== raw counter check ==="
grep -E "eth0" /proc/net/dev | head -2
A=$(awk -F'[: ]+' '/eth0/{for(i=1;i<=NF;i++) if($i=="eth0"){print $(i+1); exit}}' /proc/net/dev)
echo "A=$A"
sleep 15
B=$(awk -F'[: ]+' '/eth0/{for(i=1;i<=NF;i++) if($i=="eth0"){print $(i+1); exit}}' /proc/net/dev)
echo "B=$B"
echo "delta bytes: $((B-A))"
echo "inbound: $(( (B-A)*8/15/1000000 )) Mbps"
