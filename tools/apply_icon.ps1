# 一键替换「赛博姐姐」应用图标
#
# 用法（在 dsha-mobile 目录下）：
#   .\tools\apply_icon.ps1 -Source C:\path\to\new_icon.png
#   .\tools\apply_icon.ps1 -Source .\new_icon.png -Preview      # 顺便生成预览图
#   .\tools\apply_icon.ps1 -Source .\new_icon.png -Build        # 替换后直接编译 debug APK
#
# 它会做三件事：
#   1. 生成 5 个密度档的传统图标 + 圆形图标
#   2. 生成 5 个密度档的 Adaptive Icon 前景（108dp 画布，图形落在 72dp 安全区内）
#   3. 写入 mipmap-anydpi-v26/ic_launcher.xml（Android 8.0+ 自适应图标）

param(
    [Parameter(Mandatory = $true)][string]$Source,
    [switch]$Preview,
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path $Source)) { throw "找不到源图：$Source" }

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { throw "找不到 python，请先安装 Python 3 并执行 pip install pillow" }

Write-Host "==> 生成图标" -ForegroundColor Cyan
$args = @((Join-Path $root 'tools\make_icons.py'), (Resolve-Path $Source).Path)
if ($Preview) { $args += '--preview' }
& $python @args
if ($LASTEXITCODE -ne 0) { throw "图标生成失败，退出码 $LASTEXITCODE" }

Write-Host "==> 已替换以下目录：" -ForegroundColor Cyan
Get-ChildItem (Join-Path $root 'app\src\main\res') -Directory -Filter 'mipmap-*' |
    ForEach-Object { Write-Host "    $($_.Name)" }

if ($Build) {
    Write-Host "==> 编译 debug APK" -ForegroundColor Cyan
    & (Join-Path $root 'build_debug.ps1')
}

Write-Host "完成。" -ForegroundColor Green
