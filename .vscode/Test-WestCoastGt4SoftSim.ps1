# Soft-sim: Belasco GT4 race path — SLICK spectrum, FRONT vs REAR (RWD)
# Source: SLICK_SPECTRUM_POINTS + THERMAL_TOPOLOGY drivePropSlick* scales
# sport / sport_plus PROFILE_POINTS untouched.
# Live ref: skin better @0.55; second carcass layer still overheating on driven rears.
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'wc-gt4-softsim-10laps.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

# Live medium_slick (generic race/slick continuum anchor)
$m = @{
  name = 'medium_slick'; softness = 0.65; latCapBase = 1.16
  c = @(1.38, 0.32, -0.12); gm = 1.02; lat = 0.72; dryGrip = 0.98; rollingRes = 1.02
  tOpt = 84.0; plat = 14.0; wc = 46.0; wh = 46.0; floor = 0.20; ad = 0.52; casing = 0.25
  slipHeat = 10.4; workHeat = 6.1; wearRate = 0.0008; hotWear = 4.52; blisterRatio = 1.50
  treadInertia = 0.399; carcassInertia = 0.646; react = 1.42; skinCore = 0.104
  airCool = 0.020; staticCool = 0.076; coreCool = 0.028
}

# Corner slip/work proxy (shared F/R). Drive heat is REAR-ONLY (RWD).
# Mild corner so fronts sit ~85-100 (live: fronts fine).
$SOFTSIM_CORNER_HEAT = 0.62
# Calibrated so BEFORE rear skin lap1 ≈ prior @0.55 (~96); carcass was under-modeled
$SOFTSIM_DRIVE_HEAT_FULL = 18.5
# Carcass excess proxy (hyst + flex + prop-linked RR) — separate from skin package
$SOFTSIM_CARCASS_DRIVE_FULL = 9.5
# Live THERMAL_TOPOLOGY (surgical; sport_plus keeps 1.0 / 1.0)
$DRIVE_PROP_SLICK_SCALE = 0.50
$DRIVE_PROP_SLICK_CARCASS_SCALE = 0.30
# Prior unified live (skin+carcass same gate) for BEFORE comparison
$PRIOR_UNIFIED_SCALE = 0.55
# Soft-sim RR trim (live cruise soft-cap already; single-zone overstates soak)
$SOFTSIM_RR_MULT = 0.55

function ThermalGrip([hashtable]$prof, [double]$temp) {
  $soft = [double]$prof.softness
  $plat = [double]$prof.plat * (0.8 + 0.4 * $soft)
  $wC = [double]$prof.wc * (0.8 + 0.4 * $soft) * (1.0 + ([double]$prof.casing - 0.5) * 0.15)
  $wH = [double]$prof.wh * (0.8 + 0.4 * $soft)
  $diff = [math]::Abs($temp - [double]$prof.tOpt)
  $excess = [math]::Max(0.0, $diff - $plat)
  if ($temp -lt [double]$prof.tOpt) { $w = $wC; $p = 1.35 } else { $w = $wH; $p = 2.0 }
  $decay = [math]::Exp(-[math]::Pow($excess / [math]::Max(1.0, $w), $p))
  $tm = [double]$prof.floor + (1.0 - [double]$prof.floor) * $decay
  if ($tm -lt 1.0) { $tm = [math]::Max(0.42, [math]::Pow($tm, 1.12)) }
  $shaped = $tm * (0.62 + 0.38 * $tm)
  return ($tm + ($shaped - $tm) * ([double]$prof.ad * 0.55))
}

