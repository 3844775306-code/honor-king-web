# 伤害审计数据

单机 / 训练营 / 测试对局开始前会弹窗询问是否生成本局审计表格。

- 选择“生成”：本局生成 `damage_audit_<battle/training/test>_<时间戳>.csv`
- 选择“不生成”：本局不记录
- 启动参数加 `--damage-audit` 可跳过询问、强制生成（联机/录像不生成）

字段：

`match, mode, time, src, src_team, tgt, tgt_team, skill, magic, crit, raw, pre, res, flat_pen, pen_pct, expected, after_mit, actual, shield, post_delta`
