import json, glob, os, datetime
tz = datetime.timezone(datetime.timedelta(hours=8))
d = r"C:\Users\18749\Documents\honor-king\.recover"
wr_end = datetime.datetime(2026, 10, 31, 23, 26, 0, tzinfo=tz).timestamp() * 1000
import re
pw = re.compile(r"Set-Content|Add-Content|Insert-Content|Remove-Item.*BattleManager|Move-Item.*BattleManager|Copy-Item.*BattleManager", re.I)
seen = {}
for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
    for ln in open(f, "rb").read().split(b"\n"):
        if b"BattleManager" not in ln: continue
        try: o = json.loads(ln)
        except Exception: continue
        if o.get("type") != "tool/call": continue
        t = o.get("time", 0)
        if t > wr_end: continue
        data = o.get("data", {})
        cid = data.get("callId"); a = data.get("arguments", ""); name = data.get("name")
        ok = False
        if name == "pwsh" and pw.search(a): ok = True
        elif name in ("edit", "write"):
            try: arg = json.loads(a)
            except Exception: arg = {}
            if "BattleManager" in str(arg.get("file_path", "")): ok = True
        if ok and cid not in seen:
            seen[cid] = {"time": t, "name": name, "args": a, "callId": cid}
items = sorted(seen.values(), key=lambda x: x["time"])
print("total ops:", len(items))
print("first:", datetime.datetime.fromtimestamp(items[0]["time"]/1000, tz))
print("last:", datetime.datetime.fromtimestamp(items[-1]["time"]/1000, tz))
json.dump(items, open(os.path.join(d, "replay_all_full.json"), "w", encoding="utf-8"), ensure_ascii=False)
