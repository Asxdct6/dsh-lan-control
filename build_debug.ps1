# Build a debug APK for 局域网控制 DSH
#
# Usage (from this directory):
#   .\build_debug.ps1                                          # uses the default URL baked in gradle
#   .\build_debug.ps1 -DshUrl "http://192.168.1.100:8787/?token=xxxx"
#
# Requires: JDK 17 (JAVA_HOME or on PATH), Android SDK (ANDROID_HOME or ANDROID_SDK_ROOT),
#           platform-34 + build-tools 34.0.0 installed via sdkmanager.

param(
    [string]$DshUrl = ""
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

# ---- locate JDK ----
if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
    $java = (Get-Command java -ErrorAction SilentlyContinue).Source
    if ($java) {
        $env:JAVA_HOME = Split-Path (Split-Path $java -Parent) -Parent
    }
}
if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
    throw "JDK 17 not found. Install one and set JAVA_HOME (e.g. winget install EclipseAdoptium.Temurin.17.JDK)"
}

# ---- locate Android SDK ----
if (-not $env:ANDROID_HOME -or -not (Test-Path $env:ANDROID_HOME)) {
    $env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
}
if (-not $env:ANDROID_HOME -or -not (Test-Path $env:ANDROID_HOME)) {
    $guess = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (Test-Path $guess) { $env:ANDROID_HOME = $guess }
}
if (-not $env:ANDROID_HOME -or -not (Test-Path $env:ANDROID_HOME)) {
    throw "Android SDK not found. Set ANDROID_HOME to your SDK path."
}
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

Write-Host "JAVA_HOME    = $env:JAVA_HOME" -ForegroundColor DarkGray
Write-Host "ANDROID_HOME = $env:ANDROID_HOME" -ForegroundColor DarkGray

# local.properties (git-ignored)
"sdk.dir=$($env:ANDROID_HOME -replace '\\','\\')" |
    Set-Content -Path (Join-Path $root 'local.properties') -Encoding ASCII

# ---- run gradle via wrapper ----
$gradle = Join-Path $root 'gradlew.bat'
if (-not (Test-Path $gradle)) { $gradle = 'gradle' }

$gradleArgs = @('assembleDebug', '--no-daemon', '--console=plain')
if ($DshUrl) { $gradleArgs += "-Pdsh.url=$DshUrl" }

Write-Host "==> $gradle $($gradleArgs -join ' ')" -ForegroundColor Cyan
& $gradle @gradleArgs
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }

$apk = Get-ChildItem (Join-Path $root 'app\build\outputs\apk\debug') -Filter '*.apk' -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $apk) { throw "No APK produced" }

Write-Host ""
Write-Host "APK : $($apk.FullName)" -ForegroundColor Green
Write-Host "Size: $([math]::Round($apk.Length/1MB,2)) MB" -ForegroundColor Green
