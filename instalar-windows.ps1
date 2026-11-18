param(
    [switch]$SkipModels,
    [switch]$NoLaunch,
    [switch]$ForceRuntime
)

$ErrorActionPreference = 'Stop'
$appRoot = $PSScriptRoot
$runtimeRoot = Join-Path $appRoot '.runtime'
$nodeRoot = Join-Path $runtimeRoot 'node'
$nodeExe = Join-Path $nodeRoot 'node.exe'
$npmExe = Join-Path $nodeRoot 'npm.cmd'
$modelsFile = Join-Path $appRoot 'models.txt'
$temporaryRoot = Join-Path $env:TEMP ("ia-local-install-" + [guid]::NewGuid().ToString('N'))
$ollamaWasRunning = $false
$ollamaStartedForInstall = $null

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-OllamaServer {
    try {
        $response = Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -eq 200
    }
    catch { return $false }
}

function Find-OllamaExecutable {
    $command = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        (Join-Path $env:LOCALAPPDATA 'Ollama\ollama.exe'),
        (Join-Path $env:ProgramFiles 'Ollama\ollama.exe')
    )
    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function Install-PortableNode {
    if ((Test-Path -LiteralPath $nodeExe) -and -not $ForceRuntime) {
        Write-Host "Node local ya está instalado: $(& $nodeExe --version)" -ForegroundColor Green
        return
    }

    Write-Step 'Descargando Node.js LTS local'
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $releases = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
    $fileLabel = "win-$architecture-zip"
    $release = $releases | Where-Object { $_.lts -and $_.files -contains $fileLabel } | Select-Object -First 1
    if (-not $release) { throw "No encontré una versión LTS de Node para Windows $architecture." }

    $version = [string]$release.version
    $archiveName = "node-$version-win-$architecture.zip"
    $baseUrl = "https://nodejs.org/dist/$version"
    $archivePath = Join-Path $temporaryRoot $archiveName
    $extractRoot = Join-Path $temporaryRoot 'node-extract'
    Invoke-WebRequest -Uri "$baseUrl/$archiveName" -OutFile $archivePath

    $checksums = Invoke-RestMethod -Uri "$baseUrl/SHASUMS256.txt"
    $checksumPattern = "(?m)^([a-f0-9]{64})\s+$([regex]::Escape($archiveName))\s*$"
    $checksumMatch = [regex]::Match([string]$checksums, $checksumPattern)
    if (-not $checksumMatch.Success) { throw 'No pude encontrar el checksum oficial de Node.js.' }
    $actualChecksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualChecksum -ne $checksumMatch.Groups[1].Value) { throw 'El checksum de Node.js no coincide.' }

    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
    $extractedNode = Get-ChildItem -LiteralPath $extractRoot -Directory | Select-Object -First 1
    if (-not $extractedNode) { throw 'El archivo de Node.js no contiene la carpeta esperada.' }

    $expectedNodeRoot = [IO.Path]::GetFullPath((Join-Path $appRoot '.runtime\node'))
    if ([IO.Path]::GetFullPath($nodeRoot) -ne $expectedNodeRoot) { throw 'La ruta del runtime local no es segura.' }
    if (Test-Path -LiteralPath $nodeRoot) { Remove-Item -LiteralPath $nodeRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    Move-Item -LiteralPath $extractedNode.FullName -Destination $nodeRoot
    Write-Host "Node $version instalado dentro del proyecto." -ForegroundColor Green
}

function Install-OllamaIfMissing {
    $existing = Find-OllamaExecutable
    if ($existing) {
        Write-Host "Ollama ya está instalado: $existing" -ForegroundColor Green
        return $existing
    }

    Write-Step 'Instalando Ollama desde el instalador oficial'
    $installerPath = Join-Path $temporaryRoot 'ollama-install.ps1'
    Invoke-WebRequest -Uri 'https://ollama.com/install.ps1' -OutFile $installerPath
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installerPath
    if ($LASTEXITCODE -ne 0) { throw "El instalador oficial de Ollama terminó con código $LASTEXITCODE." }

    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $installed = Find-OllamaExecutable
    if (-not $installed) { throw 'Ollama terminó de instalarse, pero no encontré ollama.exe.' }
    return $installed
}