# axle: 'F' (no drive heat) or 'R' (excess-prop drive heat * scales)
function SimulateAxle([hashtable]$prof, [string]$axle, [double]$slickSkinScale, [double]$slickCarcassScale, [int]$laps) {
  $dt = 0.02; $env = 26.0; $trackTemp = 36.0; $surfMu = 1.05; $tyreW = 0.95; $vehMass = 1435.0
  $surfaceCap = 1.15
  $lapTime = 95.0; $dur = $lapTime * $laps
  $isRear = ($axle -eq 'R')
  # Slight rear bias load on RWD GT (drive + static)
  $loadCorner = if ($isRear) { 6000.0 } else { 5400.0 }
  $loadStraight = if ($isRear) { 3800.0 } else { 3400.0 }

  $skin = Lerp $env ([double]$prof.tOpt) 0.50
  $core = $skin - 3.0
  $cond = 100.0; $blister = 0.0; $marbles = 0.0; $hotStint = 0.0
  $peakSkin = $skin
  $peakCore = $core
  $startSkin = $skin
  $lapPeakSkin = $skin
  $lapPeakCore = $core
  $lapSumSkin = 0.0
  $lapSumCore = 0.0
  $lapSamples = 0
  $base = [double]$prof.c[0] + [double]$prof.c[1] + [double]$prof.c[2]
  $adj = [double]$prof.react / [math]::Max(0.05, [double]$prof.treadInertia)
  $coreRate = 0.08 / [math]::Max(0.05, [double]$prof.carcassInertia)
  $blOn = [double]$prof.tOpt * [double]$prof.blisterRatio
  $scaleW = [double]$prof.wearRate * 2000.0

  $n = [int]($dur / $dt)
  $t = 0.0
  $nextLap = 1
  $lapRows = @()

  for ($i = 0; $i -lt $n; $i++) {
    $phase = $t % $lapTime
    $inCorner = ($phase -gt 8.0 -and $phase -lt 70.0)
    # RWD throttle: exits + most of straight (excess prop). Corners still get some drive.
    $driveGate = 0.0
    if ($isRear) {
      if (-not $inCorner) { $driveGate = 1.0 }
      elseif ($phase -gt 55.0) { $driveGate = 0.75 }
      elseif ($phase -gt 20.0) { $driveGate = 0.35 }
    }
    $slip = if ($inCorner) { 0.20 } else { 0.06 }
    $gMag = if ($inCorner) { 1.15 } else { 0.25 }
    $airspeed = if ($inCorner) { 38.0 } else { 48.0 }
    $loadRaw = if ($inCorner) { $loadCorner } else { $loadStraight }

    $loadKg = $loadRaw / 9.81
    $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)
    $slipEff = $slip * (1.0 + $gMag * 0.15)
    $seh = $slipEff / (1.0 + $slipEff * 0.12)
    $wt = 0.46
    $loadCoeff = $wt * $loadKg
    $gWork = [math]::Max(0.0, $gMag - 0.22)
    $rel = $gWork * $loadCoeff / 1000.0

    $raw = ($seh * 0.05) * 3.0 * $wt * ([math]::Max($surfMu - 0.5, 0.1) * 2.0)
    $peakWork = if ($inCorner) { 1.18 } else { 0.90 }
    $heatScale = if ($inCorner) { $SOFTSIM_CORNER_HEAT } else { 1.0 }
    $raw = $raw + ((0.0078 * $seh * $seh * $loadCoeff * [double]$prof.slipHeat) +
      (0.145 * $rel * [double]$prof.workHeat * $peakWork / (1.0 + $seh * $seh))) * $surfMu / $tyreW * $heatScale

    $cruiseRR = 1.0
    if (($slipEff -lt 0.08) -and ($gMag -lt 0.35)) { $cruiseRR = 0.48 }
    elseif (($slipEff -lt 0.15) -and ($gMag -lt 0.55)) { $cruiseRR = 0.72 }
    $angHeat = $airspeed / (1.0 + $airspeed / 90.0)
    $rrSkin = 0.012 * $loadKg * $angHeat * 0.0000028 * [double]$prof.rollingRes * $cruiseRR * 8000.0 * $SOFTSIM_RR_MULT
    if ($inCorner) { $rrSkin = $rrSkin * 1.35 }
    $raw = $raw + $rrSkin

    # Excess-prop SKIN drive heat (REAR only). slickSkinScale → drivePropSlickScale
    $effGateSkin = 0.0
    $effGateCarcass = 0.0
    if ($driveGate -gt 0) {
      $effGateSkin = $driveGate * $slickSkinScale
      $effGateCarcass = $driveGate * $slickCarcassScale
      $slipWorkBoost = 1.0 + (1.28 - 1.0) * $effGateSkin
      $driveSkin = (0.066 * $SOFTSIM_DRIVE_HEAT_FULL * [double]$prof.workHeat * 0.28) * $effGateSkin
      $raw = ($raw * $slipWorkBoost) + $driveSkin
    }

    $tempDist = $skin / [math]::Max(1.0, [double]$prof.tOpt)
    $thermFric = 1.0
    if ($tempDist -gt 1.1) { $thermFric = [math]::Max(0.30, 1.0 - ($tempDist - 1.1) * 0.6) }
    $gain = $raw * $thermFric

    $effAir = $airspeed / (1.0 + $airspeed / 220.0)
    $retain = 1.0 / (1.0 + [math]::Min(0.18, [math]::Max(0.0, $gMag - 0.20) * 0.22))
    $velCool = [math]::Pow($effAir, 0.8) * [double]$prof.airCool * 0.155 * $retain
    $conv = ($skin - $env) * ([double]$prof.staticCool * 0.04 + $velCool)
    $trackCond = ($skin - $trackTemp) * 0.012 * $wt
    $toCore = ($core - $skin) * [double]$prof.skinCore
    $skinRate = ($gain - $conv - $trackCond + $toCore) * $adj / $tyreW
    $skin = Clamp ($skin + $dt * $skinRate) -20 200

    $fromSkin = ($skin - $core) * [double]$prof.skinCore
    $coreCoolAmt = ($core - $env) * [double]$prof.coreCool * 0.15 * (1.0 + $airspeed * 0.01)
    # Carcass-bound excess: torqueHysteresis + flexExcess + prop-linked RR damp target
    $driveCarcass = 0.0
    if ($effGateCarcass -gt 0) {
      $driveCarcass = $SOFTSIM_CARCASS_DRIVE_FULL * [double]$prof.rollingRes * 0.55 * $effGateCarcass
      # prop-linked RR damp mirrors live slickPropRrDamp on base carcass soak under drive
      $rrDamp = 1.0 + ($slickCarcassScale - 1.0) * $driveGate
      $driveCarcass = $driveCarcass * (0.70 + 0.30 * $rrDamp)
    }
    $core = Clamp ($core + $dt * ($fromSkin + $driveCarcass - $coreCoolAmt) * $coreRate * 8.0) -20 180
    if ($skin -gt $peakSkin) { $peakSkin = $skin }
    if ($core -gt $peakCore) { $peakCore = $core }
    if ($skin -gt $lapPeakSkin) { $lapPeakSkin = $skin }
    if ($core -gt $lapPeakCore) { $lapPeakCore = $core }
    $lapSumSkin += $skin
    $lapSumCore += $core
    $lapSamples++

    $tempWear = 1.0
    if ($tempDist -gt 1.0) { $tempWear = Lerp 1.0 ([double]$prof.hotWear) (Clamp ($tempDist - 1.0) 0 1) }
    $sliding = 14.0 * (($loadRaw / ($vehMass * 9.81)) * $slipEff * $tempWear / $tyreW)
    $cond = Clamp ($cond - $sliding * [double]$prof.wearRate * $dt) 0 100

    if (($skin -gt $blOn) -and ($slipEff -gt 0.32)) {
      $oh = [math]::Min(2.0, ($skin - $blOn) / [math]::Max(12.0, [double]$prof.tOpt * 0.18))
      $sf = [math]::Min(2.2, $slipEff / 0.32)
      $blister = Clamp ($blister + 0.00028 * $scaleW * $oh * $sf * $dt) 0 1
    }
    if (($skin -gt [double]$prof.tOpt * 0.95) -and ($slipEff -gt 0.20)) {
      $marbles = Clamp ($marbles + 0.0004 * $slipEff * $scaleW * $dt) 0 1
    }
    if ($skin -ge [double]$prof.tOpt * 0.90) { $hotStint += $dt }

    $t += $dt
    if ($t -ge ($nextLap * $lapTime - 1e-6) -and $nextLap -le $laps) {
      $avgSkin = if ($lapSamples -gt 0) { $lapSumSkin / $lapSamples } else { $skin }
      $avgCore = if ($lapSamples -gt 0) { $lapSumCore / $lapSamples } else { $core }
      $therm = ThermalGrip $prof $skin
      $grip = $base * $therm * [double]$prof.gm * [double]$prof.dryGrip * (Lerp 0.75 1.0 ($cond * 0.01))
      $bPen = 0.0
      if ($blister -gt 0.08) { $bPen = ($blister - 0.08) * 0.32 }
      $grip = $grip * (1.0 - $bPen) * (1.0 - $marbles * 0.18) * (1.0 - [math]::Min(0.12, $hotStint / 10000.0))
      $latGrip = $grip * [double]$prof.lat
      $beamRef = [math]::Max(0.18, [math]::Min(1.20, $surfMu))
      $latGrip = [math]::Min($latGrip, $surfaceCap / $beamRef)
      $coldFrac = Clamp (([double]$prof.tOpt - $skin) / [math]::Max(20.0, [double]$prof.tOpt * 0.45)) 0 1
      $hotFrac = Clamp (($skin - [double]$prof.tOpt) / [math]::Max(20.0, [double]$prof.tOpt * 0.40)) 0 1
      $latCap = [double]$prof.latCapBase * (1.0 - 0.18 * $coldFrac - 0.12 * $hotFrac)
      if ($latGrip -gt $latCap) { $latGrip = $latCap }
      $lapRows += [pscustomobject]@{
        lap = $nextLap
        avg = [math]::Round($avgSkin, 1)
        skin = [math]::Round($skin, 1)
        peak = [math]::Round($lapPeakSkin, 1)
        coreAvg = [math]::Round($avgCore, 1)
        core = [math]::Round($core, 1)
        corePeak = [math]::Round($lapPeakCore, 1)
        cond = [math]::Round($cond, 1)
        blister = [math]::Round($blister * 100, 1)
        grip = [math]::Round($latGrip, 3)
      }
      $lapPeakSkin = $skin
      $lapPeakCore = $core
      $lapSumSkin = 0.0
      $lapSumCore = 0.0
      $lapSamples = 0
      $nextLap++
    }
  }

  return @{
    axle = $axle
    skinScale = $slickSkinScale
    carcassScale = $slickCarcassScale
    startSkin = $startSkin
    peakSkin = [math]::Round($peakSkin, 1)
    peakCore = [math]::Round($peakCore, 1)
    rows = $lapRows
  }
}

