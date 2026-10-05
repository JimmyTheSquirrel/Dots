#!/bin/sh
SINK="http://192.168.0.226:9557/"
echo "=== player state ==="
python3 -c "
import socket,json
s=socket.create_connection(('127.0.0.1',9090),8); s.settimeout(8)
s.sendall(json.dumps({'jsonrpc':'2.0','id':1,'method':'Player.GetActivePlayers'}).encode())
print(s.recv(4096).decode()[:160])" 2>/dev/null

echo "=== eth0 link ==="
ethtool eth0 2>/dev/null | grep -E "Speed|Duplex|Link detected"

echo "=== DOWNLOAD (single stream) ==="
curl -s -o /dev/null -m 30 -w '  %{speed_download} B/s\n' "$SINK"
echo "=== DOWNLOAD (aggregate, 4 streams, 10s) ==="
a=$(grep -E "^ *eth0" /proc/net/dev | awk '{print $2}')
for i in 1 2 3 4; do
  ( end=$(( $(date +%s) + 11 ))
    while [ $(date +%s) -lt $end ]; do curl -s -o /dev/null -m 11 "$SINK" 2>/dev/null; done ) &
done
sleep 1; a=$(grep -E "^ *eth0" /proc/net/dev | awk '{print $2}'); sleep 9
b=$(grep -E "^ *eth0" /proc/net/dev | awk '{print $2}'); wait
echo "  aggregate: $(( (b-a)*8/9/1000000 )) Mbps"

echo "=== UPLOAD ==="
dd if=/dev/zero bs=1M count=80 2>/dev/null | curl -s -o /dev/null -m 30 -T - -w '  %{speed_upload} B/s\n' http://192.168.0.226:9557/up

echo "=== PING gateway (40) ==="
ping -c 40 -i 0.2 192.168.0.1 2>&1 | tail -2
