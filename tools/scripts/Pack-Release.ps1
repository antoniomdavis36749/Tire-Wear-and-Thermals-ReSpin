#Requires -Version 5.1
param(
    [string]$OutDir = '',
    [string]$ZipName = 'TireWearThermalsReSpin.zip',
    # Empty = auto-pack TireWearThermalsReSpin_CompatTires.zip when vehicles/ exists.
    # Pass a name to override; use -SkipCompatTires to omit.
    [string]$CompatTiresZip = '',
    [switch]$SkipCompatTires
)

$ErrorActionPreference = 'Stop'
$ModRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $OutDir) {
    $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function New-ZipFromStage {
    param([string]$StageDir, [string]$DestZip)
    # BeamNG zipFS requires forward-slash entry names. .NET CreateFromDirectory on
    # Windows writes backslashes, which mounts the zip but hides ui/lua/scripts.
    $py = @'
import sys, zipfile
from pathlib import Path
stage = Path(sys.argv[1])
dest = Path(sys.argv[2])
if dest.exists():
    dest.unlink()
with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    dirs = set()
    files = []
    for p in stage.rglob("*"):
        rel = p.relative_to(stage).as_posix()
        if p.is_dir():
            dirs.add(rel.rstrip("/") + "/")
            parts = rel.split("/")
            for i in range(1, len(parts)):
                dirs.add("/".join(parts[:i]) + "/")
        else:
            files.append(p)
            parts = rel.split("/")
            for i in range(1, len(parts)):
                dirs.add("/".join(parts[:i]) + "/")
    for d in sorted(dirs):
        zf.writestr(zipfile.ZipInfo(d), b"")
    for p in files:
        arc = p.relative_to(stage).as_posix()
        zf.write(p, arcname=arc)
print(dest)
'@
    $tmpPy = Join-Path $env:TEMP ('respin-zip-' + [guid]::NewGuid().ToString('N') + '.py')
    Set-Content -Path $tmpPy -Value $py -Encoding UTF8
    try {
        python $tmpPy $StageDir $DestZip
        if ($LASTEXITCODE -ne 0) { throw "Python zip failed ($LASTEXITCODE)" }
    } finally {
        Remove-Item -Force $tmpPy -ErrorAction SilentlyContinue
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($DestZip)
    try {
        $roots = $zip.Entries | ForEach-Object {
            ($_.FullName -replace '\\', '/').Split('/')[0]
        } | Select-Object -Unique | Sort-Object
        Write-Host ("Wrote $DestZip")
        Write-Host ("Zip root entries: " + ($roots -join ', '))
    } finally {
        $zip.Dispose()
    }
}

if ($ZipName -notmatch '\.zip$') { $ZipName = "$ZipName.zip" }
$zipPath = Join-Path $OutDir $ZipName

$stage = Join-Path $env:TEMP ("respin-pack-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

try {
    # Core only. Never include vehicles/ in the main zip: BeamNG sets mountPoint=vehicles/
    # for vehicle-classified zips, which hides ui/lua/scripts (Apps vanish).
    foreach ($d in @('lua', 'ui', 'scripts')) {
        $src = Join-Path $ModRoot $d
        if (-not (Test-Path $src)) { throw "Missing required folder: $src" }
        Copy-Item -Recurse -Force $src (Join-Path $stage $d)
    }

    foreach ($f in @('license', 'CREDITS.md', 'NOTICE', 'README.md', 'LISTING.md', 'COMPAT_TIRES.md')) {
        $src = Join-Path $ModRoot $f
        if (Test-Path $src) { Copy-Item -Force $src (Join-Path $stage $f) }
    }

    $mi = Join-Path $ModRoot 'mod_info'
    if (Test-Path $mi) {
        Copy-Item -Recurse -Force $mi (Join-Path $stage 'mod_info')
        # Companion identity belongs only in the compat-tires zip.
        $compatMi = Join-Path $stage 'mod_info\TWTRS_COMPAT'
        if (Test-Path $compatMi) { Remove-Item -Recurse -Force $compatMi }
        Get-ChildItem (Join-Path $stage 'mod_info') -Recurse -Filter 'icon-redux-reference.jpg' -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    $lap = Join-Path $stage 'lua\ge\extensions\tyreWestCoastLapTest.lua'
    if (Test-Path $lap) {
        Remove-Item -Force $lap
        Write-Host 'Excluded tyreWestCoastLapTest.lua from package'
    }

    New-ZipFromStage -StageDir $stage -DestZip $zipPath
    Write-Host 'NOTE: vehicles/ excluded from main zip (prevents vehicle mountPoint hiding UI).'
    Write-Host 'NOTE: zip entries use forward slashes (required by BeamNG zipFS).'
}
finally {
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
}

$vehicles = Join-Path $ModRoot 'vehicles'
if (-not $SkipCompatTires -and (Test-Path $vehicles)) {
    if (-not $CompatTiresZip) {
        $CompatTiresZip = 'TireWearThermalsReSpin_CompatTires.zip'
    }
    if ($CompatTiresZip -notmatch '\.zip$') { $CompatTiresZip = "$CompatTiresZip.zip" }
    $vstage = Join-Path $env:TEMP ("respin-veh-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $vstage | Out-Null
    try {
        Copy-Item -Recurse -Force $vehicles (Join-Path $vstage 'vehicles')
        foreach ($f in @('COMPAT_TIRES.md', 'license', 'NOTICE', 'CREDITS.md')) {
            $src = Join-Path $ModRoot $f
            if (Test-Path $src) { Copy-Item -Force $src (Join-Path $vstage $f) }
        }
        $compatInfo = Join-Path $ModRoot 'mod_info\TWTRS_COMPAT'
        if (Test-Path $compatInfo) {
            New-Item -ItemType Directory -Force -Path (Join-Path $vstage 'mod_info') | Out-Null
            Copy-Item -Recurse -Force $compatInfo (Join-Path $vstage 'mod_info\TWTRS_COMPAT')
        }
        New-ZipFromStage -StageDir $vstage -DestZip (Join-Path $OutDir $CompatTiresZip)
        Write-Host 'Compat tires zip is a separate vehicle companion (install alongside core).'
    }
    finally {
        if (Test-Path $vstage) { Remove-Item -Recurse -Force $vstage }
    }
}
elseif ($CompatTiresZip -and -not (Test-Path $vehicles)) {
    throw 'No vehicles/ folder for compat tires zip'
}
elseif ($SkipCompatTires) {
    Write-Host 'Skipped compat tires zip (-SkipCompatTires).'
}
