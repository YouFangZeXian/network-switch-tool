#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework

$ErrorActionPreference = "Stop"

function Show-Box {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$Title,
        [System.Windows.MessageBoxImage]$Icon = [System.Windows.MessageBoxImage]::Information
    )

    [System.Windows.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.MessageBoxButton]::OK,
        $Icon
    ) | Out-Null
}

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-ShortcutRunAsAdministrator {
    param([Parameter(Mandatory = $true)][string]$ShortcutPath)

    # Windows shell stores the "Run as administrator" flag inside the .lnk data.
    # Setting bit 0x20 at offset 0x15 is the standard PowerShell automation method.
    $bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)
    if ($bytes.Length -le 0x15) {
        throw "快捷方式文件过短，无法设置管理员权限标记：$ShortcutPath"
    }

    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($ShortcutPath, $bytes)
}

function New-NetworkShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Hotkey,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "脚本不存在：$ScriptPath"
    }

    $desktop = [Environment]::GetFolderPath("DesktopDirectory")
    $shortcutPath = Join-Path $desktop ($Name + ".lnk")
    $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershellPath
    $shortcut.Arguments = '-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath
    $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
    $shortcut.WindowStyle = 7
    $shortcut.Description = $Description
    $shortcut.Hotkey = $Hotkey
    $shortcut.IconLocation = "$powershellPath,0"
    $shortcut.Save()

    $adminSet = $true
    try {
        Set-ShortcutRunAsAdministrator -ShortcutPath $shortcutPath
    } catch {
        $adminSet = $false
        Write-Warning $_.Exception.Message
    }

    return [pscustomobject]@{
        Name = $Name
        Path = $shortcutPath
        Hotkey = $Hotkey
        RunAsAdministrator = $adminSet
    }
}

if (-not (Test-IsAdministrator)) {
    Show-Box -Title "需要管理员权限" -Icon Warning -Message "请以管理员身份运行。"
    exit 1
}

try {
    $projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

    $results = @(
        New-NetworkShortcut `
            -Name "切到校园网" `
            -ScriptPath (Join-Path $projectRoot "switch-to-campus.ps1") `
            -Hotkey "CTRL+ALT+1" `
            -Description "切换到校园网 XiaoYuanWang，并提醒不要打开 VPN"

        New-NetworkShortcut `
            -Name "切到路由器" `
            -ScriptPath (Join-Path $projectRoot "switch-to-router.ps1") `
            -Hotkey "CTRL+ALT+2" `
            -Description "切换到路由器 LuYouQi，确认后可以打开 VPN"

        New-NetworkShortcut `
            -Name "检查当前网络" `
            -ScriptPath (Join-Path $projectRoot "check-network.ps1") `
            -Hotkey "CTRL+ALT+3" `
            -Description "检查 XiaoYuanWang 和 LuYouQi 的当前网络状态"
    )

    $summary = ($results | ForEach-Object {
        $adminText = if ($_.RunAsAdministrator) { "已尝试设置为管理员运行" } else { "未能自动设置管理员运行" }
        "- {0}`n  路径：{1}`n  快捷键：{2}`n  管理员权限：{3}" -f $_.Name, $_.Path, $_.Hotkey, $adminText
    }) -join "`n`n"

    $manualTip = @"

如果某个快捷方式没有成功以管理员身份运行，请手动设置：
右键快捷方式 → 属性 → 高级 → 勾选“用管理员身份运行”

快捷方式已设置为隐藏 PowerShell 终端窗口，只显示脚本弹窗提示。

如果快捷键没有生效，请手动设置：
右键桌面快捷方式 → 属性 → 快捷键 → 分别输入 Ctrl + Alt + 1 / 2 / 3 → 应用
"@

    Write-Host $summary
    Write-Host $manualTip

    Show-Box -Title "快捷方式安装完成" -Icon Information -Message @"
已在桌面创建 3 个快捷方式：

$summary
$manualTip
"@
} catch {
    $manualTip = '如需手动设置管理员权限：右键快捷方式 → 属性 → 高级 → 勾选“用管理员身份运行”。'
    Write-Error $_.Exception.Message
    Show-Box -Title "安装快捷方式失败" -Icon Error -Message "安装快捷方式时发生错误：`n`n$($_.Exception.Message)`n`n$manualTip"
    exit 1
}
