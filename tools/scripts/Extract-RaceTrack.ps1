$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$lz = 'C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive\content\levels\west_coast_usa.zip'
$outDir = $PSScriptRoot
$z = [System.IO.Compression.ZipFile]::OpenRead($lz)

function Extract-Entry([string]$entryName, [string]$outName) {
  $e = $z.Entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
  if (-not $e) {
    Write-Host "MISSING: $entryName"
    return $false
  }
  $sr = New-Object System.IO.StreamReader($e.Open())
  $t = $sr.ReadToEnd()
  $sr.Close()
  $out = Join-Path $outDir $outName
  [IO.File]::WriteAllText($out, $t)
  Write-Host "WROTE $outName len=$($t.Length)"
  return $true
}

Write-Host '--- quickrace entries ---'
$z.Entries | Where-Object { $_.FullName -match 'quickrace/' } | ForEach-Object { $_.FullName }

Extract-Entry 'levels/west_coast_usa/quickrace/race_track.json' 'race_track.json' | Out-Null
Extract-Entry 'levels/west_coast_usa/facilities/belasco1.race.json' 'belasco1-from-game.race.json' | Out-Null

# Prefab snippet if text
$prefab = $z.Entries | Where-Object { $_.FullName -match 'quickrace/race_track\.prefab' } | Select-Object -First 1
if ($prefab) {
  Write-Host "prefab=$($prefab.FullName) size=$($prefab.Length)"
}

$z.Dispose()

# Peek race_track.json
$rt = Join-Path $outDir 'race_track.json'
if (Test-Path $rt) {
  Write-Host '--- race_track.json head ---'
  Get-Content $rt -TotalCount 80
}