function Disable-OllamaAutoStart {
    try {
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Ollama' -ErrorAction SilentlyContinue
        $startupShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk'
        if (Test-Path -LiteralPath $startupShortcut) { Remove-Item -LiteralPath $startupShortcut -Force }
    }
    catch {}
}

function Ensure-OllamaServer {
    param([string]$OllamaExecutable)
    if (Test-OllamaServer) { return }

    Write-Step 'Iniciando Ollama para descargar los modelos'
    $script:ollamaStartedForInstall = Start-Process -FilePath $OllamaExecutable -ArgumentList @('serve') -WindowStyle Hidden -PassThru
    for ($attempt = 0; $attempt -lt 80; $attempt++) {
        Start-Sleep -Milliseconds 250
        if (Test-OllamaServer) { return }
    }
    throw 'Ollama no respondió en http://127.0.0.1:11434.'
}

function Install-Models {
    param([string]$OllamaExecutable)
    if ($SkipModels) {
        Write-Host 'Descarga de modelos omitida por parámetro.' -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path -LiteralPath $modelsFile)) { throw 'No encontré models.txt.' }

    $models = Get-Content -LiteralPath $modelsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
    foreach ($model in $models) {
        Write-Step "Descargando modelo $model"
        & $OllamaExecutable pull $model
        if ($LASTEXITCODE -ne 0) { throw "No se pudo descargar $model." }
    }
}

function Install-NodeDependencies {
    Write-Step 'Instalando dependencias de IA Local'
    Push-Location $appRoot
    try {
        & $npmExe ci --omit=dev --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw "npm ci terminó con código $LASTEXITCODE." }
    }
    finally { Pop-Location }
}

function Install-Shortcuts {
    Write-Step 'Creando accesos directos'
    $target = Join-Path $appRoot 'IA Local.exe'
    if (-not (Test-Path -LiteralPath $target)) { $target = Join-Path $appRoot 'iniciar-chat.bat' }
    $icon = Join-Path $appRoot 'IA-Local.ico'
    $shell = New-Object -ComObject WScript.Shell
    $shortcutPaths = @(
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'IA Local.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'IA Local.lnk')
    )
    foreach ($shortcutPath in $shortcutPaths) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $target
        $shortcut.WorkingDirectory = $appRoot
        if (Test-Path -LiteralPath $icon) { $shortcut.IconLocation = "$icon,0" }
        $shortcut.Description = 'Chat local con Ollama'
        $shortcut.Save()
    }
}

New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
try {
    Write-Host 'Instalador de IA Local para Windows' -ForegroundColor Magenta
    Write-Host "Proyecto: $appRoot"
    $ollamaWasRunning = Test-OllamaServer
    Install-PortableNode
    Install-NodeDependencies
    $ollamaExecutable = Install-OllamaIfMissing
    Disable-OllamaAutoStart
    Ensure-OllamaServer -OllamaExecutable $ollamaExecutable
    Install-Models -OllamaExecutable $ollamaExecutable
    Install-Shortcuts

    Write-Host "`nIA Local quedó instalado correctamente." -ForegroundColor Green
}
finally {
    if ($ollamaStartedForInstall -and -not $ollamaStartedForInstall.HasExited) {
        Stop-Process -Id $ollamaStartedForInstall.Id -Force -ErrorAction SilentlyContinue
    }
    if (-not $ollamaWasRunning -and -not $ollamaStartedForInstall) {
        Get-Process -Name 'ollama' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if (-not $NoLaunch) {
    Write-Step 'Abriendo IA Local'
    $launcher = Join-Path $appRoot 'IA Local.exe'
    if (Test-Path -LiteralPath $launcher) { Start-Process -FilePath $launcher }
    else { Start-Process -FilePath (Join-Path $appRoot 'iniciar-chat.bat') }
}
