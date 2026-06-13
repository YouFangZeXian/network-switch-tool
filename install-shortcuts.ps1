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
        [Parameter(Mandatory = $true)][string]$ShortcutDirectory,
        [string]$Hotkey = "",
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "脚本不存在：$ScriptPath"
    }

    New-Item -ItemType Directory -Force -Path $ShortcutDirectory | Out-Null

    $shortcutPath = Join-Path $ShortcutDirectory ($Name + ".lnk")
    $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershellPath
    $shortcut.Arguments = '-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath
    $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
    $shortcut.WindowStyle = 7
    $shortcut.Description = $Description
    if (-not [string]::IsNullOrWhiteSpace($Hotkey)) {
        $shortcut.Hotkey = $Hotkey
    }
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
        Hotkey = if ([string]::IsNullOrWhiteSpace($Hotkey)) { "无" } else { $Hotkey }
        RunAsAdministrator = $adminSet
    }
}

if (-not (Test-IsAdministrator)) {
    Show-Box -Title "需要管理员权限" -Icon Warning -Message "请以管理员身份运行。"
    exit 1
}

try {
    $projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $desktop = [Environment]::GetFolderPath("DesktopDirectory")
    $startMenuFolder = Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs\网络切换工具"

    # Remove older desktop shortcuts so the desktop can stay clean and their
    # hotkeys do not conflict with the Start Menu shortcuts.
    @("切到校园网", "切到路由器", "检查当前网络") | ForEach-Object {
        $oldShortcut = Join-Path $desktop ($_.ToString() + ".lnk")
        if (Test-Path -LiteralPath $oldShortcut -PathType Leaf) {
            Remove-Item -LiteralPath $oldShortcut -Force
        }
    }

    $shortcutDefinitions = @(
        [pscustomobject]@{
            Name = "切到校园网"
            Script = "switch-to-campus.ps1"
            Hotkey = "CTRL+ALT+1"
            Description = "切换到校园网 XiaoYuanWang；如果检测到 VPN 或代理仍在运行，会禁止切换"
        }
        [pscustomobject]@{
            Name = "切到路由器"
            Script = "switch-to-router.ps1"
            Hotkey = "CTRL+ALT+2"
            Description = "切换到路由器 LuYouQi，确认后可以打开 VPN"
        }
        [pscustomobject]@{
            Name = "检查当前网络"
            Script = "check-network.ps1"
            Hotkey = "CTRL+ALT+3"
            Description = "检查 XiaoYuanWang 和 LuYouQi 的当前网络状态"
        }
    )

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($definition in $shortcutDefinitions) {
        $scriptPath = Join-Path $projectRoot $definition.Script

        $results.Add((New-NetworkShortcut `
            -Name $definition.Name `
            -ScriptPath $scriptPath `
            -ShortcutDirectory $startMenuFolder `
            -Hotkey $definition.Hotkey `
            -Description $definition.Description))
    }

    $summary = ($results | ForEach-Object {
        $adminText = if ($_.RunAsAdministrator) { "已尝试设置为管理员运行" } else { "未能自动设置管理员运行" }
        "- {0}`n  路径：{1}`n  快捷键：{2}`n  管理员权限：{3}" -f $_.Name, $_.Path, $_.Hotkey, $adminText
    }) -join "`n`n"

    $manualTip = @"

如果某个快捷方式没有成功以管理员身份运行，请手动设置：
右键快捷方式 → 属性 → 高级 → 勾选“用管理员身份运行”

快捷方式已设置为隐藏 PowerShell 终端窗口，只显示脚本弹窗提示。

本脚本不会在桌面创建快捷方式。
全局快捷键设置在开始菜单“网络切换工具”文件夹里的快捷方式上；把桌面快捷方式移动到子文件夹后，Windows 可能不会继续监听它的快捷键。

如果快捷键没有生效，请手动设置：
打开开始菜单文件夹中的快捷方式属性 → 快捷键 → 分别输入 Ctrl + Alt + 1 / 2 / 3 → 应用
"@

    Write-Host $summary
    Write-Host $manualTip

    Show-Box -Title "快捷方式安装完成" -Icon Information -Message @"
已创建开始菜单快捷键快捷方式：

$summary
$manualTip
"@
} catch {
    $manualTip = '如需手动设置管理员权限：右键快捷方式 → 属性 → 高级 → 勾选“用管理员身份运行”。'
    Write-Error $_.Exception.Message
    Show-Box -Title "安装快捷方式失败" -Icon Error -Message "安装快捷方式时发生错误：`n`n$($_.Exception.Message)`n`n$manualTip"
    exit 1
}
