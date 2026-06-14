#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework

$ErrorActionPreference = "Stop"

$RouterName = "LuYouQi"
$CampusName = "XiaoYuanWang"
$StateDirectory = Join-Path $PSScriptRoot ".state"
$DisabledServicesStatePath = Join-Path $StateDirectory "disabled-vpn-services.json"
$ProxyStatePath = Join-Path $StateDirectory "disabled-system-proxy.json"
$InternetSettingsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

$VpnProcessKeywordPattern = "(?i)(vpn|openvpn|wireguard|tailscale|zerotier|clash|clash-verge|mihomo|v2ray|xray|sing-box|singbox|shadowsocks|sslocal|trojan|hysteria|tuic|naive|nekoray|netch|sstap|warp|anyconnect|globalprotect|forticlient|fortissl|openconnect|pulse|softether|protonvpn|nordvpn|expressvpn|surfshark|mullvad|windscribe|outline|lantern|cfw|flclash)"
$VpnAdapterKeywordPattern = "(?i)(vpn|openvpn|wireguard|wintun|tap|tun|tailscale|zerotier|clash|mihomo|v2ray|xray|sing-box|singbox|shadowsocks|warp|anyconnect|globalprotect|forticlient|fortissl|openconnect|pulse|softether|protonvpn|nordvpn|expressvpn|surfshark|mullvad|windscribe|outline)"

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

function Show-ConfirmBox {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$Title
    )

    return [System.Windows.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
}

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RequiredAdapter {
    param([Parameter(Mandatory = $true)][string]$Name)

    $adapter = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $adapter) {
        Show-Box -Title "网卡不存在" -Icon Error -Message "找不到网卡：$Name`n`n脚本不会继续执行，避免误操作其他网卡。"
        exit 1
    }

    return $adapter
}

function Get-UpPhysicalAdapterSummary {
    $adapters = Get-NetAdapter -Physical |
        Where-Object { $_.Status -eq "Up" } |
        Sort-Object -Property ifIndex |
        Select-Object -Property Name, InterfaceDescription, Status, LinkSpeed

    if (-not $adapters) {
        return "无启用中的物理网卡"
    }

    return ($adapters | ForEach-Object {
        "- $($_.Name) | $($_.InterfaceDescription) | $($_.Status) | $($_.LinkSpeed)"
    }) -join "`n"
}

function Get-DefaultGatewaySummary {
    $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric |
        Select-Object -First 1

    if ($null -eq $route) {
        return @{
            Gateway = ""
            Text = "未找到默认路由"
        }
    }

    $gateway = [string]$route.NextHop
    if ([string]::IsNullOrWhiteSpace($gateway) -or $gateway -eq "0.0.0.0") {
        $gatewayText = "默认路由存在，但默认网关为空"
    } else {
        $gatewayText = "$gateway (InterfaceIndex: $($route.InterfaceIndex), RouteMetric: $($route.RouteMetric))"
    }

    return @{
        Gateway = $gateway
        Text = $gatewayText
    }
}

function Enable-AdapterAndWait {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$WaitSeconds = 12
    )

    $adapter = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $adapter) {
        return $null
    }

    if ($adapter.Status -eq "Disabled") {
        Enable-NetAdapter -Name $Name -Confirm:$false
        Start-Sleep -Seconds 2
    }

    for ($i = 0; $i -lt $WaitSeconds; $i++) {
        $adapter = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $adapter) {
            return $null
        }

        if ($adapter.Status -eq "Up") {
            return $adapter
        }

        Start-Sleep -Seconds 1
    }

    return (Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue)
}

