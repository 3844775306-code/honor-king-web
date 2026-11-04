param(
    [int]$TargetPerHero = 30,
    [int]$MaxMatches = 200,
    [double]$Speed = 10.0
)
# 英雄强弱批量采样：反复跑 --hero-stats-batch 完整 AI 对局，直到每个英雄场次达标。
# 用法: pwsh -NoProfile -File scripts\debug\run_hero_stats_batch.ps1 -TargetPerHero 30 -MaxMatches 200 -Speed 10

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$godot = Join-Path $root ".cache\godot47.exe"
$csv = Join-Path $env:APPDATA "Godot\app_userdata\HonorKing\hero_match_stats.csv"

if (-not (Test-Path $godot)) {
    throw "找不到 Godot: $godot"
}

function Get-Counts {
    if (-not (Test-Path $csv)) { return @{} }
    $rows = Import-Csv $csv -Encoding UTF8
    $counts = @{}
    foreach ($r in $rows) {
        $n = [string]$r.hero
        if ($n -eq "") { continue }
        if ($counts.ContainsKey($n)) { $counts[$n]++ } else { $counts[$n] = 1 }
    }
    return $counts
}

$run = 0
while ($run -lt $MaxMatches) {
    $counts = Get-Counts
    $short = @($counts.GetEnumerator() | Where-Object { $_.Value -lt $TargetPerHero })
    # 尚未出现过的英雄也算未达标；29 个英雄（排除元流之子）
    $all = @("狄仁杰","马可波罗","孙尚香","马超","吕布","沈梦溪","不知火舞","甄姬","铠","亚瑟",
             "太乙真人","东皇太一","李白","兰陵王","张飞","安琪拉","妲己","小乔","鲁班七号","王昭君",
             "夏侯惇","后羿","李元芳","大禹","刘禅","孙悟空","英睿")
    $missing = @($all | Where-Object { -not $counts.ContainsKey($_) -or $counts[$_] -lt $TargetPerHero })
    if ($missing.Count -eq 0) {
        Write-Host "所有英雄均达到 $TargetPerHero 场，停止。"
        break
    }
    $run++
    Write-Host ("[{0}/{1}] 开始第 {2} 局，未达标英雄 {3} 个，当前最少场次 {4}" -f $run, $MaxMatches, $run, $missing.Count, ($(if ($counts.Count) { ($counts.Values | Measure-Object -Minimum).Minimum } else { 0 })))
    $args = @(
        "--headless", "--path", $root,
        "res://scenes/battle.tscn",
        "--",
        "--hero-stats-batch",
        "--hero-stats-speed=$Speed"
    )
    $p = Start-Process -FilePath $godot -ArgumentList $args -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(900000)) {
        Write-Warning "第 $run 局超时，强制结束"
        $p.Kill()
    }
    Start-Sleep -Milliseconds 300
}

$counts = Get-Counts
Write-Host "采样结束。各英雄场次："
$counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0,-8} {1}" -f $_.Name, $_.Value }
Write-Host "原始数据: $csv"
Write-Host "生成 Excel: python scripts\debug\hero_stats_report.py"
