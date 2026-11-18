$ErrorActionPreference = 'Stop'
$appUrl = 'http://127.0.0.1:8765'
$serverPath = Join-Path $PSScriptRoot 'server.js'
$localNodePath = Join-Path $PSScriptRoot '.runtime\node\node.exe'
$ollamaStartedByLauncher = $false
$ollamaProcess = $null
$nodeProcess = $null
$previousPowerSchemeGuid = $null
$performanceProfileEnabled = $false

function Set-GpuHighPerformancePreference {
    param([string]$ExecutablePath)
    if (-not $ExecutablePath -or -not (Test-Path -LiteralPath $ExecutablePath)) { return }
    try {
        $gpuPreferencePath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
        New-Item -Path $gpuPreferencePath -Force | Out-Null
        New-ItemProperty -Path $gpuPreferencePath -Name $ExecutablePath -PropertyType String -Value 'GpuPreference=2;' -Force | Out-Null
    }
    catch {}
}

function Enable-PerformanceProfile {
    try {
        $activeScheme = (& powercfg.exe /getactivescheme 2>$null) -join ' '
        $schemeMatch = [regex]::Match($activeScheme, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
        if ($schemeMatch.Success) { $script:previousPowerSchemeGuid = $schemeMatch.Value }
        & powercfg.exe /setactive SCHEME_MIN 2>$null | Out-Null
        $script:performanceProfileEnabled = $true
    }
    catch {}

    $ollamaCommand = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($ollamaCommand) {
        Set-GpuHighPerformancePreference $ollamaCommand.Source
        $ollamaFolder = Split-Path -Parent $ollamaCommand.Source
        Set-GpuHighPerformancePreference (Join-Path $ollamaFolder 'lib\ollama\llama-server.exe')
    }
}

function Restore-PerformanceProfile {
    if (-not $performanceProfileEnabled -or -not $previousPowerSchemeGuid) { return }
    try { & powercfg.exe /setactive $previousPowerSchemeGuid 2>$null | Out-Null }
    catch {}
}

function Set-InferenceProcessPriority {
    Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::AboveNormal) {
                $_.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::AboveNormal
            }
        }
        catch {}
    }
}

function Test-ChatServer {
    try {
        $status = Invoke-RestMethod -Uri "$appUrl/api/status" -TimeoutSec 1
        return $status.ok -and $status.app -eq 'ia-local-mini-chat'
    }
    catch { return $false }
}

function Stop-StaleChatServer {
    $isMiniChatServer = $false
    try {
        $status = Invoke-RestMethod -Uri "$appUrl/api/status" -TimeoutSec 1
        $isMiniChatServer = $status.ok -and $status.app -eq 'ia-local-mini-chat'
    }
    catch {}
    $listeners = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
    foreach ($listener in $listeners) {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)" -ErrorAction SilentlyContinue
        $isThisPath = $processInfo.CommandLine -like "*$serverPath*"
        if ($processInfo.Name -eq 'node.exe' -and $isThisPath) {
            Write-Host 'Reiniciando una versión anterior del chat...' -ForegroundColor Cyan
            Stop-Process -Id $listener.OwningProcess -Force
            Start-Sleep -Milliseconds 500
        }
    }
}

function Test-OllamaServer {
    try {
        $response = Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -eq 200
    }
    catch { return $false }
}

try {
    Enable-PerformanceProfile

if (-not (Test-OllamaServer)) {
    $ollamaCommand = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if (-not $ollamaCommand) {
        Write-Host 'No encontré Ollama instalado o disponible en el PATH.' -ForegroundColor Red
        exit 1
    }

    Write-Host 'Iniciando Ollama...' -ForegroundColor Cyan
    $ollamaProcess = Start-Process $ollamaCommand.Source -ArgumentList @('serve') -WindowStyle Hidden -PassThru
    $ollamaStartedByLauncher = $true

    $ollamaReady = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        Start-Sleep -Milliseconds 250
        if (Test-OllamaServer) { $ollamaReady = $true; break }
    }
    if (-not $ollamaReady) {
        Write-Host 'Ollama no pudo iniciar. Probá abrir la aplicación Ollama manualmente.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Ollama iniciado correctamente.' -ForegroundColor Green
}

$nodeExecutable = if (Test-Path -LiteralPath $localNodePath) {
    $localNodePath
}
else {
    (Get-Command node.exe -ErrorAction SilentlyContinue).Source
}

if (-not $nodeExecutable) {
    Write-Host 'No encontré Node.js en el PATH.' -ForegroundColor Red
    Write-Host 'Ejecutá instalar-windows.bat y volvé a abrir IA Local.'
    exit 1
}

Stop-StaleChatServer
$nodeProcess = Start-Process $nodeExecutable -ArgumentList @($serverPath) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru

$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 250
    if (Test-ChatServer) { $ready = $true; break }
}
if (-not $ready) {
    if ($nodeProcess -and -not $nodeProcess.HasExited) { Stop-Process -Id $nodeProcess.Id -Force }
    if ($ollamaStartedByLauncher -and $ollamaProcess -and -not $ollamaProcess.HasExited) { Stop-Process -Id $ollamaProcess.Id -Force }
    Write-Host 'El servidor no pudo iniciar.' -ForegroundColor Red
    exit 1
}

$chromeCandidates = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
)
$chrome = $chromeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

if ($chrome) {
    Start-Process $chrome -ArgumentList @("--app=$appUrl", '--start-maximized')
}
else {
    Start-Process $appUrl
}

while ($nodeProcess -and -not $nodeProcess.HasExited) {
    Set-InferenceProcessPriority
    Start-Sleep -Milliseconds 750
}
}
finally {
    if ($nodeProcess -and -not $nodeProcess.HasExited) {
        Stop-Process -Id $nodeProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($ollamaStartedByLauncher -and $ollamaProcess -and -not $ollamaProcess.HasExited) {
        Stop-Process -Id $ollamaProcess.Id -Force -ErrorAction SilentlyContinue
    }
    Restore-PerformanceProfile
}
