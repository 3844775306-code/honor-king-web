import json, os, subprocess, hashlib, shutil
base = r"C:\Users\18749\Documents\honor-king"
rec = os.path.join(base, ".recover")
ws = os.path.join(rec, "ws")
bm = os.path.join(ws, "scripts", "core", "BattleManager.gd")
snap = os.path.join(rec, "snap")
os.makedirs(snap, exist_ok=True)

subprocess.run(["pwsh", "-NoProfile", "-Command", "git archive HEAD scripts/core/BattleManager.gd | tar -x -C .recover\\ws"], cwd=base, check=True)
raw = open(bm, encoding="utf-8", newline="").read()
raw = raw.replace("\r\n", "\n").replace("\n", "\r\n")
open(bm, "w", encoding="utf-8", newline="").write(raw)

items = json.load(open(os.path.join(rec, "replay_all_full.json"), encoding="utf-8"))
log, applied, skipped, fail = [], 0, 0, 0
for i, it in enumerate(items):
    name = it["name"]
    args = json.loads(it["args"])
    if name == "edit":
        fp = args.get("file_path", "").replace(base, ws)
        old = args.get("old_string", "").replace("\r\n", "\n").replace("\n", "\r\n")
        new = args.get("new_string", "").replace("\r\n", "\n").replace("\n", "\r\n")
        try:
            data = open(fp, encoding="utf-8", newline="").read()
        except Exception:
            continue
        cnt = data.count(old)
        if cnt == 0:
            skipped += 1          # 已包含在 HEAD 基线里
        elif cnt == 1:
            open(fp, "w", encoding="utf-8", newline="").write(data.replace(old, new, 1))
            applied += 1
        else:
            log.append((i, "AMBIG", cnt, old[:60].replace("\r\n", "|"))); fail += 1
    elif name == "pwsh":
        cmd = args.get("command", "").replace("C:\\Users\\18749\\Documents\\honor-king", ws)
        cmd = cmd.replace("\r\n", "\n").replace("\n", "\r\n")
        sf = os.path.join(rec, "step.ps1")
        open(sf, "w", encoding="utf-8", newline="").write(cmd)
        subprocess.run(["pwsh", "-NoProfile", "-File", sf], cwd=ws, capture_output=True, text=True, encoding="utf-8", errors="replace")
        applied += 1
    if (i + 1) % 50 == 0:
        shutil.copy(bm, os.path.join(snap, f"bm_{i+1:04d}.gd"))
        print("progress", i + 1, "applied", applied, "skip", skipped, "fail", fail, "lines", sum(1 for _ in open(bm, "rb")), flush=True)
print("DONE applied", applied, "skipped", skipped, "fail", fail)
lines = sum(1 for _ in open(bm, "rb"))
print("final lines:", lines, "size:", os.path.getsize(bm))
for row in log[-10:]: print(row)
