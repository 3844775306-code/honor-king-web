import json, os, re
rec = r"C:\Users\18749\Documents\honor-king\.recover"
items = json.load(open(os.path.join(rec, "replay_all_full.json"), encoding="utf-8"))
pw = [it for it in items if it["name"] == "pwsh"]
print("pwsh ops:", len(pw))
mut = 0
nonmut = 0
for it in pw:
    a = json.loads(it["args"]); c = a.get("command", "")
    is_mut = bool(re.search(r"Set-Content[^\n]*BattleManager", c)) or bool(re.search(r"(write_text|write_bytes)[^\n]*", c) and "BattleManager" in c and "pathlib" in c) or bool(re.search(r"Add-Content[^\n]*BattleManager", c)) or bool(re.search(r"Remove-Item[^\n]*BattleManager", c)) or bool(re.search(r"Out-File[^\n]*BattleManager", c))
    if is_mut: mut += 1
    else: nonmut += 1
print("mutate:", mut, "nonmutate:", nonmut)