function EmitAxle([System.Text.StringBuilder]$sb, $r, [string]$label) {
  [void]$sb.AppendLine(("--- {0} (skinScale={1} carcassScale={2}) ---" -f $label, $r.skinScale, $r.carcassScale))
  [void]$sb.AppendLine(('{0,4} {1,7} {2,7} {3,7} {4,8} {5,8} {6,8} {7,6} {8,6}' -f `
    'lap', 'skAvg', 'skEnd', 'skPeak', 'carAvg', 'carEnd', 'carPeak', 'cond%', 'grip'))
  foreach ($row in $r.rows) {
    [void]$sb.AppendLine(('{0,4} {1,7:n1} {2,7:n1} {3,7:n1} {4,8:n1} {5,8:n1} {6,8:n1} {7,6:n1} {8,6:n3}' -f `
      $row.lap, $row.avg, $row.skin, $row.peak, $row.coreAvg, $row.core, $row.corePeak, $row.cond, $row.grip))
  }
  [void]$sb.AppendLine(('lap1 skin avg={0:n1}C peak={1:n1}C | carcass avg={2:n1}C peak={3:n1}C' -f `
    $r.rows[0].avg, $r.rows[0].peak, $r.rows[0].coreAvg, $r.rows[0].corePeak))
  [void]$sb.AppendLine('')
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('SOFT-SIM: Belasco GT4 / medium_slick — FRONT vs REAR (RWD drive heat)')
[void]$sb.AppendLine(("lap~95s, cornerHeat={0}, driveHeatFull={1}, carcassDriveFull={2}" -f `
  $SOFTSIM_CORNER_HEAT, $SOFTSIM_DRIVE_HEAT_FULL, $SOFTSIM_CARCASS_DRIVE_FULL))
