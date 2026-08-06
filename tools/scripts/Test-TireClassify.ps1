# Unit check: purpose + compound descriptor + classifyReason routing
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

# Returns hashtable: descriptor, purpose, classifyReason
function Get-Classify([string]$tireName, [double]$treadCoef, [string[]]$parts) {
  $nameLower = $tireName.ToLowerInvariant()
  $isAsphaltName = ($nameLower -like '*tarmac*') -or (($nameLower -like '*asphalt*') -and ($nameLower -notlike '*supersport*'))
  $isAsphaltRallyRaceSku = ($nameLower -like '*race*') -and (
    ($nameLower -like '*180_580*') -or ($nameLower -like '*200_600*') -or ($nameLower -like '*210_600*')
  )
  $isGravelRallyName = ($nameLower -like '*rally*') -and -not $isAsphaltName
  $isSlickName = ($nameLower -like '*slick*')
  $isRaceName = ($nameLower -like '*race*')
  $isRaceOrSlickName = $isSlickName -or $isRaceName
  $isRaceLikeName = $isRaceOrSlickName -or ($treadCoef -le 0.12)

  $isDamperTarmacHint = $false
  if (-not $isAsphaltName -and -not $isAsphaltRallyRaceSku) {
    $hasDamper = Test-HasPlainRallyDamper $parts
    $isDamperTarmacHint = $isRaceName -and -not $isSlickName -and -not $isGravelRallyName `
      -and ($nameLower -notlike '*gravel*') -and $hasDamper
  }
  $isRallyAsphaltMount = $isAsphaltName -or $isAsphaltRallyRaceSku -or $isDamperTarmacHint
  $tarmacReason = if ($isAsphaltName) { 'asphalt_name' }
    elseif ($isAsphaltRallyRaceSku) { 'race_sku' }
    elseif ($isDamperTarmacHint) { 'rally_damper' }
    else { $null }

  $purpose = 'street'
  $classifyReason = 'street_spectrum'
  $descriptor = 'Standard'

  if ($nameLower -match 'crawler|beadlock') {
    $purpose = 'utility'; $classifyReason = 'standalone_crawler'; $descriptor = 'Crawler'
  } elseif ($nameLower -match 'paddle|sand') {
    $purpose = 'utility'; $classifyReason = 'standalone_paddle'; $descriptor = 'Paddle'
  } elseif ($isRallyAsphaltMount) {
    $purpose = 'tarmac_rally'; $classifyReason = $tarmacReason; $descriptor = 'Rally'
  } elseif ($isGravelRallyName) {
    $purpose = 'gravel'; $classifyReason = 'gravel_name'; $descriptor = 'Rally'
  } elseif ($nameLower -match 'winter|snow') {
    $purpose = 'winter'; $classifyReason = 'standalone_winter'; $descriptor = 'Winter'
  } elseif ($nameLower -match 'drag') {
    $purpose = 'drag'; $classifyReason = 'standalone_drag'; $descriptor = 'Drag'
  } elseif ($nameLower -match 'drift') {
    $purpose = 'drift'; $classifyReason = 'standalone_drift'; $descriptor = 'Drift'
  } elseif ($nameLower -match 'rain|wet|inter') {
    $purpose = 'wet'; $classifyReason = 'standalone_rain'; $descriptor = 'Wet'
  } elseif ($isRaceLikeName -and ($nameLower -notlike '*gravel*')) {
    $purpose = 'circuit'; $classifyReason = 'slick_spectrum'; $descriptor = 'Slick'
  } elseif ($treadCoef -le 0.20) {
    $purpose = 'circuit'; $classifyReason = 'slick_spectrum'; $descriptor = 'Slick'
  } elseif ($treadCoef -le 0.42) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Sport Plus'
  } elseif ($treadCoef -le 0.58) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Sport'
  } elseif ($treadCoef -le 0.72) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Standard'
  } elseif ($treadCoef -le 0.85) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'All-Terrain'
  } elseif ($treadCoef -le 0.95) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Mud-Terrain'
  } else {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Crawler'
  }

  # Street-spectrum MT + gravel name → gravel purpose (mirrors Lua gravel_mt_name)
  if ($classifyReason -eq 'street_spectrum' -and ($nameLower -like '*gravel*') -and ($treadCoef -gt 0.78)) {
    $purpose = 'gravel'; $classifyReason = 'gravel_mt_name'
  }

  # Low-tread street path still shows Slick but purpose remaps to circuit in Lua;
  # already covered by treadCoef <= 0.20 above.

  return @{
    descriptor = $descriptor
    purpose = $purpose
    classifyReason = $classifyReason
  }
}

$cases = @(
  # --- Pure race (must stay circuit / Slick) ---
  @{ name='Covet race'; tire='tire_F_195_50_15_race'; tread=0.0
    parts=@('covet_coilover_F_race','covet_rallylights','tire_F_195_50_15_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Bolide race'; tire='tire_F_265_40_17_race'; tread=0.0
    parts=@('bolide_race_coilover_F','bolide_rallylights','tire_F_265_40_17_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Bolide topspeed (same tires as asphalt, race dampers)'; tire='tire_F_245_45_16_race'; tread=0.0
    parts=@('bolide_coilover_F_race','bolide_coilover_R_race','tire_F_245_45_16_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='ETK GT4 race_DCT'; tire='tire_F_295_30_18_race'; tread=0.0
    parts=@('etkc_strut_F_wide_race','etkc_shock_R_race','etkc_spring_R_race','tire_F_295_30_18_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Scintilla race'; tire='tire_F_295_35_19_race'; tread=0.0
    parts=@('scintilla_coilover_F_race','tire_F_295_35_19_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  # REAL bug: Ardente race keeps vivace_suspension_*_rally + track coilovers
  @{ name='Vivace Ardente race (suspension_rally + track coilover)'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_suspension_F_rally','vivace_suspension_R_rally','vivace_rally_coilover_F_track','vivace_rally_coilover_R_track','vivace_rally_steering','vivace_rally_swaybar_F','tire_F_235_40_18_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Vivace race_SQ'; tire='tire_F_245_35_19_race'; tread=0.0
    parts=@('vivace_strut_F_wide_race','vivace_shock_R_wide_race','vivace_spring_R_wide_race','tire_F_245_35_19_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + suspension_rally only (no damper)'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_suspension_F_rally','vivace_suspension_R_rally')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + spring/shock_rally must not remap'; tire='tire_F_265_40_17_race'; tread=0.0
    parts=@('bolide_spring_F_rally','bolide_shock_R_rally','tire_F_265_40_17_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Low tread alone + suspension_rally stays circuit'; tire='tire_F_225_45_17_sport'; tread=0.05
    parts=@('vivace_suspension_F_rally')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  # Explicit slick name stays circuit even with plain rally damper
  @{ name='Slick name + rally coilover stays circuit'; tire='tire_F_265_40_17_slick'; tread=0.0
    parts=@('bolide_coilover_F_rally','bolide_coilover_R_rally')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }

  # --- Tarmac rally (compound Rally, purpose tarmac_rally) ---
  @{ name='Covet rally_asphalt (race tire + rally coilover)'; tire='tire_F_180_580_15_altb_race'; tread=0.0
    parts=@('covet_coilover_F_rally','covet_rallylights','tire_F_180_580_15_altb_race')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  @{ name='Covet asphalt SKU alone (no hardware)'; tire='tire_F_180_580_15_altb_race'; tread=0.0
    parts=@()
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  @{ name='Bolide rally_asphalt'; tire='tire_F_245_45_16_race'; tread=0.0
    parts=@('bolide_coilover_F_rally','bolide_coilover_R_rally','bolide_rallylights','tire_F_245_45_16_race')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='rally_damper' }
  @{ name='BX rally_asp'; tire='tire_F_200_600_16_race'; tread=0.0
    parts=@('bx_strut_F_rally','bx_coilover_R_rally','tire_F_200_600_16_race')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  @{ name='BX asphalt SKU alone'; tire='tire_R_200_600_16_race'; tread=0.0
    parts=@()
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  @{ name='210_600 race SKU alone'; tire='tire_F_210_600_16_race'; tread=0.0
    parts=@()
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  # 210_650 is a real Race slick SKU, not asphalt-rally
  @{ name='210_650 race slick SKU'; tire='tire_F_210_650_19_race'; tread=0.0
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }

  # Explicit asphalt / tarmac tire names → tarmac_rally (hardware optional)
  @{ name='Scintilla rally (*_asphalt)'; tire='tire_F_245_40_18_asphalt'; tread=0.40
    parts=@('scintilla_coilover_F_rally')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='asphalt_name' }
  @{ name='Vivace Ardente asphalt'; tire='tire_F_235_40_18_asphalt'; tread=0.40
    parts=@('vivace_rally_coilover_F_asphalt','vivace_suspension_F_rally','tire_F_235_40_18_asphalt')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='asphalt_name' }
  @{ name='tarmac name alone'; tire='tire_F_205_55_16_tarmac'; tread=0.35
    parts=@()
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='asphalt_name' }
  @{ name='asphalt coilover + race tire (custom mount)'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_rally_coilover_F_asphalt')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='rally_damper' }

  # Gravel rally
  @{ name='Covet rally_gravel'; tire='tire_F_165_70_14_rally'; tread=0.70
    parts=@('covet_coilover_F_rally','tire_F_165_70_14_rally')
    expectDesc='Rally'; expectPurpose='gravel'; expectReason='gravel_name' }
  @{ name='Bolide rally_gravel'; tire='tire_R_245_45_16_rally'; tread=0.70
    parts=@('bolide_coilover_F_rally')
    expectDesc='Rally'; expectPurpose='gravel'; expectReason='gravel_name' }

  # Street spectrum
  @{ name='Street sport'; tire='tire_F_225_45_17_sport'; tread=0.50
    parts=@()
    expectDesc='Sport'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='Street sport_plus'; tire='tire_F_245_40_18_sport'; tread=0.35
    parts=@()
    expectDesc='Sport Plus'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='Street sport_tour anchor'; tire='tire_F_235_40_18_sport'; tread=0.40
    parts=@()
    expectDesc='Sport Plus'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='Street standard mid'; tire='tire_F_205_55_16_standard'; tread=0.60
    parts=@()
    expectDesc='Standard'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='Street standard'; tire='tire_F_205_55_16_standard'; tread=0.65
    parts=@()
    expectDesc='Standard'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='Street AT/MT mid'; tire='tire_F_265_70_16_offroad'; tread=0.85
    parts=@()
    expectDesc='All-Terrain'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='MT gravel name purpose'; tire='tire_F_265_70_16_gravel'; tread=0.90
    parts=@()
    expectDesc='Mud-Terrain'; expectPurpose='gravel'; expectReason='gravel_mt_name' }

  # Negatives: cosmetic / empty slots must not remap race → tarmac_rally
  @{ name='Race + skin_rally only'; tire='tire_F_265_40_17_race'; tread=0.0
    parts=@('bolide_skin_rally','tire_F_265_40_17_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + skidplate only'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_skidplate_rally_F','tire_F_235_40_18_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + empty rallylights slot string'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('','vivace_rally_steering','tire_F_235_40_18_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + strut_bar only'; tire='tire_F_195_50_15_race'; tread=0.0
    parts=@('covet_strut_bar_F','tire_F_195_50_15_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
)

Out '=== Tire purpose / descriptor / classifyReason ==='
Out ('Mirrored from luukstyrethermalsandwear.lua @ {0:yyyy-MM-dd}' -f (Get-Date))
Out ''

$fail = 0
foreach ($c in $cases) {
  $got = Get-Classify $c.tire ([double]$c.tread) $c.parts
  $ok = ($got.descriptor -eq $c.expectDesc) -and ($got.purpose -eq $c.expectPurpose) -and ($got.classifyReason -eq $c.expectReason)
  if (-not $ok) { $fail++ }
  $mark = if ($ok) { 'PASS' } else { 'FAIL' }
  Out ("{0}: {1}  tire={2} tread={3}" -f $mark, $c.name, $c.tire, $c.tread)
  Out ("       got  desc={0} purpose={1} reason={2}" -f $got.descriptor, $got.purpose, $got.classifyReason)
  Out ("       want desc={0} purpose={1} reason={2}" -f $c.expectDesc, $c.expectPurpose, $c.expectReason)
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
