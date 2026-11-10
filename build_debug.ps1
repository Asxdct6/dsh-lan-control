# 编译「赛博姐姐」debug APK
#
# 用法：在 dsha-mobile 目录下执行
#   .\build_debug.ps1
#   .\build_debug.ps1 -DshUrl http://192.168.1.4:8787/    # 指定内置连接地址
#
# 依赖：JDK 17、Android SDK (platform-34 / build-tools 34.0.0)、Gradle

param(
    [string]$DshUrl = ""
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# ---- 工具链定位（优先环境变量，其次默认安装位置）----
if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
    $candidates = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending
    if ($candidates) { $env:JAVA_HOME = $candidates[0].FullName }
}
if (-not $env:JAVA_HOME) { throw "找不到 JDK 17，请设置 JAVA_HOME" }

if (-not $env:ANDROID_HOME -or -not (Test-Path $env:ANDROID_HOME)) {
    $env:ANDROID_HOME = 'C:\Android\sdk'
}
if (-not (Test-Path $env:ANDROID_HOME)) { throw "找不到 Android SDK，请设置 ANDROID_HOME" }
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

Write-Host "JAVA_HOME    = $env:JAVA_HOME" -ForegroundColor DarkGray
Write-Host "ANDROID_HOME = $env:ANDROID_HOME" -ForegroundColor DarkGray

# sdk.dir
"sdk.dir=$($env:ANDROID_HOME -replace '\\','\\')" |
    Set-Content -Path (Join-Path $root 'local.properties') -Encoding ASCII

# ---- 选择 gradle ----
$gradle = Join-Path $root 'gradlew.bat'
if (-not (Test-Path $gradle)) {
    $fallback = 'C:\Android\tmp\g\gradle-8.7\bin\gradle.bat'
    if (Test-Path $fallback) { $gradle = $fallback } else { $gradle = 'gradle' }
}

$gradleArgs = @('assembleDebug', '--no-daemon', '--console=plain')
if ($DshUrl) { $gradleArgs += "-Pdsh.url=$DshUrl" }

Write-Host "==> $gradle $($gradleArgs -join ' ')" -ForegroundColor Cyan
& $gradle @gradleArgs
if ($LASTEXITCODE -ne 0) { throw "编译失败，退出码 $LASTEXITCODE" }

$apk = Get-ChildItem (Join-Path $root 'app\build\outputs\apk\debug') -Filter '*.apk' |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $apk) { throw "没找到 APK 产物" }

Write-Host ""
Write-Host "APK: $($apk.FullName)" -ForegroundColor Green
Write-Host "大小: $([math]::Round($apk.Length/1MB,2)) MB" -ForegroundColor Green