[void]$sb.AppendLine(("live drivePropSlickScale={0} drivePropSlickCarcassScale={1} (prior unified={2})" -f `
  $DRIVE_PROP_SLICK_SCALE, $DRIVE_PROP_SLICK_CARCASS_SCALE, $PRIOR_UNIFIED_SCALE))
[void]$sb.AppendLine('Fronts: corner+RR only. Rears: + Pass3/4 skin excess + carcass hyst/flex/RR.')
[void]$sb.AppendLine('sport/sport_plus PROFILE_POINTS not used. Burnout slipVelBoost unchanged.')
[void]$sb.AppendLine('Live ref: skin OK @0.55 (want slight cooler); carcass still overheating on rears.')
[void]$sb.AppendLine('')

$laps = 3  # enough for lap1 verdict + settle

# BEFORE: prior unified live 0.55 (skin+carcass same gate)
$beforeF = SimulateAxle $m 'F' $PRIOR_UNIFIED_SCALE $PRIOR_UNIFIED_SCALE $laps
$beforeR = SimulateAxle $m 'R' $PRIOR_UNIFIED_SCALE $PRIOR_UNIFIED_SCALE $laps
# AFTER: split skin 0.50 / carcass 0.35
$afterF = SimulateAxle $m 'F' $DRIVE_PROP_SLICK_SCALE $DRIVE_PROP_SLICK_CARCASS_SCALE $laps
$afterR = SimulateAxle $m 'R' $DRIVE_PROP_SLICK_SCALE $DRIVE_PROP_SLICK_CARCASS_SCALE $laps

[void]$sb.AppendLine(('======== BEFORE (unified slickScale={0}) ========' -f $PRIOR_UNIFIED_SCALE))
EmitAxle $sb $beforeF 'FRONT'
EmitAxle $sb $beforeR 'REAR'

[void]$sb.AppendLine(('======== AFTER (skin={0} carcass={1}) ========' -f `
  $DRIVE_PROP_SLICK_SCALE, $DRIVE_PROP_SLICK_CARCASS_SCALE))
