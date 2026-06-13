#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework

$ErrorActionPreference = "Stop"

$RouterName = "LuYouQi"
$CampusName = "XiaoYuanWang"
$StateDirectory = Join-Path $PSScriptRoot ".state"
$DisabledServicesStatePath = Join-Path $StateDirectory "disabled-vpn-services.json"

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
    $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
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

function ConvertTo-ServiceStartupType {
    param([string]$StartMode)

    switch ($StartMode) {
        "Auto" { return "Automatic" }
        "Automatic" { return "Automatic" }
        "Manual" { return "Manual" }
        "Disabled" { return "Disabled" }
        default { return "Manual" }
    }
}

function Restore-CampusDisabledServices {
    if (-not (Test-Path -LiteralPath $DisabledServicesStatePath -PathType Leaf)) {
        return "没有需要恢复的 VPN/代理服务。"
    }

    $entries = @(Get-Content -LiteralPath $DisabledServicesStatePath -Encoding UTF8 -Raw | ConvertFrom-Json)
    if ($entries.Count -eq 0) {
        Remove-Item -LiteralPath $DisabledServicesStatePath -Force -ErrorAction SilentlyContinue
        return "没有需要恢复的 VPN/代理服务。"
    }

    $messages = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $entries) {
        $service = Get-Service -Name $entry.Name -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            $messages.Add("未找到服务：$($entry.Name)")
            continue
        }

        $startupType = ConvertTo-ServiceStartupType -StartMode $entry.StartMode
        Set-Service -Name $entry.Name -StartupType $startupType -ErrorAction SilentlyContinue

        if ($entry.WasRunning -eq $true) {
            Start-Service -Name $entry.Name -ErrorAction SilentlyContinue
        }

        $messages.Add("已恢复服务：$($entry.Name) / 启动类型：$startupType")
    }

    Remove-Item -LiteralPath $DisabledServicesStatePath -Force -ErrorAction SilentlyContinue

    if ($messages.Count -eq 0) {
        return "没有需要恢复的 VPN/代理服务。"
    }

    return ($messages -join "`n")
}

if (-not (Test-IsAdministrator)) {
    Show-Box -Title "需要管理员权限" -Icon Warning -Message "请以管理员身份运行。"
    exit 1
}

try {
    Get-RequiredAdapter -Name $CampusName | Out-Null
    Get-RequiredAdapter -Name $RouterName | Out-Null

    $campus = Get-NetAdapter -Name $CampusName
    if ($campus.Status -ne "Disabled") {
        Disable-NetAdapter -Name $CampusName -Confirm:$false
    }

    Start-Sleep -Seconds 2

    $router = Get-NetAdapter -Name $RouterName
    if ($router.Status -eq "Disabled") {
        Enable-NetAdapter -Name $RouterName -Confirm:$false
    }

    Start-Sleep -Seconds 5

    $router = Get-NetAdapter -Name $RouterName
    $upAdapters = Get-UpPhysicalAdapterSummary
    $gatewayInfo = Get-DefaultGatewaySummary

    if ($router.Status -ne "Up" -or [string]::IsNullOrWhiteSpace($gatewayInfo.Gateway) -or $gatewayInfo.Gateway -eq "0.0.0.0") {
        Show-Box -Title "路由器未连接成功" -Icon Warning -Message @"
路由器未连接成功，不要打开 VPN。

LuYouQi 当前状态：$($router.Status)

当前启用网卡列表：
$upAdapters

当前默认网关：
$($gatewayInfo.Text)
"@
        exit 2
    }

    $restoreSummary = Restore-CampusDisabledServices

    Show-Box -Title "已切换路由器" -Icon Information -Message @"
当前已切换到：路由器 / LuYouQi

当前启用网卡列表：
$upAdapters

当前默认网关：
$($gatewayInfo.Text)

VPN/代理服务恢复状态：
$restoreSummary

确认后可以打开 VPN。
"@
} catch {
    Show-Box -Title "切换失败" -Icon Error -Message "切换到路由器时发生错误：`n`n$($_.Exception.Message)"
    exit 1
}
