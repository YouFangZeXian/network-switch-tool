#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework

$ErrorActionPreference = "Stop"

$RouterName = "LuYouQi"
$CampusName = "XiaoYuanWang"

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

function Get-DefaultGatewaySummary {
    $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
        Sort-Object RouteMetric |
        Select-Object -First 1

    if ($null -eq $route) {
        return "未找到默认路由"
    }

    $gateway = [string]$route.NextHop
    if ([string]::IsNullOrWhiteSpace($gateway) -or $gateway -eq "0.0.0.0") {
        return "默认路由存在，但默认网关为空 (InterfaceIndex: {0}, RouteMetric: {1})" -f $route.InterfaceIndex, $route.RouteMetric
    }

    return "{0} (InterfaceIndex: {1}, RouteMetric: {2})" -f $gateway, $route.InterfaceIndex, $route.RouteMetric
}

if (-not (Test-IsAdministrator)) {
    Show-Box -Title "需要管理员权限" -Icon Warning -Message "请以管理员身份运行。"
    exit 1
}

try {
    $campus = Get-RequiredAdapter -Name $CampusName
    $router = Get-RequiredAdapter -Name $RouterName
    $gatewayText = Get-DefaultGatewaySummary

    $statusText = @"
XiaoYuanWang 状态：$($campus.Status)
LuYouQi 状态：$($router.Status)

当前默认网关：
$gatewayText
"@

    if ($campus.Status -eq "Up" -and $router.Status -eq "Up") {
        Show-Box -Title "危险：两张网卡同时启用" -Icon Warning -Message @"
⚠️ 危险：校园网和路由器同时启用，不要打开 VPN，请先切换

$statusText
"@
        exit 2
    }

    if ($campus.Status -eq "Up") {
        Show-Box -Title "当前是校园网状态" -Icon Warning -Message @"
⚠️ 当前校园网网卡处于启用状态，不要打开 VPN

$statusText
"@
        exit 0
    }

    if ($router.Status -eq "Up" -and ($campus.Status -eq "Disabled" -or $campus.Status -eq "Disconnected")) {
        Show-Box -Title "当前大概率是路由器网络" -Icon Information -Message @"
✅ 当前大概率是路由器网络，可以打开 VPN

$statusText
"@
        exit 0
    }

    if ($router.Status -ne "Up" -and $campus.Status -ne "Up") {
        Show-Box -Title "没有可用有线网络" -Icon Error -Message @"
❌ 当前没有可用有线网络

$statusText
"@
        exit 2
    }

    Show-Box -Title "网络状态需要人工确认" -Icon Warning -Message @"
当前网络状态不属于预设安全状态，请先确认后再操作 VPN。

$statusText
"@
    exit 2
} catch {
    Show-Box -Title "检查失败" -Icon Error -Message "检查网络状态时发生错误：`n`n$($_.Exception.Message)"
    exit 1
}
