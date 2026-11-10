# Keeps the Electron -> tailnet bridge healthy.
#
#   Electron host 127.0.0.1:<random>   auth = signed cookie, port changes every launch
#        ^ cookie captured from the main process (--inspect=9229)
#   proxy 127.0.0.1:<port>  <- tailscale serve <- phone
#
# Loop: ensure proxy -> probe it -> if it is not serving 200, re-capture the
# cookie (app restarted => new port => old cookie invalid).
#
# Start hidden (no console window), e.g. from a .vbs in the Startup folder:
#   CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -WindowStyle Hidden " & _
#     "-ExecutionPolicy Bypass -File <path>\supervisor.ps1", 0, False

param(
    [int]$ProxyPort = 8791,
    [int]$MainDebugPort = 9229,
    [int]$PageDebugPort = 9222,
    [int]$IntervalSeconds = 5,
    [string]$NodeExe = 'C:\Program Files\nodejs\node.exe',
    [string]$ProfileDir = (Join-Path $env:USERPROFILE '.dsh')
)

$ErrorActionPreference = 'SilentlyContinue'

$log       = Join-Path $ProfileDir 'dsh-electron.log'
$proxyJs   = Join-Path $PSScriptRoot 'proxy.js'
$captureJs = Join-Path $PSScriptRoot 'capture-cookie.js'
$stateFile = Join-Path $ProfileDir 'electron-cookie.json'

$mutex = New-Object System.Threading.Mutex($false, 'Global\DshElectronBridgeSupervisor')
if (-not $mutex.WaitOne(0)) { exit 0 }

function Write-Log([string]$msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Out-File -FilePath $log -Append -Encoding utf8
}

function Test-Port([int]$p) {
    try {
        $c = [System.Net.Sockets.TcpClient]::new()
        $c.Connect('127.0.0.1', $p)
        $c.Close()
        return $true
    } catch { return $false }
}

function Ensure-Proxy {
    if (Test-Port $ProxyPort) { return }
    Write-Log 'starting proxy'
    Start-Process -FilePath $NodeExe -WindowStyle Hidden -ArgumentList @($proxyJs, "$ProxyPort", $stateFile) | Out-Null
    Start-Sleep -Seconds 2
}

function Probe-Proxy {
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:$ProxyPort/" -UseBasicParsing -TimeoutSec 8
        return [int]$r.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

Write-Log '--- electron bridge supervisor start ---'

$lastCapture = [DateTime]::MinValue
while ($true) {
    Ensure-Proxy

    # 200 = healthy. 401/503 = cookie missing or stale (app restarted).
    $code = Probe-Proxy
    if ($code -ne 200 -and ((Get-Date) - $lastCapture).TotalSeconds -gt 20) {
        Write-Log "proxy returned $code, capturing cookie"
        & $NodeExe $captureJs $MainDebugPort $PageDebugPort $stateFile 30 *> $null
        $lastCapture = Get-Date
        Write-Log "after capture: $(Probe-Proxy)"
    }

    Start-Sleep -Seconds $IntervalSeconds
}
