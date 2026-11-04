# 伤害审计数据

启动参数加 `--damage-audit` 后，每局生成一个 CSV 表格：

- `damage_audit_<battle/training>_<时间戳>.csv`

字段：

`match, mode, time, src, src_team, tgt, tgt_team, skill, magic, crit, raw, pre, res, flat_pen, pen_pct, expected, after_mit, actual, shield, post_delta`
