#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""读取 hero_match_stats.csv，生成英雄强弱 Excel 报告。

用法:
  python scripts/debug/hero_stats_report.py
  python scripts/debug/hero_stats_report.py --input <csv> --output <xlsx> --min-matches 30
"""
import argparse
import csv
import os
from collections import defaultdict
from datetime import datetime

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_DIR = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "HonorKing")
DEFAULT_INPUT = os.path.join(DEFAULT_DIR, "hero_match_stats.csv")
DEFAULT_OUTPUT = os.path.join(DEFAULT_DIR, "hero_balance_report.xlsx")

WEIGHTS = {
    "win": 0.30,
    "damage": 0.25,
    "gold": 0.20,
    "kda": 0.15,
    "survival": 0.10,
}


def fnum(v, default=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def normalize(values):
    """min-max 归一化；全部相同返回 0.5。"""
    if not values:
        return {}
    lo, hi = min(values.values()), max(values.values())
    if hi - lo < 1e-9:
        return {k: 0.5 for k in values}
    return {k: (v - lo) / (hi - lo) for k, v in values.items()}


def load_rows(path):
    with open(path, "r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def build_summary(rows):
    # 每局每队的总伤害/总经济，用于伤害占比、经济占比
    team_damage = defaultdict(float)
    team_gold = defaultdict(float)
    for r in rows:
        key = (r["match_id"], r["team"])
        team_damage[key] += fnum(r["damage_dealt"])
        team_gold[key] += fnum(r["gold"])

    agg = defaultdict(lambda: {
        "matches": 0, "wins": 0,
        "damage": 0.0, "damage_share": 0.0, "damage_per_min": 0.0,
        "gold": 0.0, "gold_share": 0.0, "gold_per_min": 0.0,
        "kills": 0.0, "deaths": 0.0, "assists": 0.0,
        "deaths_per_min": 0.0, "level": 0.0,
    })

    for r in rows:
        hero = r["hero"]
        a = agg[hero]
        a["role"] = r.get("role", "")
        a["matches"] += 1
        dur = max(1.0, fnum(r["duration"]) / 60.0)
        key = (r["match_id"], r["team"])
        a["wins"] += 1 if int(fnum(r["winner"], -1)) == int(fnum(r["team"], -1)) else 0
        dmg = fnum(r["damage_dealt"])
        gold = fnum(r["gold"])
        a["damage"] += dmg
        a["gold"] += gold
        a["damage_share"] += dmg / team_damage[key] if team_damage[key] > 0 else 0.0
        a["gold_share"] += gold / team_gold[key] if team_gold[key] > 0 else 0.0
        a["damage_per_min"] += dmg / dur
        a["gold_per_min"] += gold / dur
        a["kills"] += fnum(r["kills"])
        a["deaths"] += fnum(r["deaths"])
        a["assists"] += fnum(r["assists"])
        a["deaths_per_min"] += fnum(r["deaths"]) / dur
        a["level"] += fnum(r["level"])

    for a in agg.values():
        n = max(1, a["matches"])
        a["win_rate"] = a["wins"] / n
        a["avg_damage_share"] = a["damage_share"] / n
        a["avg_gold_share"] = a["gold_share"] / n
        a["avg_damage_per_min"] = a["damage_per_min"] / n
        a["avg_gold_per_min"] = a["gold_per_min"] / n
        a["avg_kda"] = (a["kills"] + a["assists"]) / max(1.0, a["deaths"])
        a["avg_deaths_per_min"] = a["deaths_per_min"] / n
        a["avg_level"] = a["level"] / n
    return agg


def add_composite(agg, min_matches):
    """按职业分别归一化后算综合分，再算全英雄综合分。"""
    by_role = defaultdict(list)
    for hero, a in agg.items():
        if a["matches"] >= min_matches:
            by_role[a["role"]].append(hero)

    def score_group(heroes):
        if not heroes:
            return
        win_n = normalize({h: agg[h]["win_rate"] for h in heroes})
        dmg_n = normalize({h: agg[h]["avg_damage_share"] for h in heroes})
        gold_n = normalize({h: agg[h]["avg_gold_per_min"] for h in heroes})
        kda_n = normalize({h: agg[h]["avg_kda"] for h in heroes})
        # 每分钟死亡越低越好
        surv_n = normalize({h: -agg[h]["avg_deaths_per_min"] for h in heroes})
        for h in heroes:
            agg[h]["composite"] = (
                WEIGHTS["win"] * win_n[h]
                + WEIGHTS["damage"] * dmg_n[h]
                + WEIGHTS["gold"] * gold_n[h]
                + WEIGHTS["kda"] * kda_n[h]
                + WEIGHTS["survival"] * surv_n[h]
            )

    for heroes in by_role.values():
        score_group(heroes)
    # 全英雄综合分：职业内综合分不能直接平均，改用全局指标重算
    all_heroes = [h for h, a in agg.items() if a["matches"] >= min_matches]
    if all_heroes:
        win_n = normalize({h: agg[h]["win_rate"] for h in all_heroes})
        dmg_n = normalize({h: agg[h]["avg_damage_share"] for h in all_heroes})
        gold_n = normalize({h: agg[h]["avg_gold_per_min"] for h in all_heroes})
        kda_n = normalize({h: agg[h]["avg_kda"] for h in all_heroes})
        surv_n = normalize({h: -agg[h]["avg_deaths_per_min"] for h in all_heroes})
        for h in all_heroes:
            agg[h]["composite_all"] = (
                WEIGHTS["win"] * win_n[h]
                + WEIGHTS["damage"] * dmg_n[h]
                + WEIGHTS["gold"] * gold_n[h]
                + WEIGHTS["kda"] * kda_n[h]
                + WEIGHTS["survival"] * surv_n[h]
            )


def style_sheet(ws, widths):
    header_fill = PatternFill("solid", fgColor="1F4E78")
    header_font = Font(bold=True, color="FFFFFF")
    for c in ws[1]:
        c.fill = header_fill
        c.font = header_font
        c.alignment = Alignment(horizontal="center", vertical="center")
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = "A2"


def hero_row(hero, a, rank_col, rank):
    return [
        hero, a.get("role", ""), a["matches"], a["wins"], round(a["win_rate"], 4),
        round(a["avg_damage_share"], 4), round(a["avg_damage_per_min"], 1),
        round(a["avg_gold_per_min"], 1), round(a["avg_kda"], 2),
        round(a["avg_deaths_per_min"], 3), round(a["avg_level"], 2),
        round(a.get("composite", a.get("composite_all", 0.0)), 4), rank,
    ]


def build_workbook(rows, agg, min_matches, output):
    wb = Workbook()
    headers = ["英雄", "职业", "场次", "胜场", "胜率", "伤害占比", "分均伤害",
               "分均经济", "KDA", "分钟死亡", "平均等级", "综合分", "排名"]
    widths = [14, 10, 8, 8, 10, 12, 12, 12, 10, 12, 10, 10, 8]

    # 原始数据
    ws = wb.active
    ws.title = "原始数据"
    raw_headers = list(rows[0].keys()) if rows else []
    ws.append(raw_headers)
    for r in rows:
        ws.append([r.get(k, "") for k in raw_headers])
    style_sheet(ws, [22, 20, 10, 8, 12, 8, 14, 10, 8, 6, 8, 8, 8, 8, 12, 12, 10, 10, 10, 10, 8, 10])

    # 英雄汇总
    ws = wb.create_sheet("英雄汇总")
    ws.append(headers)
    for hero, a in sorted(agg.items(), key=lambda kv: -kv[1]["matches"]):
        ws.append(hero_row(hero, a, "排名", ""))
    style_sheet(ws, widths)

    # 职业内排名
    ws = wb.create_sheet("职业内排名")
    ws.append(headers)
    roles = defaultdict(list)
    for hero, a in agg.items():
        if a["matches"] >= min_matches:
            roles[a.get("role", "")].append(hero)
    for role in sorted(roles.keys()):
        ranked = sorted(roles[role], key=lambda h: -agg[h].get("composite", 0.0))
        for i, hero in enumerate(ranked, 1):
            ws.append(hero_row(hero, agg[hero], "职业排名", i))
    style_sheet(ws, widths)

    # 全英雄排名
    ws = wb.create_sheet("全英雄排名")
    ws.append(headers)
    ranked = sorted(
        [h for h, a in agg.items() if a["matches"] >= min_matches],
        key=lambda h: -agg[h].get("composite_all", 0.0),
    )
    for i, hero in enumerate(ranked, 1):
        row = hero_row(hero, agg[hero], "总排名", i)
        row[11] = round(agg[hero].get("composite_all", 0.0), 4)
        ws.append(row)
    style_sheet(ws, widths)

    # 强势/弱势候选
    ws = wb.create_sheet("强弱候选")
    ws.append(["类型", "英雄", "职业", "场次", "胜率", "伤害占比", "KDA", "综合分", "说明"])
    for label, subset in [
        ("强势候选", ranked[:5]),
        ("弱势候选", ranked[-5:] if len(ranked) >= 5 else ranked),
    ]:
        for hero in subset:
            a = agg[hero]
            note = "样本充足" if a["matches"] >= min_matches else "样本不足"
            ws.append([label, hero, a.get("role", ""), a["matches"],
                       round(a["win_rate"], 4), round(a["avg_damage_share"], 4),
                       round(a["avg_kda"], 2), round(a.get("composite_all", 0.0), 4), note])
    style_sheet(ws, [12, 14, 10, 8, 10, 12, 10, 10, 14])

    wb.save(output)
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default=DEFAULT_INPUT)
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--min-matches", type=int, default=30)
    args = parser.parse_args()

    if not os.path.exists(args.input):
        raise SystemExit(f"找不到数据文件: {args.input}")
    rows = load_rows(args.input)
    if not rows:
        raise SystemExit("数据文件为空")
    agg = build_summary(rows)
    add_composite(agg, args.min_matches)
    out = build_workbook(rows, agg, args.min_matches, args.output)
    enough = sum(1 for a in agg.values() if a["matches"] >= args.min_matches)
    print(f"英雄数={len(agg)} 达到{args.min_matches}场={enough} 总对局={len({r['match_id'] for r in rows})}")
    print(f"报告已生成: {out}")


if __name__ == "__main__":
    main()
