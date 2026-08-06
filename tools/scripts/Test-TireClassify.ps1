# Unit check: Rally Asphalt vs Slick vs Rally descriptor routing
# Mirrors getInterpolatedProfile + vehicleHasPlainRallyDamper in
# lua/vehicle/extensions/auto/luukstyrethermalsandwear.lua
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'tire-classify-test.txt'
$sb = New-Object System.Text.StringBuilder
function Out([string]$s) { [void]$sb.AppendLine($s); Write-Host $s }

# Plain rally coilover/strut only — not suspension/spring/shock/damp, not strut_bar,
# not track/race/gravel/lights. Empty strings are ignored (no slot-key fallback).
function Test-HasPlainRallyDamper([string[]]$parts) {
  foreach ($raw in $parts) {
    if ([string]::IsNullOrEmpty($raw)) { continue }
    $n = $raw.ToLowerInvariant()
    if ($n -notlike '*rally*') { continue }
    if ($n -notmatch 'coilover|strut') { continue }
    if ($n -match 'strut_bar|strutbar|strutbrace') { continue }
    if ($n -match 'skin|paint|light|cover|interior|switch|track|circuit|gravel') { continue }
    if ($n -match '_race|race_') { continue }
    return $true
  }
  return $false
}

function Get-Descriptor([string]$tireName, [double]$treadCoef, [string[]]$parts) {
  $nameLower = $tireName.ToLowerInvariant()
  $isAsphaltName = ($nameLower -like '*tarmac*') -or (($nameLower -like '*asphalt*') -and ($nameLower -notlike '*supersport*'))
  $isAsphaltRallyRaceSku = ($nameLower -like '*race*') -and (
    ($nameLower -like '*180_580*') -or ($nameLower -like '*200_600*') -or ($nameLower -like '*210_600*')
  )
  $isGravelRallyName = ($nameLower -like '*rally*') -and -not $isAsphaltName
  $isRaceOrSlickName = ($nameLower -like '*slick*') -or ($nameLower -like '*race*')
  $hasDamper = Test-HasPlainRallyDamper $parts
  $isRallyAsphaltMount = $isAsphaltName -or $isAsphaltRallyRaceSku -or (
    $isRaceOrSlickName -and -not $isGravelRallyName -and ($nameLower -notlike '*gravel*') -and $hasDamper
  )

  if ($nameLower -match 'crawler|beadlock') { return 'Crawler' }
  if ($nameLower -match 'paddle|sand') { return 'Paddle' }
  if ($isRallyAsphaltMount) { return 'Rally Asphalt' }
  if ($isGravelRallyName) { return 'Rally' }
  if ($nameLower -match 'winter|snow') { return 'Winter' }
  if ($nameLower -match 'drag') { return 'Drag' }
  if ($nameLower -match 'drift') { return 'Drift' }
  if ($isRaceOrSlickName -or ($treadCoef -le 0.15)) { return 'Slick' }
  if ($treadCoef -le 0.20) { return 'Slick' }
  if ($treadCoef -le 0.42) { return 'Sport Plus' }
  if ($treadCoef -le 0.58) { return 'Sport' }
  return 'Standard'
}

