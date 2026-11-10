# 在本机局域网 IP 上启动 DSH Web，供手机端「局域网控制 DSH」连接。
#
# 用法：
#   .\start-dsh-lan.ps1                 # 自动选一个局域网 IPv4
#   .\start-dsh-lan.ps1 -HostIp 192.168.1.23 -Port 8787
#
# 启动后窗口会打印形如 http://<ip>:8787/?token=xxxx 的地址，
# 把这个完整地址（含 ?token=）粘贴到手机的 App 右上角「设置」里。

param(
    [string]$HostIp = "",
    [int]$Port = 8787,
    [string]$DshExe = "dsh"
)

$ErrorActionPreference = 'Stop'

if (-not $HostIp) {
    $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
            $_.IPAddress -notmatch '^192\.168\.(137|56)\.1$' -and   # Windows 热点/虚拟网卡
            $_.PrefixOrigin -ne 'WellKnown'
        } |
        Sort-Object -Property @{ Expression = { if ($_.InterfaceAlias -match 'WLAN|Wi-Fi|无线') { 0 } else { 1 } } }
    $HostIp = ($candidates | Select-Object -First 1).IPAddress
}

if (-not $HostIp) { throw "找不到局域网 IPv4，请用 -HostIp 手动指定" }

Write-Host "绑定 $HostIp`:$Port ..." -ForegroundColor Cyan
Write-Host "手机与电脑需在同一 Wi-Fi；下面的地址整段复制到 App 的「设置」里：" -ForegroundColor DarkGray
& $DshExe web --host $HostIp --port $Port --no-open
