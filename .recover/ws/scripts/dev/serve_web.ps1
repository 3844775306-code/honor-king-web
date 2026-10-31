# serve_web.ps1 — 本地起静态服务器预览网页版（默认 build/web）
param(
    [int]$Port = 8080,
    [string]$Root = (Join-Path $PSScriptRoot '..\..\build\web')
)
$root = (Resolve-Path $Root -ErrorAction Stop).Path
$index = Join-Path $root 'index.html'
if (-not (Test-Path $index)) { Write-Error "找不到 $index，请先导出 Web：`n  godot --headless --path . --export-release Web build/web/index.html"; exit 1 }

$py = $null
foreach ($cand in @('python', 'py', 'python3')) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $py = $cmd.Source; break }
}
if (-not $py) { Write-Error '需要 Python3 来起静态服务器（或改用任意静态服务器指向 build/web）'; exit 1 }

Write-Host "网页版预览： http://127.0.0.1:$Port/  (Ctrl+C 停止)"
Write-Host "注意：用 http://127.0.0.1 或 localhost 打开，file:// 无法运行 WebGL/WASM"
Push-Location $root
try { & $py -m http.server $Port --bind 127.0.0.1 } finally { Pop-Location }
