#!/usr/bin/env python3
"""三端「表现」对齐审计：按 scripts/dev/presentation_features.json 的功能清单，
在各端源码范围里做正则探测，输出 docs/ui_parity_report.md 与控制台差异摘要。

用法：
  python scripts/dev/presentation_audit.py        # 生成报告，打印缺口
  python scripts/dev/presentation_audit.py --strict
  python scripts/dev/presentation_audit.py --quiet
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from pathlib import Path

try:  # Windows 控制台默认 cp936，强制 UTF-8，避免中文报告乱码
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "scripts" / "dev" / "presentation_features.json"
REPORT = ROOT / "docs" / "presentation_report.md"
SIDE_ORDER = ["host", "net", "replay"]
SIDE_LABEL = {"host": "单机", "net": "联机", "replay": "回放"}


def load_registry() -> dict:
    with REGISTRY.open("r", encoding="utf-8") as f:
        return json.load(f)


def gather_texts(paths: list[str]) -> str:
    """把某端所有源码拼成一段（只扫 .gd），用于正则探测。"""
    chunks: list[str] = []
    for rel in paths:
        p = ROOT / rel
        if p.is_file() and p.suffix == ".gd":
            chunks.append(p.read_text(encoding="utf-8", errors="ignore"))
        elif p.is_dir():
            for f in sorted(p.rglob("*.gd")):
                chunks.append(f.read_text(encoding="utf-8", errors="ignore"))
    return "\n".join(chunks)


def probe(patterns: list[str], text: str) -> bool:
    for pat in patterns:
        try:
            if re.search(pat, text, re.MULTILINE):
                return True
        except re.error:
            # 非法正则按字面量兜底，避免审计工具本身炸掉
            if pat in text:
                return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="存在未接受缺口时退出码 1")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    reg = load_registry()
    sides: dict[str, str] = {}
    for side, paths in reg["meta"]["sides"].items():
        sides[side] = gather_texts(paths)

    rows = []
    gaps: list[str] = []
    for feat in reg["features"]:
        fid = str(feat["id"])
        target = list(feat.get("target", []))
        accepted = dict(feat.get("accepted", {}))
        pats = feat.get("patterns", {})
        found: dict[str, bool] = {}
        for side in SIDE_ORDER:
            sp = pats.get(side, [])
            found[side] = probe(sp, sides[side]) if sp else False
        missing = [s for s in target if not found[s] and s not in accepted]
        accepted_missing = [s for s in target if not found[s] and s in accepted]
        rows.append({
            "id": fid,
            "name": str(feat.get("name", fid)),
            "target": target,
            "found": found,
            "missing": missing,
            "accepted": accepted_missing,
        })
        for s in missing:
            gaps.append(f"{SIDE_LABEL[s]}缺：{feat.get('name', fid)}（{fid}）")

    # 控制台摘要
    if not args.quiet:
        print("=" * 86)
        print("三端表现对齐审计")
        print("=" * 86)
        for r in rows:
            flags = "  ".join(
                f"{SIDE_LABEL[s]}:{'OK' if r['found'][s] else ('--' if s not in r['target'] else ('(接受)' if s in r['accepted'] else 'MISS'))}"
                for s in SIDE_ORDER
            )
            print(f"{r['name'][:26]:<28} {flags}")
        print("-" * 86)
        if gaps:
            print(f"未接受缺口 {len(gaps)} 项：")
            for g in gaps:
                print("  -", g)
        else:
            print("未接受缺口 0 项（三端目标功能均已具备）")

    # 报告
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    now = _dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# 三端表现对齐报告",
        "",
        f"- 生成时间：{now}",
        "- 生成方式：`python scripts/dev/ui_parity_audit.py`",
        "- 数据源：`scripts/dev/presentation_features.json`（正则探测，命中即视为该端具备）",
        "",
        f"## 未接受缺口：{len(gaps)} 项",
        "",
    ]
    if gaps:
        lines += [f"{i + 1}. {g}" for i, g in enumerate(gaps)]
    else:
        lines.append("无。")
    lines += ["", "## 全量清单", "", "| 功能 | 目标端 | 单机 | 联机 | 回放 |", "|---|---|---|---|---|"]
    for r in rows:
        def cell(s: str) -> str:
            if s not in r["target"]:
                return "—"
            if r["found"][s]:
                return "✅"
            return "⚠️ 接受" if s in r["accepted"] else "❌ 缺"
        lines.append(f"| {r['name']} | {'/'.join(SIDE_LABEL[s] for s in r['target'])} | {cell('host')} | {cell('net')} | {cell('replay')} |")
    lines += ["", "> 接受 = 设计性差异（如观战端无商店/触控），不计为缺口。", ""]
    REPORT.write_text("\n".join(lines), encoding="utf-8")
    if not args.quiet:
        print(f"\n报告已写入 {REPORT.relative_to(ROOT)}")
    return 1 if (gaps and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
