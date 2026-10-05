import socket, json, time

def rpc(method, params=None, _id=1):
    s = socket.create_connection(("127.0.0.1", 9090), 5)
    s.sendall(json.dumps({"jsonrpc":"2.0","id":_id,"method":method,"params":params or {}}).encode())
    dec = json.JSONDecoder()
    buf = ""
    s.settimeout(5)
    deadline = time.time() + 6
    while time.time() < deadline:
        try:
            chunk = s.recv(65536).decode("utf-8", "replace")
        except Exception:
            break
        if not chunk:
            break
        buf += chunk
        idx = 0
        while idx < len(buf):
            try:
                obj, end = dec.raw_decode(buf, idx)
            except ValueError:
                break
            if obj.get("id") == _id:
                s.close()
                return obj
            idx = end
            while idx < len(buf) and buf[idx] in " \r\n\t":
                idx += 1
    s.close()
    return None

pl = rpc("Player.GetActivePlayers", {}, 1)
print("ACTIVE:", json.dumps(pl.get("result") if pl else None))
players = (pl or {}).get("result") or []
if players:
    pid = players[0]["playerid"]
    item = rpc("Player.GetItem", {"playerid": pid, "properties": ["title","showtitle","season","episode","file","runtime"]}, 2)
    print("ITEM:", json.dumps((item or {}).get("result")))
    for i in range(4):
        p = rpc("Player.GetProperties", {"playerid": pid,
              "properties":["cachepercentage","percentage","speed","time","totaltime"]}, 10+i)
        r = (p or {}).get("result", {})
        t = r.get("time", {})
        print("t=%2ds cache=%6.2f%% pos=%02d:%02d:%02d speed=%s" % (
            i*10, r.get("cachepercentage",-1),
            t.get("hours",0), t.get("minutes",0), t.get("seconds",0), r.get("speed")))
        if i < 3:
            time.sleep(10)