EmitAxle $sb $afterF 'FRONT'
EmitAxle $sb $afterR 'REAR'

$bF1 = $beforeF.rows[0]; $bR1 = $beforeR.rows[0]
$aF1 = $afterF.rows[0]; $aR1 = $afterR.rows[0]

[void]$sb.AppendLine('======== SUMMARY F vs R — skin + carcass ========')
[void]$sb.AppendLine(('BEFORE  F skin={0:n1}/{1:n1} car={2:n1}/{3:n1} | R skin={4:n1}/{5:n1} car={6:n1}/{7:n1}' -f `
  $bF1.avg, $bF1.peak, $bF1.coreAvg, $bF1.corePeak,
  $bR1.avg, $bR1.peak, $bR1.coreAvg, $bR1.corePeak))
[void]$sb.AppendLine(('AFTER   F skin={0:n1}/{1:n1} car={2:n1}/{3:n1} | R skin={4:n1}/{5:n1} car={6:n1}/{7:n1}' -f `
  $aF1.avg, $aF1.peak, $aF1.coreAvg, $aF1.corePeak,
  $aR1.avg, $aR1.peak, $aR1.coreAvg, $aR1.corePeak))
[void]$sb.AppendLine(('DELTA R skin avg {0:n1}C | R carcass avg {1:n1}C (negative = cooler)' -f `
  ($aR1.avg - $bR1.avg), ($aR1.coreAvg - $bR1.coreAvg)))
[void]$sb.AppendLine(('AFTER R-F delta skin {0:n1}C | carcass {1:n1}C' -f `
  ($aR1.avg - $aF1.avg), ($aR1.coreAvg - $aF1.coreAvg)))
