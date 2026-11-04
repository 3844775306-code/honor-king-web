# 伤害审计数据

主菜单进入单机 / 训练营 / 测试前，会在「对局数据」弹窗中询问是否生成本局审计表格。

- 勾选“伤害审计”：本局生成 `damage_audit_<battle/training/test>_<时间戳>.csv`
- 不勾选：本局不记录
- 启动参数加 `--damage-audit` 可跳过弹窗、强制生成（联机/录像不生成）

Excel 报告（按伤害源分 Sheet，每个 Sheet 内按技能分组、组内按游戏时间）：

```powershell
python scripts\debug\damage_audit_report.py
```

输出：`data/damage_audit/damage_audit_report.xlsx`

CSV 字段：

`match, mode, time, src, src_team, tgt, tgt_team, skill, skill_name, magic, crit, raw, pre, res, flat_pen, pen_pct, expected, after_mit, actual, shield, post_delta`
