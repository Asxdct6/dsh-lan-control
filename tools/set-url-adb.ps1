# 通过 adb 自动把 DSH 地址填进「局域网控制DSH」App
#
# 用法：
#   .\set-url-adb.ps1 -Url "http://nrte96.taild3f9d0.ts.net:8443/?token=xxxx"
#   .\set-url-adb.ps1 -Url "..." -Wait 120
#
# 原理：uiautomator 抓界面节点，按文字/类名定位，再 tap + input text。
# 不依赖固定坐标，换分辨率也不会错位。

param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$Wait = 60,
    [string]$Package = "com.dsh.lancontrol"
)

$ErrorActionPreference = 'Stop'
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { throw "找不到 adb，请把 platform-tools 加进 PATH" }

function Get-Serial {
    $lines = & $adb devices 2>&1
    $hit = $lines | Where-Object { $_ -match '^\S+\s+device$' } | Select-Object -First 1
    if ($hit) { return ($hit -split '\s+')[0] }
    return $null
}

function Adb {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    & $adb @Args 2>&1
}

# ---------- 1. 等设备 ----------
Write-Host "等待设备上线（最多 $Wait 秒）..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds($Wait)
$serial = $null
while ((Get-Date) -lt $deadline) {
    $serial = Get-Serial
    if ($serial) { break }
    Start-Sleep -Seconds 2
}
if (-not $serial) { throw "设备没上线。检查数据线 / USB 调试授权。" }
Write-Host "设备: $serial" -ForegroundColor Green

# ---------- 2. 工具函数 ----------
function Dump-Ui {
    & $adb shell uiautomator dump /sdcard/ui.xml 2>&1 | Out-Null
    $xml = (& $adb shell "cat /sdcard/ui.xml" 2>&1) -join ''
    if ($xml -notmatch '<hierarchy') { return $null }
    try { return [xml]$xml } catch { return $null }
}

function Find-Node {
    param($Xml, [string]$Text, [string]$Class)
    if (-not $Xml) { return $null }
    foreach ($n in $Xml.SelectNodes('//node')) {
        if ($Text -and $n.GetAttribute('text') -eq $Text) { return $n }
        if ($Class -and $n.GetAttribute('class') -like "*$Class*") { return $n }
    }
    return $null
}

function Get-Bounds {
    param($Node)
    $b = $Node.GetAttribute('bounds')
    $m = [regex]::Match($b, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $m.Success) { return $null }
    return @{
        X = ([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2
        Y = ([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2
    }
}

function Tap-Node {
    param($Node)
    $p = Get-Bounds $Node
    if (-not $p) { throw "解析 bounds 失败" }
    & $adb shell input tap ([int]$p.X) ([int]$p.Y) 2>&1 | Out-Null
}

# ---------- 3. 启动 App ----------
Write-Host "启动 App..." -ForegroundColor Cyan
& $adb shell am force-stop $Package 2>&1 | Out-Null
& $adb shell am start -n "$Package/.MainActivity" 2>&1 | Out-Null
Start-Sleep -Seconds 6

# ---------- 4. 打开「设置」 ----------
$ui = Dump-Ui
$settings = Find-Node -Xml $ui -Text '设置'
if (-not $settings) { throw "没找到「设置」按钮（界面可能还没渲染完）" }
Write-Host "点「设置」" -ForegroundColor Cyan
Tap-Node $settings
Start-Sleep -Seconds 2

# ---------- 5. 填地址 ----------
$ui = Dump-Ui
$edit = Find-Node -Xml $ui -Class 'EditText'
if (-not $edit) { throw "没找到输入框" }
Write-Host "选中输入框" -ForegroundColor Cyan
Tap-Node $edit
Start-Sleep -Milliseconds 800

# 优先全选替换；不行再逐个删除
$replaced = $false
& $adb shell input keycombination 113 29 2>&1 | Out-Null   # Ctrl+A
Start-Sleep -Milliseconds 400
& $adb shell "input text '$Url'" 2>&1 | Out-Null
Start-Sleep -Milliseconds 600

$ui = Dump-Ui
$edit = Find-Node -Xml $ui -Class 'EditText'
if ($edit -and $edit.GetAttribute('text') -eq $Url) {
    $replaced = $true
    Write-Host "  全选替换成功" -ForegroundColor DarkGray
}

if (-not $replaced) {
    Write-Host "  全选没生效，改用逐个删除" -ForegroundColor DarkYellow
    Tap-Node $edit
    & $adb shell input keyevent 123 2>&1 | Out-Null   # 光标移到末尾
    $len = 0
    if ($edit) { $len = $edit.GetAttribute('text').Length }
    $times = [Math]::Min(200, $len + 5)
    & $adb shell "for i in `$(seq 1 $times); do input keyevent 67; done" 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    & $adb shell "input text '$Url'" 2>&1 | Out-Null
    Start-Sleep -Milliseconds 600
}

# ---------- 6. 保存 ----------
$ui = Dump-Ui
$save = Find-Node -Xml $ui -Text '保存并连接'
if (-not $save) { throw "没找到「保存并连接」" }
Write-Host "保存并连接" -ForegroundColor Cyan
Tap-Node $save
Start-Sleep -Seconds 8

# ---------- 7. 截图 ----------
$shot = Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\after-set-url.png'
New-Item -ItemType Directory -Force -Path (Split-Path $shot) | Out-Null
cmd /c "`"$adb`" exec-out screencap -p > `"$shot`""
Write-Host "完成，截图: $shot" -ForegroundColor Green