[void]$sb.AppendLine('')

$fail = 0; $pass = 0
function Expect([bool]$ok, [string]$msg) {
  if ($ok) { $script:pass++; [void]$sb.AppendLine("PASS  $msg") }
  else { $script:fail++; [void]$sb.AppendLine("FAIL  $msg") }
}

# Fronts unchanged / in range
Expect ([math]::Abs($aF1.avg - $bF1.avg) -lt 1.0) 'front skin unchanged by rear drive scales'
Expect ([math]::Abs($aF1.coreAvg - $bF1.coreAvg) -lt 1.0) 'front carcass unchanged by rear drive scales'
Expect ($aF1.avg -ge 70 -and $aF1.avg -lt 108) ("AFTER front skin lap1 in band (got {0})" -f $aF1.avg)

# Skin: slight cooler than prior 0.55, still in 90-105 rear band
Expect ($aR1.avg -le $bR1.avg + 0.5) 'AFTER rear skin <= BEFORE (or tiny float)'
Expect ($aR1.avg -ge 88) ("AFTER rear skin avg >=88C (got {0})" -f $aR1.avg)
Expect ($aR1.avg -le 105) ("AFTER rear skin avg <=105C (got {0})" -f $aR1.avg)

# Carcass: stronger cut — cooler than prior, not runaway vs front
Expect ($aR1.coreAvg -lt ($bR1.coreAvg - 2.0)) ("AFTER rear carcass cooler than BEFORE by >=2C (got d={0:n1})" -f ($aR1.coreAvg - $bR1.coreAvg))
Expect (($aR1.coreAvg - $aF1.coreAvg) -lt ($bR1.coreAvg - $bF1.coreAvg)) 'AFTER R-F carcass gap narrower than BEFORE'
Expect (($aR1.coreAvg - $aF1.coreAvg) -lt 25.0) ("AFTER R-F carcass gap <25C (got {0:n1})" -f ($aR1.coreAvg - $aF1.coreAvg))
Expect ($aR1.corePeak -lt 140) ("AFTER rear carcass peak not runaway <140C (got {0})" -f $aR1.corePeak)
Expect ($aR1.grip -gt 0.90) ("AFTER rear grip usable (got {0})" -f $aR1.grip)

[void]$sb.AppendLine('')
[void]$sb.AppendLine('CAUSE: unified drivePropSlickScale damped skin+carcass together; carcass hyst/flex/RR')
[void]$sb.AppendLine('       still overcooked driven rears after skin landed in band.')
[void]$sb.AppendLine(('CHANGE: drivePropSlickScale {0}->{1} (skin); new drivePropSlickCarcassScale={2}' -f `
  $PRIOR_UNIFIED_SCALE, $DRIVE_PROP_SLICK_SCALE, $DRIVE_PROP_SLICK_CARCASS_SCALE))
[void]$sb.AppendLine('       (hyst excess, flex excess, prop-linked RR/flex damp). sport/sport_plus untouched.')
if ($aR1.avg -ge 90 -and $aR1.avg -le 105 -and ($aR1.coreAvg - $aF1.coreAvg) -lt 20) {
  [void]$sb.AppendLine('RECOMMEND: keep split — rear skin in 90-105, carcass gap controlled.')
} elseif ($aR1.coreAvg -gt ($aF1.coreAvg + 22)) {
  [void]$sb.AppendLine('RECOMMEND: carcass still hot — lower drivePropSlickCarcassScale toward 0.28.')
} elseif ($aR1.avg -lt 90) {
  [void]$sb.AppendLine('RECOMMEND: skin slightly cool — nudge drivePropSlickScale toward 0.52.')
} else {
  [void]$sb.AppendLine('RECOMMEND: review in-game; soft-sim is directional for carcass package.')
}
[void]$sb.AppendLine("RESULT: $pass passed, $fail failed")

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Output $sb.ToString()
if ($fail -gt 0) { exit 1 }
exit 0
