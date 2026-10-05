#!/bin/sh
set -e
S=/storage/.kodi/userdata/addon_data/plugin.video.jellyfin/settings.xml
python3 -c "
import socket,json
s=socket.create_connection(('127.0.0.1',9090),8); s.settimeout(8)
s.sendall(json.dumps({'jsonrpc':'2.0','id':1,'method':'Player.GetActivePlayers'}).encode())
print('players before:', s.recv(4096).decode()[:120])"
systemctl stop kodi
sleep 3
python3 - "$S" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
new, n = re.subn(r'<setting id="maxBitrate"[^>]*>\d+</setting>',
                 '<setting id="maxBitrate" default="true">23</setting>', s)
if n != 1:
    sys.exit("FAILED: matched %d, expected 1" % n)
open(p, "w", encoding="utf-8").write(new)
print("  maxBitrate -> 23 (uncapped, 1000 Mbps)")
PY
grep -E 'maxBitrate|videoPreferredCodec' "$S"
systemctl start kodi
sleep 12
echo "kodi: $(systemctl is-active kodi)"
