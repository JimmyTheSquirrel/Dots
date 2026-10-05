#!/bin/sh
set -e
SETTINGS=/storage/.kodi/userdata/addon_data/plugin.video.jellyfin/settings.xml

echo "=== 1. capture position + stop playback cleanly ==="
python3 - <<'PY'
import socket, json, time
def rpc(m,p=None,i=1,t=8):
    s=socket.create_connection(("127.0.0.1",9090),t); s.settimeout(t)
    s.sendall(json.dumps({"jsonrpc":"2.0","id":i,"method":m,"params":p or {}}).encode())
    d=json.JSONDecoder(); b=""; end=time.time()+t
    while time.time()<end:
        try: c=s.recv(65536).decode("utf-8","replace")
        except Exception: break
        if not c: break
        b+=c; k=0
        while k<len(b):
            try: o,e=d.raw_decode(b,k)
            except ValueError: break
            if o.get("id")==i: s.close(); return o
            k=e
            while k<len(b) and b[k] in " \r\n\t": k+=1
    s.close(); return None
r=rpc("Player.GetActivePlayers",{},1)
ps=(r or {}).get("result") or []
if ps:
    pid=ps[0]["playerid"]
    p=rpc("Player.GetProperties",{"playerid":pid,"properties":["time","percentage"]},2)
    t=((p or {}).get("result") or {}).get("time",{})
    print("  stopping at %02d:%02d:%02d (%.1f%%)" % (t.get("hours",0),t.get("minutes",0),t.get("seconds",0),
          ((p or {}).get("result") or {}).get("percentage",0)))
    rpc("Player.Stop",{"playerid":pid},3)
    print("  Player.Stop sent")
else:
    print("  nothing playing")
PY
sleep 6

echo "=== 2. stop kodi ==="
systemctl stop kodi
sleep 3

echo "=== 3. back up + edit settings.xml ==="
cp -a "$SETTINGS" "$SETTINGS.bak-bitrate23-$(date +%Y%m%d)"
python3 - "$SETTINGS" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
new, n = re.subn(r'<setting id="maxBitrate"[^>]*>\d+</setting>',
                 '<setting id="maxBitrate">17</setting>', s)
if n != 1:
    sys.exit("FAILED: matched %d maxBitrate settings, expected 1" % n)
open(p, "w", encoding="utf-8").write(new)
print("  maxBitrate -> 17 (20 Mbps)")
PY
grep -E 'maxBitrate|videoPreferredCodec' "$SETTINGS"

echo "=== 4. start kodi ==="
systemctl start kodi
sleep 12
systemctl is-active kodi
