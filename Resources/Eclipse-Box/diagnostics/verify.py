import socket, json, time, subprocess

def rpc(m, p=None, i=1, t=10):
    s = socket.create_connection(("127.0.0.1", 9090), t); s.settimeout(t)
    s.sendall(json.dumps({"jsonrpc":"2.0","id":i,"method":m,"params":p or {}}).encode())
    d = json.JSONDecoder(); b = ""; end = time.time() + t
    while time.time() < end:
        try: c = s.recv(65536).decode("utf-8", "replace")
        except Exception: break
        if not c: break
        b += c; k = 0
        while k < len(b):
            try: o, e = d.raw_decode(b, k)
            except ValueError: break
            if o.get("id") == i: s.close(); return o
            k = e
            while k < len(b) and b[k] in " \r\n\t": k += 1
    s.close(); return None

URL = ("plugin://plugin.video.jellyfin/f137a2dd21bbc1b99aa5c0f6bf02a805/"
       "?filename=The+Drama.2026.2160p.UHD.BluRay.HDR10%2B.DoVi.TrueHD+7.1.Atmos.x265-SPHD.mkv"
       "&id=492792a673bcba9868b8885b1bbb128e&dbid=30&mode=play")

print("opening player...")
rpc("Player.Open", {"item": {"file": URL}}, 1, t=20)

def rx():
    for ln in open("/proc/net/dev"):
        if ln.strip().startswith("eth0"):
            return int(ln.split()[1])
    return 0

started = None
last = rx(); tlast = time.time()
for n in range(20):
    time.sleep(9)
    now = rx(); tnow = time.time()
    mbps = (now - last) * 8 / (tnow - tlast) / 1e6
    last, tlast = now, tnow
    r = rpc("Player.GetActivePlayers", {}, 2)
    ps = (r or {}).get("result") or []
    if not ps:
        print("%3ds  no player yet   net=%5.1f Mbps" % (n*9, mbps)); continue
    pid = ps[0]["playerid"]
    p = rpc("Player.GetProperties", {"playerid": pid,
            "properties": ["cachepercentage","percentage","speed","time"]}, 3)
    res = (p or {}).get("result") or {}
    tm = res.get("time", {})
    pos = tm.get("hours",0)*3600 + tm.get("minutes",0)*60 + tm.get("seconds",0)
    if started is None and pos > 0: started = (pos, time.time())
    print("%3ds  pos=%02d:%02d  cache=%5.1f%%  speed=%s  net=%5.1f Mbps"
          % (n*9, pos//60, pos%60, res.get("cachepercentage",-1), res.get("speed"), mbps))
    if started and time.time() - started[1] > 70:
        played = pos - started[0]; wall = time.time() - started[1]
        print("  --> played %ds of video in %ds wall = %.2fx realtime" % (played, wall, played/wall))
        break
