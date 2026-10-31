# export_web.ps1 — 导出网页版（临时把渲染后端切到 gl_compatibility，导出后自动还原）
param(
    [string]$GodotPath = '',
    [string]$Out = 'build/web/index.html'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$proj = Join-Path $root 'project.godot'
$outPath = Join-Path $root $Out
New-Item -ItemType Directory -Force (Split-Path $outPath -Parent) | Out-Null

# 1) 找 Godot 可执行文件
if (-not $GodotPath) {
    foreach ($c in @(
        (Join-Path $root '.cache\godot47.exe'),
        'D:\Downloads\06_游戏与Flash资源\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
    )) { if (Test-Path $c) { $GodotPath = $c; break } }
    if (-not $GodotPath) {
        $cmd = Get-Command godot -ErrorAction SilentlyContinue
        if ($cmd) { $GodotPath = $cmd.Source }
    }
}
if (-not $GodotPath -or -not (Test-Path $GodotPath)) { Write-Error '找不到 Godot 4 可执行文件，请用 -GodotPath 指定'; exit 1 }

# 2) Web 只能用 Compatibility(GL) 渲染后端：临时改 project.godot，导出后还原
$orig = [System.IO.File]::ReadAllText($proj)
$patched = $orig -replace 'renderer/rendering_method="[a-z_]+"', 'renderer/rendering_method="gl_compatibility"'
$dirty = $false
if ($patched -ne $orig) {
    [System.IO.File]::WriteAllText($proj, $patched)
    $dirty = $true
    Write-Host '[web] 已临时切换渲染后端 -> gl_compatibility'
}
try {
    Write-Host "[web] 导出： $GodotPath --headless --path . --export-release Web $Out"
    $proc = Start-Process -FilePath $GodotPath -ArgumentList '--headless','--path',$root,'--export-release','Web',$outPath -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) { Write-Error "导出失败 exit=$($proc.ExitCode)"; exit 1 }
} finally {
    # 只在文件没被其它改动时还原，避免覆盖并发编辑
    if ($dirty -and ([System.IO.File]::ReadAllText($proj) -eq $patched)) {
        [System.IO.File]::WriteAllText($proj, $orig)
        Write-Host '[web] 渲染后端已还原为原设置'
    } elseif ($dirty) {
        Write-Warning 'project.godot 在导出期间被修改，未自动还原，请检查 renderer/rendering_method'
    }
}

# 3) 结果自检：pck 里带的渲染后端必须是 gl_compatibility
$pck = Join-Path $root 'build\web\index.pck'
if (Test-Path $pck) {
    $txt = [System.Text.Encoding]::Latin1.GetString([System.IO.File]::ReadAllBytes($pck))
    if ($txt.Contains('gl_compatibility')) { Write-Host '[web] OK: pck 渲染后端 = gl_compatibility' }
    else { Write-Warning 'pck 中未找到 gl_compatibility，请检查导出是否生效' }
    '{0:N1} MB' -f ((Get-Item $pck).Length / 1MB) | ForEach-Object { Write-Host "[web] index.pck = $_" }
}
Write-Host '[web] 完成。本地预览： pwsh -NoProfile -File scripts\dev\serve_web.ps1'
