import json, os, subprocess, re, hashlib
base = r"C:\Users\18749\Documents\honor-king"
rec = os.path.join(base, ".recover")
ws = os.path.join(rec, "ws")
bm = os.path.join(ws, "scripts", "core", "BattleManager.gd")

subprocess.run(["pwsh", "-NoProfile", "-Command", "git archive HEAD scripts/core/BattleManager.gd | tar -x -C .recover\\ws"], cwd=base, check=True)
raw = open(bm, encoding="utf-8", newline="").read().replace("\r\n", "\n").replace("\n", "\r\n")
open(bm, "w", encoding="utf-8", newline="").write(raw)

items = json.load(open(os.path.join(rec, "replay_all_full.json"), encoding="utf-8"))
stats = {"edit_apply":0, "edit_skip_ok":0, "edit_skip_missing":0, "edit_ambig":0, "pwsh_run":0, "pwsh_skip":0}
missing = []
for i, it in enumerate(items):
    args = json.loads(it["args"])
    if it["name"] == "edit":
        fp = args.get("file_path", "").replace(base, ws)
        old = args.get("old_string", "").replace("\r\n", "\n").replace("\n", "\r\n")
        new = args.get("new_string", "").replace("\r\n", "\n").replace("\n", "\r\n")
        try: data = open(fp, encoding="utf-8", newline="").read()
        except Exception: continue
        cnt = data.count(old)
        if cnt == 1:
            open(fp, "w", encoding="utf-8", newline="").write(data.replace(old, new, 1)); stats["edit_apply"] += 1
        elif cnt == 0:
            # new_string 的关键片段是否已在文件里？用于判断“已应用”
            probe = new.strip().split("\n")[0].strip()
            if probe and probe in data: stats["edit_skip_ok"] += 1
            else:
                stats["edit_skip_missing"] += 1; missing.append((i, "EDIT", probe[:60]))
        else:
            stats["edit_ambig"] += 1
    else:
        c = args.get("command", "")
        is_mut = ("BattleManager" in c) and (bool(re.search(r"Set-Content|Add-Content|Out-File|Remove-Item|Move-Item|Copy-Item", c)) or "pathlib" in c)
        if not is_mut:
            stats["pwsh_skip"] += 1
            continue
        cmd = c.replace("C:\\Users\\18749\\Documents\\honor-king", ws).replace("\r\n", "\n").replace("\n", "\r\n")
        sf = os.path.join(rec, "step.ps1")
        open(sf, "w", encoding="utf-8", newline="").write(cmd)
        subprocess.run(["pwsh", "-NoProfile", "-File", sf], cwd=ws, capture_output=True, text=True, encoding="utf-8", errors="replace")
        stats["pwsh_run"] += 1
    if (i + 1) % 100 == 0:
        print("p", i+1, stats, "lines", sum(1 for _ in open(bm,"rb")), flush=True)
print("STATS", stats)
print("lines", sum(1 for _ in open(bm, "rb")))
for m in missing[:15]: print("MISSING", m)
