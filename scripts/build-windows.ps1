$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "Brak Node.js 20 x64 w PATH." }
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw "Brak npm w PATH." }

Set-Location $Root
Write-Host "== npm install =="
npm install
Write-Host "== npm run check (składnia) =="
npm run check
Write-Host "== npm install --save-dev @yao-pkg/pkg =="
npm install --save-dev @yao-pkg/pkg
Write-Host "== budowanie itrack-tacho-agent.exe =="
if (Test-Path (Join-Path $Root 'dist')) { Remove-Item (Join-Path $Root 'dist') -Recurse -Force }
npm run build:win

$exe = Join-Path $Root 'dist\itrack-tacho-agent.exe'
if (-not (Test-Path $exe)) { throw "Build nie utworzył $exe — sprawdź log pkg powyżej." }
Write-Host "Gotowe: $exe"
