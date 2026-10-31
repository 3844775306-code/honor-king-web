# net_integration_test.ps1 — M0+M1 双无头进程联机冒烟测试
#   1) 启动"房主"：headless + --net-host 7000 + --net-test（BattleManager 自动开局跑 AI 对局）
#   2) 启动"客户端"：headless + net_client.tscn + --net-join 127.0.0.1:7000 + --net-test
#   3) 等客户端收到几帧快照（[Net] snap #… heroes=N），断言 N 与无 SCRIPT ERROR，然后杀掉两个进程
# 用法：pwsh scripts/net/net_integration_test.ps1 [-Port 7011]
# 默认 7000；与本机正在跑的 host 撞端口时（err=20），可指定其它空闲端口复跑。

param([int]$Port = 7000)
$ErrorActionPreference = "Stop"
$G    = "C:\Users\18749\Desktop\Godot_v4.5.1-stable_win64.exe"
$dir  = "C:\Users\18749\Documents\honor-king"
$hostOut = "$env:TEMP\hkn_host.log"; $hostErr = "$env:TEMP\hkn_host.err"
$cliOut  = "$env:TEMP\hkn_cli.log";  $cliErr  = "$env:TEMP\hkn_cli.err"
Remove-Item $hostOut,$hostErr,$cliOut,$cliErr -ErrorAction SilentlyContinue

$hp = $null; $cp = $null
try {
    $hostArgs = @("--headless","--path",$dir,"--","--net-host",$Port,"--net-test")
    $hp = Start-Process -FilePath $G -ArgumentList $hostArgs `
        -RedirectStandardOutput $hostOut -RedirectStandardError $hostErr -PassThru -WindowStyle Hidden
    Write-Output "[i] host started pid=$($hp.Id), waiting for battle boot…"
    Start-Sleep -Seconds 8

    $cliArgs = @("--headless","--path",$dir,"res://scenes/net_client.tscn","--","--net-join","127.0.0.1:$Port","--net-test")
    $cp = Start-Process -FilePath $G -ArgumentList $cliArgs `
        -RedirectStandardOutput $cliOut -RedirectStandardError $cliErr -PassThru -WindowStyle Hidden
    Write-Output "[i] client started pid=$($cp.Id), waiting for snapshots…"
    Start-Sleep -Seconds 20
}
finally {
    if ($hp -and -not $hp.HasExited) { Stop-Process -Id $hp.Id -Force -ErrorAction SilentlyContinue }
    if ($cp -and -not $cp.HasExited) { Stop-Process -Id $cp.Id -Force -ErrorAction SilentlyContinue }
}

function Read-Safe([string]$p){ if (Test-Path $p) { Get-Content $p -Raw } else { "" } }
$ho = Read-Safe $hostOut; $he = Read-Safe $hostErr
$co = Read-Safe $cliOut;  $ce = Read-Safe $cliErr

Write-Output "===== HOST stdout (tail 12) ====="
($ho -split "`n") | Where-Object { $_ } | Select-Object -Last 12
Write-Output "===== HOST stderr (tail 6) ====="
($he -split "`n") | Where-Object { $_ } | Select-Object -Last 6
Write-Output "===== CLIENT stdout (tail 16) ====="
($co -split "`n") | Where-Object { $_ } | Select-Object -Last 16
Write-Output "===== CLIENT stderr (tail 6) ====="
($ce -split "`n") | Where-Object { $_ } | Select-Object -Last 6

$ok = $true
# M2：接管链路
if (-not ($co -match "接管成功")) {
    Write-Output "FAIL: client never got takeover"; $ok = $false
} else {
    $m = [regex]::Match($co, "接管成功 hero=(\S+)")
    if ($m.Success) { Write-Output "[i] client takeover hero=$($m.Groups[1].Value)" }
}
if (-not ($co -match "move-ok")) {
    Write-Output "FAIL: client drive move not confirmed"; $ok = $false
} else {
    Write-Output "[i] client move-ok confirmed"
}
if ($co -match "move-fail") { Write-Output "FAIL: client move timed out"; $ok = $false }
# 主机应收到并执行指令
if (-not ($ho -match "指令 move_to")) { Write-Output "FAIL: host never applied move_to"; $ok = $false }
else { Write-Output "[i] host applied move_to" }
if (-not ($co -match "snap #")) { Write-Output "FAIL: client never logged a snapshot"; $ok = $false }
if (($ho -match "SCRIPT ERROR") -or ($he -match "SCRIPT ERROR")) { Write-Output "FAIL: host had SCRIPT ERROR"; $ok = $false }
if (($co -match "SCRIPT ERROR") -or ($ce -match "SCRIPT ERROR")) { Write-Output "FAIL: client had SCRIPT ERROR"; $ok = $false }
if ($ok) { Write-Output "===== INTEGRATION PASS =====" } else { Write-Output "===== INTEGRATION FAIL =====" }
exit $(if ($ok) { 0 } else { 1 })