$cases = @(
  # --- Pure race (must stay Slick) ---
  @{ name='Covet race'; tire='tire_F_195_50_15_race'; tread=0.0
    parts=@('covet_coilover_F_race','covet_rallylights','tire_F_195_50_15_race'); expect='Slick' }
  @{ name='Bolide race'; tire='tire_F_265_40_17_race'; tread=0.0
    parts=@('bolide_race_coilover_F','bolide_rallylights','tire_F_265_40_17_race'); expect='Slick' }
  @{ name='Bolide topspeed (same tires as asphalt, race dampers)'; tire='tire_F_245_45_16_race'; tread=0.0
    parts=@('bolide_coilover_F_race','bolide_coilover_R_race','tire_F_245_45_16_race'); expect='Slick' }
  @{ name='ETK GT4 race_DCT'; tire='tire_F_295_30_18_race'; tread=0.0
    parts=@('etkc_strut_F_wide_race','etkc_shock_R_race','etkc_spring_R_race','tire_F_295_30_18_race'); expect='Slick' }
  @{ name='Scintilla race'; tire='tire_F_295_35_19_race'; tread=0.0
    parts=@('scintilla_coilover_F_race','tire_F_295_35_19_race'); expect='Slick' }
  # REAL bug: Ardente race keeps vivace_suspension_*_rally + track coilovers
  @{ name='Vivace Ardente race (suspension_rally + track coilover)'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_suspension_F_rally','vivace_suspension_R_rally','vivace_rally_coilover_F_track','vivace_rally_coilover_R_track','vivace_rally_steering','vivace_rally_swaybar_F','tire_F_235_40_18_race'); expect='Slick' }
  @{ name='Vivace race_SQ'; tire='tire_F_245_35_19_race'; tread=0.0
    parts=@('vivace_strut_F_wide_race','vivace_shock_R_wide_race','vivace_spring_R_wide_race','tire_F_245_35_19_race'); expect='Slick' }
  @{ name='Race + suspension_rally only (no damper)'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_suspension_F_rally','vivace_suspension_R_rally'); expect='Slick' }
  @{ name='Race + spring/shock_rally must not remap'; tire='tire_F_265_40_17_race'; tread=0.0
    parts=@('bolide_spring_F_rally','bolide_shock_R_rally','tire_F_265_40_17_race'); expect='Slick' }
  @{ name='Low tread alone + suspension_rally stays Slick'; tire='tire_F_225_45_17_sport'; tread=0.05
    parts=@('vivace_suspension_F_rally'); expect='Slick' }

  # --- Asphalt rally ---
  @{ name='Covet rally_asphalt (race tire + rally coilover)'; tire='tire_F_180_580_15_altb_race'; tread=0.0
    parts=@('covet_coilover_F_rally','covet_rallylights','tire_F_180_580_15_altb_race'); expect='Rally Asphalt' }
  @{ name='Covet asphalt SKU alone (no hardware)'; tire='tire_F_180_580_15_altb_race'; tread=0.0
    parts=@(); expect='Rally Asphalt' }
  @{ name='Bolide rally_asphalt'; tire='tire_F_245_45_16_race'; tread=0.0
    parts=@('bolide_coilover_F_rally','bolide_coilover_R_rally','bolide_rallylights','tire_F_245_45_16_race'); expect='Rally Asphalt' }
  @{ name='BX rally_asp'; tire='tire_F_200_600_16_race'; tread=0.0
    parts=@('bx_strut_F_rally','bx_coilover_R_rally','tire_F_200_600_16_race'); expect='Rally Asphalt' }
  @{ name='BX asphalt SKU alone'; tire='tire_R_200_600_16_race'; tread=0.0
    parts=@(); expect='Rally Asphalt' }
  @{ name='210_600 race SKU alone'; tire='tire_F_210_600_16_race'; tread=0.0
    parts=@(); expect='Rally Asphalt' }
  # 210_650 is a real Race slick SKU, not asphalt-rally
  @{ name='210_650 race slick SKU'; tire='tire_F_210_650_19_race'; tread=0.0
    parts=@(); expect='Slick' }

  # Explicit asphalt / tarmac tire names → Rally Asphalt (hardware optional)
  @{ name='Scintilla rally (*_asphalt)'; tire='tire_F_245_40_18_asphalt'; tread=0.40
    parts=@('scintilla_coilover_F_rally'); expect='Rally Asphalt' }
  @{ name='Vivace Ardente asphalt'; tire='tire_F_235_40_18_asphalt'; tread=0.40
    parts=@('vivace_rally_coilover_F_asphalt','vivace_suspension_F_rally','tire_F_235_40_18_asphalt'); expect='Rally Asphalt' }
  @{ name='tarmac name alone'; tire='tire_F_205_55_16_tarmac'; tread=0.35
    parts=@(); expect='Rally Asphalt' }
  @{ name='asphalt coilover + race tire (custom mount)'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_rally_coilover_F_asphalt'); expect='Rally Asphalt' }

  # Gravel rally
  @{ name='Covet rally_gravel'; tire='tire_F_165_70_14_rally'; tread=0.70
    parts=@('covet_coilover_F_rally','tire_F_165_70_14_rally'); expect='Rally' }
  @{ name='Bolide rally_gravel'; tire='tire_R_245_45_16_rally'; tread=0.70
    parts=@('bolide_coilover_F_rally'); expect='Rally' }

  # Negatives: cosmetic / empty slots must not remap race → Rally Asphalt
  @{ name='Race + skin_rally only'; tire='tire_F_265_40_17_race'; tread=0.0
    parts=@('bolide_skin_rally','tire_F_265_40_17_race'); expect='Slick' }
  @{ name='Race + skidplate only'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_skidplate_rally_F','tire_F_235_40_18_race'); expect='Slick' }
  @{ name='Race + empty rallylights slot string'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('','vivace_rally_steering','tire_F_235_40_18_race'); expect='Slick' }
  @{ name='Race + strut_bar only'; tire='tire_F_195_50_15_race'; tread=0.0
    parts=@('covet_strut_bar_F','tire_F_195_50_15_race'); expect='Slick' }
)

Out '=== Tire descriptor classification (Rally Asphalt / Slick / Rally) ==='
Out ('Mirrored from luukstyrethermalsandwear.lua @ {0:yyyy-MM-dd}' -f (Get-Date))
Out ''

$fail = 0
foreach ($c in $cases) {
  $got = Get-Descriptor $c.tire ([double]$c.tread) $c.parts
  $ok = ($got -eq $c.expect)
  if (-not $ok) { $fail++ }
  $mark = if ($ok) { 'PASS' } else { 'FAIL' }
  Out ("{0}: {1}  tire={2} tread={3} -> {4} (expect {5})" -f $mark, $c.name, $c.tire, $c.tread, $got, $c.expect)
  if (-not $ok) {
    Out ("       parts: {0}" -f ($c.parts -join ', '))
  }
}

Out ''
if ($fail -eq 0) {
  Out ("OVERALL: PASS ({0}/{0})" -f $cases.Count)
} else {
  Out ("OVERALL: FAIL ($fail/$($cases.Count) failed)")
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host "Wrote $out"
if ($fail -gt 0) { exit 1 }
