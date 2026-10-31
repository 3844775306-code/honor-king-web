# 任务完成 → 弹一个右下角置顶小窗（不抢焦点，7 秒自动消失）。
# 为什么不用系统 Toast：本机 Win11 下 powershell.exe 5.1 调用 WinRT Toast 报
# "The process has no package identity (0x80073D54)"，桌面脚本无法注册 AUMID；
# 而 NotifyIcon 气泡受「专注助手/通知关闭」影响可能不显示。
# 自绘窗口不依赖通知设置，必定可见。
# 用法：pwsh -File scripts\dev\notify.ps1 -Title "HonorKing" -Message "..."
param(
    [string]$Title = "DSH 任务完成",
    [string]$Message = "任务已完成",
    [int]$Seconds = 7
)

$ErrorActionPreference = "Continue"

function New-Brush([string]$hex) {
    $conv = New-Object System.Windows.Media.BrushConverter
    return $conv.ConvertFromString($hex)
}

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $win = New-Object System.Windows.Window
    $win.WindowStyle = [System.Windows.WindowStyle]::None
    $win.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $win.AllowsTransparency = $true
    $win.Background = New-Brush "#F21B1E22"
    $win.Topmost = $true
    $win.ShowInTaskbar = $false
    $win.ShowActivated = $false
    $win.Width = 360
    $win.Height = 104
    $win.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $wa = [System.Windows.SystemParameters]::WorkArea
    $win.Left = $wa.Right - $win.Width - 24
    $win.Top = $wa.Bottom - $win.Height - 24

    $border = New-Object System.Windows.Controls.Border
    $border.BorderThickness = "1"
    $border.BorderBrush = New-Brush "#FF3D4753"
    $border.CornerRadius = "8"

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = "16,12,16,12"

    $t1 = New-Object System.Windows.Controls.TextBlock
    $t1.Text = $Title
    $t1.FontSize = 15
    $t1.FontWeight = [System.Windows.FontWeights]::Bold
    $t1.Foreground = New-Brush "#FF7FD1FF"
    $t1.TextTrimming = "CharacterEllipsis"

    $t2 = New-Object System.Windows.Controls.TextBlock
    $t2.Text = $Message
    $t2.FontSize = 12.5
    $t2.Margin = "0,6,0,0"
    $t2.Foreground = New-Brush "#FFDCE3EA"
    $t2.TextWrapping = "Wrap"

    $sp.Children.Add($t1) | Out-Null
    $sp.Children.Add($t2) | Out-Null
    $border.Child = $sp
    $win.Content = $border

    $app = New-Object System.Windows.Application
    $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    $win.Show()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($Seconds)
    $timer.Add_Tick({
        $timer.Stop()
        $win.Close()
        [System.Windows.Application]::Current.Dispatcher.InvokeShutdown()
    })
    $timer.Start()
    $app.Run() | Out-Null
    Write-Output "popup shown: $Title | $Message"
} catch {
    # 兜底：NotifyIcon 气泡
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Application
        $n.Visible = $true
        $n.BalloonTipTitle = $Title
        $n.BalloonTipText = $Message
        $n.ShowBalloonTip(6000)
        Start-Sleep -Seconds 4
        $n.Dispose()
        Write-Output "fallback balloon: $($_.Exception.Message)"
    } catch {
        Write-Output "notify skipped: $($_.Exception.Message)"
    }
}
