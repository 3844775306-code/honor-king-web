Remove-Item .tmp\mage_test* , .tmp\lanes_test* , .tmp\mage.log , .tmp\mage2.log , .tmp\lanes.log -Force -ErrorAction SilentlyContinue
git add -A 2>&1 | Out-String | Out-Null
git commit --quiet -m "fix(ai): 法师开局不走中路

1) _try_mid_switch 在开局第一秒就触发：兵线还没生成（BattleManager 每帧只出 2 个兵），
   _has_enemy_minions_on_lane(MID) 必为 false + 无目标 → 法师随机换到边路；
   mid_switched_lane 置位后要 30s 无目标或中路塔告急才回中，等于整局前期不在中路。
   → 加开局保护 30s + 中路静默 6s 才允许游走。
2) _get_lane_default_pos 发育路/对抗路兜底点都落中路上 (x+z=0)，且 AI 先于防御塔创建，
   开局 default_bush_pos 算错位置 → 改为几何中点，并在塔生成后补算一次。
实测：法师 lane=1 持续走中路，射手/辅助走发育路，打野走野区。" 2>&1 | Out-String
git log --oneline -2
pwsh -NoProfile -File scripts\dev\notify.ps1 -Title "HonorKing · 法师开局不走中路" -Message "已定位并修复：中路游走逻辑开局误判，法师开局即被换去边路" | Out-Null