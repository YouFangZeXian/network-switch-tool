# 网络切换工具

这个工具用于在两张有线网卡之间安全切换，降低在校园网状态下误开 VPN 的风险。

它适合这类场景：

- 一根网线连接校园网、公司网、实验室网等对 VPN 使用有限制的网络。
- 另一根网线连接家用路由器、4G/5G 路由器、旁路由等允许使用 VPN 的网络。
- 你希望在打开 VPN 前，用一个快捷键确认当前不是受限制网络。
- 你不想每次手动打开“网络连接”面板禁用/启用网卡。

核心思路很简单：只按精确网卡名称启用或禁用指定有线网卡，然后检查当前启用的物理网卡和默认网关，最后用 Windows 弹窗提醒当前是否适合打开 VPN。

## 默认配置

本仓库当前默认按我的机器配置写好：

只会精确操作这两个网卡 Name：

- `XiaoYuanWang`：校园网网线，不允许开 VPN
- `LuYouQi`：路由器网线 / 4G 路由器，可以开 VPN

脚本不会操作 WLAN、蓝牙、TAP、VMware 或其他任何虚拟网卡。

如果你的网卡名称不同，请先运行：

```powershell
Get-NetAdapter
```

然后把下面三个脚本开头的变量改成你自己的网卡 Name：

- `switch-to-router.ps1`
- `switch-to-campus.ps1`
- `check-network.ps1`

需要修改的是：

```powershell
$RouterName = "LuYouQi"
$CampusName = "XiaoYuanWang"
```

请使用 `Name` 字段，不要使用描述、品牌名或模糊匹配。这样可以避免误操作 WLAN、TAP、VMware、蓝牙或其他虚拟网卡。

## 文件说明

- `switch-to-router.ps1`：禁用 `XiaoYuanWang`，启用 `LuYouQi`，检查默认网关和当前启用物理网卡，确认成功后提示可以打开 VPN。
- `switch-to-campus.ps1`：切换前先检测疑似 VPN / 代理 / 虚拟隧道是否仍在运行；如果检测到风险会禁止切换校园网。确认安全后禁用 `LuYouQi`，启用 `XiaoYuanWang`，检查默认网关和当前启用物理网卡，并明确警告不要打开 VPN。
- `check-network.ps1`：不修改任何网卡，只检查 `XiaoYuanWang`、`LuYouQi`、默认路由、默认网关和疑似 VPN/代理信号；如果校园网和 VPN/代理信号同时存在，会显示高风险警告。
- `install-shortcuts.ps1`：在桌面创建 `网络切换工具` 文件夹用于双击，在开始菜单创建同名文件夹用于全局快捷键，并尽量自动设置管理员运行。

## 第一次使用

1. 下载或克隆本项目。
2. 确认网卡名称和你的 Windows 中完全一致：
   - `XiaoYuanWang`
   - `LuYouQi`
3. 如果你的网卡名称不同，先按“默认配置”一节修改脚本变量。
4. 右键开始菜单，打开“终端(管理员)”或“Windows PowerShell(管理员)”。
5. 进入本目录：

```powershell
cd "你的项目目录\NetworkSwitchTool"
```

