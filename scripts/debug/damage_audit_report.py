#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 damage_audit CSV 拆成按伤害源分 Sheet 的 Excel。

每个 Sheet = 一个伤害源（英雄）；
Sheet 内按 skill 分组，同 skill 连续，组内按游戏时间升序。

用法:
  python scripts/debug/damage_audit_report.py
  python scripts/debug/damage_audit_report.py --input-dir data/damage_audit_raw --output data/damage_audit/damage_audit_report.xlsx
"""
import argparse
import csv
import os
from collections import defaultdict

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW_DIR = os.path.join(ROOT, "data", "damage_audit_raw")
OUT_DIR = os.path.join(ROOT, "data", "damage_audit")
DEFAULT_OUTPUT = os.path.join(OUT_DIR, "damage_audit_report.xlsx")

SKILL_NAMES = {
    0: "普攻", 1: "技能1", 2: "技能2", 3: "技能3",
    -1: "被动", -2: "红buff灼烧", -10: "红莲斗篷(灼烧)", -11: "反伤刺甲(反伤)",
    -20: "闪电匕首(链式电弧)", -22: "金色圣剑(AP附伤)", -23: "巫术法杖(强化普攻)",
    -25: "凝冰之息(普攻附伤)", -26: "无尽战刃(暴击)", -27: "回响之杖(爆炸)",
    -28: "痛苦面具(灼烧)", -30: "日渊(溅射)", -41: "血魔之怒(附伤)",
    -42: "反伤刺甲(反弹)", -43: "闪电匕首(技能触发)", -44: "冰霜冲击(主动)",
    -45: "东皇能量体", -46: "兰陵王标记", -47: "张飞变身附伤", -48: "亚瑟标记",
    -49: "终结", -50: "惩击", -51: "王昭君冰霜冲击", -52: "王昭君强化普攻",
}


def safe_sheet_name(name, used):
    base = "".join(c for c in str(name) if c not in "[]:*?/\\").strip() or "未知"
    base = base[:31]
    out = base
    i = 2
    while out in used:
        suffix = f"_{i}"
        out = (base[:31 - len(suffix)] + suffix)
        i += 1
    used.add(out)
    return out


def load_rows(input_dir, single_file=None):
    paths = [single_file] if single_file else sorted(
        os.path.join(input_dir, f) for f in os.listdir(input_dir) if f.lower().endswith(".csv")
    )
    rows = []
    for path in paths:
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                if not r.get("src") or r.get("src") == "null":
                    continue
                sid = int(float(r.get("skill", 0) or 0))
                r["_skill_id"] = sid
                r["_skill_name"] = r.get("skill_name") or SKILL_NAMES.get(sid, f"技能{sid}")
                r["_time"] = float(r.get("time", 0) or 0)
                r["_match"] = r.get("match", "")
                r.setdefault("_file", os.path.basename(path))
                rows.append(r)
    return rows


def fnum(v):
    try:
        return float(v or 0)
    except (TypeError, ValueError):
        return 0.0


def style_sheet(ws, widths):
    fill = PatternFill("solid", fgColor="1F4E78")
    font = Font(bold=True, color="FFFFFF")
    for c in ws[1]:
        c.fill = fill
        c.font = font
        c.alignment = Alignment(horizontal="center", vertical="center")
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = ws.dimensions


def build_workbook(rows, output):
    wb = Workbook()
    ws0 = wb.active
    ws0.title = "汇总"
    by_src = defaultdict(list)
    for r in rows:
        by_src[r["src"]].append(r)

    headers = ["技能ID", "技能", "时间", "目标", "目标阵营", "类型", "暴击",
               "raw", "减伤前", "有效抗性", "固定穿透", "百分比穿透",
               "expected", "减伤后", "实际", "护盾吸收", "post_delta", "对局", "模式"]
    widths = [8, 20, 9, 14, 8, 8, 7, 11, 11, 11, 10, 11, 11, 11, 11, 10, 12, 22, 11]
    ws0.append(["伤害源", "事件数", "总raw", "总expected", "总实际", "总护盾", "技能数"])
    for src, rs in sorted(by_src.items(), key=lambda kv: -len(kv[1])):
        skills = len(set(r["_skill_id"] for r in rs))
        ws0.append([src, len(rs), round(sum(fnum(r.get("raw")) for r in rs), 1),
                    round(sum(fnum(r.get("expected")) for r in rs), 1),
                    round(sum(fnum(r.get("actual")) for r in rs), 1),
                    round(sum(fnum(r.get("shield")) for r in rs), 1), skills])
    style_sheet(ws0, [16, 10, 12, 12, 12, 12, 8])

    used = set(wb.sheetnames)
    # 原始数据
    ws_raw = wb.create_sheet("原始数据")
    raw_headers = ["伤害源", "技能ID", "技能", "时间", "目标", "目标阵营", "类型", "暴击",
                   "raw", "减伤前", "有效抗性", "固定穿透", "百分比穿透",
                   "expected", "减伤后", "实际", "护盾吸收", "post_delta", "对局", "模式"]
    ws_raw.append(raw_headers)
    for r in sorted(rows, key=lambda x: (x["src"], x["_skill_id"], x["_match"], x["_time"])):
        ws_raw.append([r["src"], r["_skill_id"], r["_skill_name"], r["_time"], r["tgt"],
                       r.get("tgt_team", ""), "法术" if str(r.get("magic", "0")) == "1" else "物理",
                       "是" if str(r.get("crit", "0")) == "1" else "",
                       fnum(r.get("raw")), fnum(r.get("pre")), fnum(r.get("res")),
                       fnum(r.get("flat_pen")), fnum(r.get("pen_pct")),
                       fnum(r.get("expected")), fnum(r.get("after_mit")), fnum(r.get("actual")),
                       fnum(r.get("shield")), fnum(r.get("post_delta")), r["_match"], r.get("mode", "")])
    style_sheet(ws_raw, [16, 8, 20, 9, 14, 8, 8, 7, 11, 11, 11, 10, 11, 11, 11, 11, 10, 12, 22, 11])

    # 每个伤害源一个 Sheet
    for src, rs in sorted(by_src.items(), key=lambda kv: kv[0]):
        ws = wb.create_sheet(safe_sheet_name(src, used))
        ws.append(headers)
        ordered = sorted(rs, key=lambda x: (x["_skill_id"], x["_skill_name"], x["_match"], x["_time"]))
        sentinel = object()
        last_skill = sentinel
        for r in ordered:
            sk = (r["_skill_id"], r["_skill_name"])
            # 同一 skill 连续；换 skill 时留空行，方便肉眼分组
            if last_skill is not sentinel and sk != last_skill:
                ws.append([])
            last_skill = sk
            ws.append([r["_skill_id"], r["_skill_name"], r["_time"], r["tgt"], r.get("tgt_team", ""),
                       "法术" if str(r.get("magic", "0")) == "1" else "物理",
                       "是" if str(r.get("crit", "0")) == "1" else "",
                       fnum(r.get("raw")), fnum(r.get("pre")), fnum(r.get("res")),
                       fnum(r.get("flat_pen")), fnum(r.get("pen_pct")),
                       fnum(r.get("expected")), fnum(r.get("after_mit")), fnum(r.get("actual")),
                       fnum(r.get("shield")), fnum(r.get("post_delta")), r["_match"], r.get("mode", "")])
        style_sheet(ws, widths)

    os.makedirs(os.path.dirname(os.path.abspath(output)), exist_ok=True)
    wb.save(output)
    return output


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-dir", default=RAW_DIR)
    ap.add_argument("--input", default="", help="只处理单个 CSV")
    ap.add_argument("--output", default=DEFAULT_OUTPUT)
    args = ap.parse_args()
    rows = load_rows(args.input_dir, args.input or None)
    if not rows:
        raise SystemExit(f"没有可用的 damage_audit 数据: {args.input_dir}")
    out = build_workbook(rows, args.output)
    print(f"伤害源={len(set(r['src'] for r in rows))} 事件={len(rows)}")
    print(f"报告已生成: {out}")


if __name__ == "__main__":
    main()
