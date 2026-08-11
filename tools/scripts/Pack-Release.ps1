#Requires -Version 5.1
<#
.SYNOPSIS
  Build a BeamNG Repo–correct release zip for Tire Wear and Thermals ReSpin.

.DESCRIPTION
  Zips top-level game folders only (lua, ui, scripts, vehicles when present, …) — NOT the parent mod folder.
  Excludes tools/, .vscode/, .git/, and the West Coast lap-test harness.
  vehicles/ holds optional compatibility tire JBeams (COMPAT_TIRES.md); never pack companion meshes.

.PARAMETER OutDir
  Folder for the zip (default: tools/output).

.PARAMETER ZipName
  Zip filename without path. Do not put a version number in the name for Repo updates.
  Default: TireWearThermalsReSpin.zip

.EXAMPLE
  .\Pack-Release.ps1
  .\Pack-Release.ps1 -ZipName 'TireWearThermalsReSpin_YourName.zip'
#>
param(
    [string]$OutDir = '',
    [string]$ZipName = 'TireWearThermalsReSpin.zip'
)

$ErrorActionPreference = 'Stop'
$ModRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $OutDir) {
    $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ($ZipName -notmatch '\.zip$') { $ZipName = "$ZipName.zip" }
$zipPath = Join-Path $OutDir $ZipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

$stage = Join-Path $env:TEMP ("respin-pack-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

try {
    # lua/ui/scripts required; vehicles/ ships optional compatibility tire JBeams (see COMPAT_TIRES.md)
    $includeDirs = @('lua', 'ui', 'scripts')
    foreach ($d in $includeDirs) {
        $src = Join-Path $ModRoot $d
        if (-not (Test-Path $src)) { throw "Missing required folder: $src" }
        Copy-Item -Recurse -Force $src (Join-Path $stage $d)
    }

    $vehicles = Join-Path $ModRoot 'vehicles'
    if (Test-Path $vehicles) {
        Copy-Item -Recurse -Force $vehicles (Join-Path $stage 'vehicles')
        Write-Host "Included vehicles/ (compatibility tires)"
    }

    foreach ($f in @('license', 'CREDITS.md', 'NOTICE', 'README.md', 'LISTING.md', 'COMPAT_TIRES.md')) {
        $src = Join-Path $ModRoot $f
        if (Test-Path $src) {
            Copy-Item -Force $src (Join-Path $stage $f)
        }
    }

    # Optional cleaned mod_info for local testing; Repo may rewrite on upload
    $mi = Join-Path $ModRoot 'mod_info'
    if (Test-Path $mi) {
        Copy-Item -Recurse -Force $mi (Join-Path $stage 'mod_info')
        Get-ChildItem (Join-Path $stage 'mod_info') -Recurse -Filter 'icon-redux-reference.jpg' -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    # Strip West Coast lap harness from player package
    $lap = Join-Path $stage 'lua\ge\extensions\tyreWestCoastLapTest.lua'
    if (Test-Path $lap) {
        Remove-Item -Force $lap
        Write-Host "Excluded tyreWestCoastLapTest.lua from package"
    }

    # Compress contents of stage (top-level folders at zip root)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)

    Write-Host "Wrote $zipPath"
    Write-Host "Verify: opening the zip should show lua/, ui/, scripts/ (and vehicles/ if present) at the root (not a parent mod folder)."
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $roots = $zip.Entries | ForEach-Object {
            ($_.FullName -replace '\\', '/').Split('/')[0]
        } | Select-Object -Unique | Sort-Object
        Write-Host ("Zip root entries: " + ($roots -join ', '))
    } finally {
        $zip.Dispose()
    }
}
finally {
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
}
