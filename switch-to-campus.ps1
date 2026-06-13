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

function Get-UpPhysicalAdapterSummary {
    $adapters = Get-NetAdapter -Physical |
        Where-Object { $_.Status -eq "Up" } |
        Sort-Object -Property ifIndex |
        Select-Object -Property Name, InterfaceDescription, Status, LinkSpeed

    if (-not $adapters) {
        return "无启用中的物理网卡"
    }

    return ($adapters | ForEach-Object {
        "- {0} | {1} | {2} | {3}" -f $_.Name, $_.InterfaceDescription, $_.Status, $_.LinkSpeed
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
        $gatewayText = "{0} (InterfaceIndex: {1}, RouteMetric: {2})" -f $gateway, $route.InterfaceIndex, $route.RouteMetric
    }

    return @{
        Gateway = $gateway
        Text = $gatewayText
    }
}

if (-not (Test-IsAdministrator)) {
    Show-Box -Title "需要管理员权限" -Icon Warning -Message "请以管理员身份运行。"
    exit 1
}

try {
    Get-RequiredAdapter -Name $RouterName | Out-Null
    Get-RequiredAdapter -Name $CampusName | Out-Null

    $router = Get-NetAdapter -Name $RouterName
    if ($router.Status -ne "Disabled") {
        Disable-NetAdapter -Name $RouterName -Confirm:$false
    }

    Start-Sleep -Seconds 2

    $campus = Get-NetAdapter -Name $CampusName
    if ($campus.Status -eq "Disabled") {
        Enable-NetAdapter -Name $CampusName -Confirm:$false
    }

    Start-Sleep -Seconds 5

    $campus = Get-NetAdapter -Name $CampusName
    $upAdapters = Get-UpPhysicalAdapterSummary
    $gatewayInfo = Get-DefaultGatewaySummary

    if ($campus.Status -ne "Up") {
        Show-Box -Title "校园网未连接成功" -Icon Warning -Message @"
校园网未连接成功。

XiaoYuanWang 当前状态：$($campus.Status)

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