6. 运行快捷方式安装脚本：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\install-shortcuts.ps1"
```

安装后会创建两组快捷方式：

- 桌面：`网络切换工具` 文件夹，适合双击使用。
- 开始菜单：`网络切换工具` 文件夹，专门用于全局快捷键。

里面都有：

- `切到校园网`
- `切到路由器`
- `检查当前网络`

## 快捷键

`install-shortcuts.ps1` 会尽量自动设置：

- `Ctrl + Alt + 1`：切到校园网
- `Ctrl + Alt + 2`：切到路由器
- `Ctrl + Alt + 3`：检查当前网络

快捷方式会调用 `powershell.exe -WindowStyle Hidden`，正常情况下按快捷键时不会弹出 PowerShell 终端窗口，只会弹出脚本自己的网络状态提示。

注意：Windows 对快捷方式快捷键的监听比较挑剔。桌面根目录和开始菜单里的快捷方式通常比较稳定；如果你把桌面快捷方式移动到“桌面上的某个文件夹”里，快捷键可能失效。所以本项目会把真正负责快捷键的那份快捷方式放到开始菜单：

```text
开始菜单\程序\网络切换工具
```

桌面 `网络切换工具` 文件夹里的快捷方式主要用于鼠标双击。

如果你已经安装过旧快捷方式，请重新运行一次：

```powershell
cd "你的项目目录\NetworkSwitchTool"
powershell.exe -ExecutionPolicy Bypass -File ".\install-shortcuts.ps1"
```

如果 PowerShell 没有稳定设置成功，请手动设置：

1. 打开开始菜单里的 `网络切换工具` 文件夹。
2. 右键对应快捷方式。
3. 打开“属性”。
4. 点击“快捷键”输入框。
5. 分别输入 `Ctrl + Alt + 1` / `Ctrl + Alt + 2` / `Ctrl + Alt + 3`。
6. 点击“应用”。

## 管理员权限

启用和禁用网卡需要管理员权限。安装脚本会尽量自动把快捷方式设置为“用管理员身份运行”。

如果某个快捷方式运行时提示“请以管理员身份运行”，请手动设置：

1. 右键桌面快捷方式。
2. 打开“属性”。
3. 点击“高级”。
4. 勾选“用管理员身份运行”。
5. 点击“确定”并“应用”。

## 安全使用流程

1. 开 VPN 前，先运行“切到路由器”。
2. 弹窗确认当前是 `LuYouQi`。
3. 再运行“检查当前网络”。
4. 确认不是 `XiaoYuanWang` 后，再打开 VPN。
5. 用完后先关闭 VPN，再切回校园网。

切回校园网时，脚本会先做一轮只读检测。如果发现常见 VPN/代理进程、运行中的 VPN 服务，或 `Up` 状态的 TAP/TUN/Wintun/WireGuard/Tailscale/ZeroTier 等虚拟网卡，会弹窗阻止切换。这个设计是为了避免“VPN 还开着就切回校园网”。

## 手动运行

如果不使用桌面快捷方式，也可以在管理员 PowerShell 中运行：

```powershell
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "你的项目目录\NetworkSwitchTool\switch-to-router.ps1"
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "你的项目目录\NetworkSwitchTool\switch-to-campus.ps1"
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "你的项目目录\NetworkSwitchTool\check-network.ps1"
```

## 重要提醒

`check-network.ps1` 只根据本机网卡状态和默认路由判断网络状态。打开 VPN 前请以弹窗中显示的启用网卡列表和默认网关为准，尤其要确认 `XiaoYuanWang` 不是 `Up`。

## 安全边界

这个项目只是本地 PowerShell 自动化工具，不会替你判断某个网络是否允许使用 VPN。请遵守你所在学校、公司或网络服务提供方的规则。

脚本的安全设计包括：

- 只使用精确网卡 Name：`XiaoYuanWang` 和 `LuYouQi`。
- 切换前检查目标网卡是否存在，不存在就弹窗报错并退出。
- 不操作 WLAN、蓝牙、TAP、VMware 或其他虚拟网卡。
- 每次切换后显示启用中的物理网卡和默认网关。
- 校园网网卡处于 `Up` 时明确提示不要打开 VPN。
- 切回校园网前检测常见 VPN/代理客户端、后台服务和虚拟隧道网卡，发现风险时直接阻止切换。

但它不能保证：

- 你的默认网关一定代表真实出口网络。
- 你的 VPN 客户端不会自动重连。
- 你的系统没有其他代理、共享网络、虚拟交换机或路由规则影响流量。
- 所有 VPN 客户端都能被脚本识别。不同软件的进程名、服务名和网卡名可能不同，必要时请按自己的软件名称扩展脚本中的 `$VpnProcessKeywordPattern` 和 `$VpnAdapterKeywordPattern`。

建议始终按“先切网络、再检查、确认后再开 VPN”的流程使用。

## 给其他用户的改造建议

如果你想 fork 这个项目给自己用，通常只需要改三处：

1. 把 `$RouterName` 改成允许打开 VPN 的网卡 Name。
2. 把 `$CampusName` 改成不允许打开 VPN 的网卡 Name。
3. 按自己的习惯修改 `install-shortcuts.ps1` 里的快捷方式名称和快捷键。

如果你的场景不是“校园网 / 路由器”，也可以把脚本文案改成：

- `公司内网 / 手机热点`
- `实验室网络 / 家用宽带`
- `受限网络 / 安全网络`

只要保持“受限网络下不要打开 VPN”的判断逻辑即可。

## 贡献

欢迎提交 issue 或 pull request，尤其是这些方向：

- 更通用的配置文件，例如 `config.json`。
- 更稳定的 Windows 通知方式。
- 更好的快捷方式图标。
- 多语言 README。
- 支持更多“受限网络 / 可用网络”组合。

提交修改时请注意：不要把自己的真实网关、校园网账号、VPN 配置、公司内网地址或其他敏感信息提交到仓库。
