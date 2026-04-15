$ErrorActionPreference = 'Stop'

$sourceDir = Join-Path $PSScriptRoot '..\mod'
$modsRoot = Join-Path $env:APPDATA 'Balatro\Mods'
$targetDir = Join-Path $modsRoot 'balatro_mcp'

if (-not (Test-Path $sourceDir)) {
  throw "Source mod directory not found: $sourceDir"
}

if (-not (Test-Path $modsRoot)) {
  New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
}

if (-not (Test-Path $targetDir)) {
  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Get-ChildItem -Path $targetDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Copy-Item -Path (Join-Path $sourceDir 'entry.lua') -Destination (Join-Path $targetDir 'entry.lua') -Force
Copy-Item -Path (Join-Path $sourceDir 'mod.json') -Destination (Join-Path $targetDir 'mod.json') -Force

Get-ChildItem -Path (Join-Path $sourceDir '*.lua') -File | Where-Object { $_.Name -ne 'entry.lua' } | ForEach-Object {
  Copy-Item -Path $_.FullName -Destination (Join-Path $targetDir $_.Name) -Force
}

$webSource = Join-Path $sourceDir 'web'
$webTarget = Join-Path $targetDir 'web'
if (Test-Path $webSource) {
  Copy-Item -Path $webSource -Destination $webTarget -Recurse -Force
}

Write-Output "Deployed balatro_mcp mod to: $targetDir"
Get-ChildItem -Path $targetDir | Select-Object Name, Length | Format-Table -AutoSize