function Find-ActiveVpnSignals {
    $signals = New-Object System.Collections.Generic.List[object]

    $vpnProcesses = Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -match $VpnProcessKeywordPattern -or
            ($_.Path -and $_.Path -match $VpnProcessKeywordPattern)
        } |
        Sort-Object -Property ProcessName -Unique

    foreach ($process in $vpnProcesses) {
        $signals.Add([pscustomobject]@{
            Type = "Process"
            Name = $process.ProcessName
            Id = $process.Id
            Display = "进程：$($process.ProcessName) (PID: $($process.Id))"
        })
    }

    $vpnServices = Get-Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Status -eq "Running" -and
            ($_.Name -match $VpnProcessKeywordPattern -or $_.DisplayName -match $VpnProcessKeywordPattern)
        } |
        Sort-Object -Property Name -Unique

    foreach ($service in $vpnServices) {
        $signals.Add([pscustomobject]@{
            Type = "Service"
            Name = $service.Name
            DisplayName = $service.DisplayName
            Display = "服务：$($service.Name) / $($service.DisplayName)"
        })
    }

    $vpnAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Status -eq "Up" -and
            ($_.Name -match $VpnAdapterKeywordPattern -or $_.InterfaceDescription -match $VpnAdapterKeywordPattern)
        } |
        Sort-Object -Property ifIndex -Unique

    foreach ($adapter in $vpnAdapters) {
        $signals.Add([pscustomobject]@{
            Type = "Adapter"
            Name = $adapter.Name
            Display = "网卡：$($adapter.Name) / $($adapter.InterfaceDescription) / $($adapter.Status)"
        })
    }

    $proxySettings = Get-ItemProperty -Path $InternetSettingsPath -ErrorAction SilentlyContinue
    if ($null -ne $proxySettings -and [int]$proxySettings.ProxyEnable -eq 1) {
        $signals.Add([pscustomobject]@{
            Type = "SystemProxy"
            Name = "WindowsSystemProxy"
            ProxyEnable = [int]$proxySettings.ProxyEnable
            ProxyServer = [string]$proxySettings.ProxyServer
            AutoConfigURL = [string]$proxySettings.AutoConfigURL
            Display = "系统代理：已开启 / $($proxySettings.ProxyServer)"
        })
    }

    return $signals
}

function Format-VpnSignals {
    param([Parameter(Mandatory = $true)]$Signals)

    if ($Signals.Count -eq 0) {
        return "未检测到"
    }

    return (($Signals | Select-Object -First 20 | ForEach-Object { $_.Display }) -join "`n")
}

function Save-DisabledServiceState {
    param([Parameter(Mandatory = $true)]$Entries)

    if ($Entries.Count -eq 0) {
        return
    }

    New-Item -ItemType Directory -Force -Path $StateDirectory | Out-Null

    $existing = @()
    if (Test-Path -LiteralPath $DisabledServicesStatePath -PathType Leaf) {
        $existing = @(Get-Content -LiteralPath $DisabledServicesStatePath -Encoding UTF8 -Raw | ConvertFrom-Json)
    }

    $allEntries = @($existing) + @($Entries)
    $merged = $allEntries |
        Group-Object -Property Name |
        ForEach-Object { $_.Group | Select-Object -First 1 }

    $merged | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $DisabledServicesStatePath -Encoding UTF8
}

function Save-SystemProxyState {
    param([Parameter(Mandatory = $true)]$ProxySignal)

    New-Item -ItemType Directory -Force -Path $StateDirectory | Out-Null

    [pscustomobject]@{
        ProxyEnable = $ProxySignal.ProxyEnable
        ProxyServer = $ProxySignal.ProxyServer
        AutoConfigURL = $ProxySignal.AutoConfigURL
    } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ProxyStatePath -Encoding UTF8
}

function Disable-VpnSignalsForCampus {
    param([Parameter(Mandatory = $true)]$Signals)

    $disabledServices = New-Object System.Collections.Generic.List[object]
    $serviceSignals = @($Signals | Where-Object { $_.Type -eq "Service" })
    $processSignals = @($Signals | Where-Object { $_.Type -eq "Process" })
    $proxySignals = @($Signals | Where-Object { $_.Type -eq "SystemProxy" })

    if ($proxySignals.Count -gt 0) {
        Save-SystemProxyState -ProxySignal ($proxySignals | Select-Object -First 1)
        Set-ItemProperty -Path $InternetSettingsPath -Name ProxyEnable -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }

    foreach ($signal in $serviceSignals) {
        $service = Get-Service -Name $signal.Name -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            continue
        }

        $cimService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($signal.Name)'" -ErrorAction SilentlyContinue
        $startMode = if ($null -ne $cimService) { $cimService.StartMode } else { "Manual" }

        $disabledServices.Add([pscustomobject]@{
            Name = $service.Name
            DisplayName = $service.DisplayName
            StartMode = $startMode
            WasRunning = ($service.Status -eq "Running")
        })

        Set-Service -Name $service.Name -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
    }

    Save-DisabledServiceState -Entries $disabledServices

    foreach ($signal in $processSignals) {
        Stop-Process -Id $signal.Id -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 3
}

