$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Dist = Join-Path $Root "dist"
$Runtime = Join-Path $Dist "runtime"

Write-Host "Katalog projektu: $Root"
Write-Host "Katalog wynikowy: $Dist"

Set-Location $Root

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw "Nie znaleziono Node.js."
}

if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    throw "Nie znaleziono npm.cmd."
}

Write-Host "Node:"
node.exe --version

Write-Host "npm:"
npm.cmd --version

if (Test-Path $Dist) {
    Remove-Item $Dist -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
New-Item -ItemType Directory -Force -Path $Runtime | Out-Null

Write-Host "Instalowanie zaleznosci..."
npm.cmd install

Write-Host "Sprawdzanie skladni..."
npm.cmd run check

$FilesToCopy = @(
    "agent.js",
    "config.js",
    "diagnostic.js",
    "pairing.js",
    "app.ps1",
    "install-service.js",
    "uninstall-service.js",
    "package.json"
)

foreach ($File in $FilesToCopy) {
    $Source = Join-Path $Root $File

    if (Test-Path $Source) {
        Copy-Item $Source $Dist -Force
        Write-Host "Skopiowano: $File"
    }
    else {
        Write-Host "Pomijam brakujacy plik: $File"
    }
}

if (Test-Path (Join-Path $Root ".env.example")) {
    Copy-Item `
        (Join-Path $Root ".env.example") `
        (Join-Path $Dist ".env.example") `
        -Force
}

if (-not (Test-Path (Join-Path $Root "node_modules"))) {
    throw "Nie powstal katalog node_modules."
}

Copy-Item `
    (Join-Path $Root "node_modules") `
    (Join-Path $Dist "node_modules") `
    -Recurse `
    -Force

$NodeExe = (Get-Command node.exe).Source

if (-not (Test-Path $NodeExe)) {
    throw "Nie znaleziono node.exe pod sciezka: $NodeExe"
}

Copy-Item `
    $NodeExe `
    (Join-Path $Runtime "node.exe") `
    -Force

@'
@echo off
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0runtime\node.exe" "%~dp0agent.js"
'@ | Set-Content `
    (Join-Path $Dist "start-agent.cmd") `
    -Encoding ASCII

@'
@echo off
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0runtime\node.exe" "%~dp0diagnostic.js"
echo.
pause
'@ | Set-Content `
    (Join-Path $Dist "diagnostic.cmd") `
    -Encoding ASCII

Write-Host ""
Write-Host "Zawartosc dist:"
Get-ChildItem $Dist -Force

Write-Host ""
Write-Host "Zawartosc runtime:"
Get-ChildItem $Runtime -Force

if (-not (Test-Path (Join-Path $Runtime "node.exe"))) {
    throw "Nie udalo sie utworzyc dist\runtime\node.exe"
}

Write-Host ""
Write-Host "Aplikacja zostala przygotowana poprawnie."
