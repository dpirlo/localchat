$ErrorActionPreference = 'Stop'
$appUrl = 'http://127.0.0.1:8765'
$serverPath = Join-Path $PSScriptRoot 'server.js'
$ollamaStartedByLauncher = $false
$ollamaProcess = $null
$nodeProcess = $null

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

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    Write-Host 'No encontré Node.js en el PATH.' -ForegroundColor Red
    Write-Host 'Instalalo y volvé a ejecutar iniciar-chat.bat.'
    exit 1
}

Stop-StaleChatServer
$nodeProcess = Start-Process node.exe -ArgumentList @($serverPath) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru

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

try {
    if ($chrome) {
        Start-Process $chrome -ArgumentList @("--app=$appUrl", '--start-maximized')
    }
    else {
        Start-Process $appUrl
    }
    Wait-Process -Id $nodeProcess.Id
}
finally {
    if ($nodeProcess -and -not $nodeProcess.HasExited) {
        Stop-Process -Id $nodeProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($ollamaStartedByLauncher -and $ollamaProcess -and -not $ollamaProcess.HasExited) {
        Stop-Process -Id $ollamaProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
