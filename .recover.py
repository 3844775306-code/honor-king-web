import zstandard, os, glob
d = r"C:\Users\18749\.dsh\sessions\--C-Users-18749-Documents-honor-king--"
files = sorted(glob.glob(os.path.join(d, "**", "session.v4.jsonl.zstd"), recursive=True), key=os.path.getmtime, reverse=True)
out_dir = r"C:\Users\18749\Documents\honor-king\.recover"
os.makedirs(out_dir, exist_ok=True)
for f in files:
    raw = open(f, "rb").read()
    parts, pos = [], 0
    try:
        while pos < len(raw):
            dobj = zstandard.ZstdDecompressor().decompressobj()
            parts.append(dobj.decompress(raw[pos:]))
            parts.append(dobj.flush())
            un = dobj.unused_data
            pos = len(raw) - len(un) if un else len(raw)
    except Exception as e:
        print("ERR", os.path.basename(os.path.dirname(f))[:8], e, "at", pos); continue
    data = b"".join(parts)
    key = os.path.basename(os.path.dirname(f))
    name = key[:8] + "_" + str(int(os.path.getmtime(f))) + ".jsonl"
    open(os.path.join(out_dir, name), "wb").write(data)
    print(name, len(data), "endseq=", b"_play_end_sequence" in data, "explosion=", b"_crystal_explosion" in data)