if (-not (Test-IsAdministrator)) {
    Show-Box -Title "需要管理员权限" -Icon Warning -Message "请以管理员身份运行。"
    exit 1
}

try {
    Get-RequiredAdapter -Name $RouterName | Out-Null
    Get-RequiredAdapter -Name $CampusName | Out-Null

    $vpnSignals = Find-ActiveVpnSignals
    if ($vpnSignals.Count -gt 0) {
        $signalText = Format-VpnSignals -Signals $vpnSignals
        $moreText = if ($vpnSignals.Count -gt 20) { "`n...另有 $($vpnSignals.Count - 20) 项疑似 VPN/代理信号未显示" } else { "" }

        $choice = Show-ConfirmBox -Title "检测到 VPN，是否自动退出" -Message @"
检测到疑似 VPN / 代理 / 虚拟隧道仍在运行，已禁止切换到校园网。

是否自动退出相关进程，并停用相关后台服务？

点“是”：自动退出/停用后复检，通过后继续切到校园网。
点“否”：保持当前状态，不切换校园网。

检测到的信号：
$signalText$moreText
"@

        if ($choice -ne [System.Windows.MessageBoxResult]::Yes) {
            Show-Box -Title "已取消切换校园网" -Icon Warning -Message @"
已取消切换校园网。

请先完全关闭 VPN、代理客户端或相关后台服务，再重新运行“切到校园网”。
"@
            exit 3
        }

        Disable-VpnSignalsForCampus -Signals $vpnSignals

        $vpnSignals = Find-ActiveVpnSignals
        if ($vpnSignals.Count -gt 0) {
            $signalText = Format-VpnSignals -Signals $vpnSignals
            $moreText = if ($vpnSignals.Count -gt 20) { "`n...另有 $($vpnSignals.Count - 20) 项疑似 VPN/代理信号未显示" } else { "" }

            Show-Box -Title "仍检测到 VPN，禁止切换校园网" -Icon Warning -Message @"
自动退出后仍检测到疑似 VPN / 代理 / 虚拟隧道，已继续禁止切换到校园网。

请手动退出这些软件或重启电脑后再尝试。

剩余信号：
$signalText$moreText
"@
            exit 3
        }

        Show-Box -Title "VPN 已退出，继续切换校园网" -Icon Information -Message @"
已自动退出/停用检测到的 VPN、代理或虚拟隧道相关项。

在切回路由器之前，这些由脚本停用的后台服务会保持禁用状态。
现在将继续切换到校园网。
"@
    }

    $router = Get-NetAdapter -Name $RouterName
    if ($router.Status -ne "Disabled") {
        Disable-NetAdapter -Name $RouterName -Confirm:$false
    }

    Start-Sleep -Seconds 2

    $campus = Enable-AdapterAndWait -Name $CampusName -WaitSeconds 12
    $upAdapters = Get-UpPhysicalAdapterSummary
    $gatewayInfo = Get-DefaultGatewaySummary

    if ($null -eq $campus -or $campus.Status -ne "Up") {
        $campusStatus = if ($null -eq $campus) { "未找到" } else { $campus.Status }
        Show-Box -Title "校园网未连接成功" -Icon Warning -Message @"
校园网未连接成功。

脚本已在检测通过后尝试启用校园网网卡。

XiaoYuanWang 当前状态：$campusStatus

当前启用网卡列表：
$upAdapters

当前默认网关：
$($gatewayInfo.Text)
"@
        exit 2
    }

    Show-Box -Title "已切换校园网" -Icon Warning -Message @"
当前已切换到：校园网 / XiaoYuanWang

当前启用网卡列表：
$upAdapters

当前默认网关：
$($gatewayInfo.Text)

警告：此状态下不要打开 VPN。
"@
} catch {
    Show-Box -Title "切换失败" -Icon Error -Message "切换到校园网时发生错误：`n`n$($_.Exception.Message)"
    exit 1
}
