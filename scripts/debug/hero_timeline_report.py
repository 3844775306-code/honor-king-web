#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""读取 hero_timeline_stats.csv，按职业平均绘制金币/经验(等级)随时间曲线。

用法:
  python scripts/debug/hero_timeline_report.py
  python scripts/debug/hero_timeline_report.py --input data/hero_stats/hero_timeline_stats.csv --output data/hero_stats/hero_timeline_report.xlsx
"""
import argparse
import csv
import os
from collections import defaultdict

from openpyxl import Workbook
from openpyxl.chart import LineChart, Reference
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_INPUT = os.path.join(ROOT, "data", "hero_stats", "hero_timeline_stats.csv")
DEFAULT_OUTPUT = os.path.join(ROOT, "data", "hero_stats", "hero_timeline_report.xlsx")


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


def build_series(rows):
    # role -> time -> [sum, n]
    data = defaultdict(lambda: defaultdict(lambda: [0.0, 0.0, 0]))
    max_minute = 0
    for r in rows:
        role = r.get("role", "") or "未知"
        t = int(float(r.get("time_min", 0) or 0))
        if t <= 0:
            continue
        max_minute = max(max_minute, t)
        cell = data[role][t]
        cell[0] += float(r.get("gold", 0) or 0)
        cell[1] += float(r.get("level", 0) or 0)
        cell[2] += 1
    roles = sorted(data.keys())
    return data, roles, max_minute


def add_metric_sheet(wb, title, data, roles, max_minute, metric_idx, y_title):
    ws = wb.create_sheet(title)
    ws.append(["分钟"] + roles)
    for t in range(1, max_minute + 1):
        row = [t]
        for role in roles:
            cell = data[role].get(t)
            row.append(round(cell[metric_idx] / cell[2], 2) if cell and cell[2] else None)
        ws.append(row)
    style_sheet(ws, [8] + [14] * len(roles))

    chart = LineChart()
    chart.title = title
    chart.y_axis.title = y_title
    chart.x_axis.title = "游戏时间（分钟）"
    chart.height = 10
    chart.width = 22
    data_ref = Reference(ws, min_col=2, max_col=1 + len(roles), min_row=1, max_row=max_minute + 1)
    cats = Reference(ws, min_col=1, min_row=2, max_row=max_minute + 1)
    chart.add_data(data_ref, titles_from_data=True)
    chart.set_categories(cats)
    ws.add_chart(chart, "K2")
    return ws


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=DEFAULT_INPUT)
    ap.add_argument("--output", default=DEFAULT_OUTPUT)
    args = ap.parse_args()
    if not os.path.exists(args.input):
        raise SystemExit(f"找不到时间线数据: {args.input}")
    with open(args.input, "r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit("时间线数据为空")
    data, roles, max_minute = build_series(rows)

    wb = Workbook()
    ws0 = wb.active
    ws0.title = "说明"
    ws0.append(["项目", "内容"])
    ws0.append(["数据文件", args.input])
    ws0.append(["样本局数", len(set(r.get("match_id", "") for r in rows))])
    ws0.append(["职业", "、".join(roles)])
    ws0.append(["最大分钟", max_minute])
    ws0.append(["金币/等级", "按职业在该分钟的所有英雄样本取平均"])
    style_sheet(ws0, [18, 80])

    add_metric_sheet(wb, "职业金币曲线", data, roles, max_minute, 0, "金币")
    add_metric_sheet(wb, "职业等级曲线", data, roles, max_minute, 1, "等级")

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    wb.save(args.output)
    print(f"职业={len(roles)} 最大分钟={max_minute} 输出={args.output}")


if __name__ == "__main__":
    main()
