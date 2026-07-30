# Aero edge-case soft-sim v4 - proven inline pattern
# Per-wheel aero loads 0..5kN (20kN total), 4 scenarios, 3 tire types.
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'aero-edge-softsim.txt'

# ── constants ────────────────────────────────────────────────────────────────
[double]$ENV_C=26.0; [double]$TRACK_C=40.0; [double]$TYRE_W=0.95
[double]$WIDTH_M=0.265; [double]$RADIUS=0.33; [double]$SURF_MU=1.12; [double]$HMS=1.05; [double]$WT=0.46
[double]$RUBBER_E=0.94; [double]$STEFAN=5.67e-8
[double]$ASPH=1.35; [double]$THK=0.002; [double]$PRES_PA=213933.0
[double]$PFMIN=0.09; [double]$PFMAX=0.22; [double]$PFREF=0.140; [double]$FBCM=1.32
[double]$AERO_SCALE=0.55; [double]$AERO_MAXFRAC=0.48; [double]$AERO_V0=15.0; [double]$AERO_V1=52.0
[double]$DPC=250.0; [double]$DPEF=520.0; [double]$DHYB=5e-8; [double]$DHYE=6e-7
[double]$DT=0.01

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('AERO EDGE-CASE SOFT-SIM v4')
[void]$sb.AppendLine('Per-wheel aero: 0/500/1000/2000/3500/5000 N  (max 20kN/4 wheels)')
[void]$sb.AppendLine('knobs: aeroHeatScale=0.55  maxFrac=0.48  speedStart=15m/s  speedFull=52m/s  patchFracMax=0.22  patchFracRef=0.140')
[void]$sb.AppendLine('cold start sim; eqTemp = skin when dT/dt < 0.08 C/s')
[void]$sb.AppendLine('')

# ── scenario definitions ─────────────────────────────────────────────────────
$scenTags  = @('Hairpin_50kmh',     'Corner_100kmh',      'FastCorner_180kmh',                  'Straight_270kmh')
$scenDescs = @('50km/h hairpin hi-slip no-aero', '100km/h partial aeroRamp', '180km/h fast corner aeroRamp~0.85', '270km/h straight full aeroRamp')
$scenVms   = @(13.9,  27.8,  50.0,  75.0)
$scenSN    = @(3800.0,3200.0,2800.0,2400.0)
$scenGM    = @(0.90,  1.10,  2.20,  0.10)
$scenPNm   = @(0.0,   150.0, 250.0, 350.0)
$scenSE    = @(0.35,  0.22,  0.20,  0.06)
$scenDur   = @(45.0,  60.0,  60.0,  60.0)

# ── tire profiles ─────────────────────────────────────────────────────────────
$profNames = @('slick',      'sport_plus', 'sport')
$profTOpt  = @(92.0,  76.0,  68.0)
$profSH    = @(6.5,   8.2,   9.2)
$profWH    = @(3.8,   3.8,   5.3)
$profRR    = @(0.55,  0.70,  0.80)
$profTI    = @(0.52,  0.44,  0.39)
$profCI    = @(0.80,  0.71,  0.63)
$profRct   = @(1.2,   1.3,   1.35)
$profSC    = @(0.072, 0.088, 0.095)
$profAC    = @(0.025, 0.029, 0.031)
$profStC   = @(0.082, 0.095, 0.105)
$profCoC   = @(0.033, 0.038, 0.042)
$profCvC   = @(0.008, 0.0095,0.011)
$profTcM   = @(1.05,  1.15,  1.18)

$aeroLoads = @(0.0, 500.0, 1000.0, 2000.0, 3500.0, 5000.0)

# flat result list
[int]$nA = $aeroLoads.Count; [int]$nP = $profNames.Count; [int]$nS = $scenTags.Count
$Results = New-Object 'System.Collections.Generic.List[object]'
for ($x=0; $x -lt ($nS*$nA*$nP); $x++) { [void]$Results.Add($null) }

for ($si = 0; $si -lt $scenTags.Count; $si++) {
  [double]$vMs = $scenVms[$si]
  [double]$sN  = $scenSN[$si]
  [double]$gM  = $scenGM[$si]
  [double]$pNm = $scenPNm[$si]
  [double]$sE  = $scenSE[$si]
  [double]$dur = $scenDur[$si]

  # per-scenario constants
  [double]$angVel = $vMs / $RADIUS
  [double]$cAir   = $vMs + $angVel * $RADIUS * 0.35
  [double]$effAir = $cAir / (1.0 + $cAir / 220.0)
  [double]$aeroRamp = [math]::Max(0.0, [math]::Min(1.0, ($vMs - $AERO_V0) / [math]::Max(1.0, $AERO_V1 - $AERO_V0)))
  [double]$pAbs = [math]::Abs($pNm)
  [double]$dhg0 = [math]::Min(1.0, ($sE * 2.5) + ($gM * 0.45))
  [double]$ePG0 = [math]::Max(0.0, [math]::Min(1.0, ($pAbs - $DPC) / [math]::Max(1.0, $DPEF)))
  if ($sE -lt 0.06 -and $gM -lt 0.28 -and $pAbs -lt 40.0) { $dhg0 = $dhg0 * 0.15 }
  [double]$dhg = [math]::Max($dhg0, $ePG0)
  [double]$ePG = $ePG0

  for ($ai = 0; $ai -lt $aeroLoads.Count; $ai++) {
    [double]$aeroN = $aeroLoads[$ai]
    [double]$totN  = $sN + $aeroN

    # load_kg
    [double]$lkr = $totN / 9.81
    [double]$lk  = ((400.0 + $lkr) * $lkr / (100.0 + $lkr) - 0.15 * $lkr)

    # thermal discount
    [double]$lkTh = $lk
    if ($aeroRamp -gt 0.0) { $lkTh = $lk * (1.0 - $aeroRamp * $AERO_MAXFRAC * (1.0 - $AERO_SCALE)) }
    [double]$disc_pct = 100.0 * (1.0 - $lkTh / [math]::Max(0.1, $lk))

    # patch
    [double]$ea  = [math]::Max(0.004, [math]::Min($WIDTH_M * 0.28, $totN / $PRES_PA))
    [double]$pf  = [math]::Max($PFMIN, [math]::Min($PFMAX, ($ea / $WIDTH_M) / [math]::Max(0.4, 2.0 * [math]::PI * $RADIUS)))
    [double]$pHS = [math]::Max(0.40,  [math]::Min(1.20,  $pf / [math]::Max(0.05, $PFREF)))
    [double]$fbc = 1.0 + (1.0 - $pf) * ($FBCM - 1.0)

    for ($pi = 0; $pi -lt $profNames.Count; $pi++) {
      [double]$tOpt  = $profTOpt[$pi];  [double]$slipH = $profSH[$pi]
      [double]$workH = $profWH[$pi];    [double]$rollRes = $profRR[$pi]
      [double]$tI    = $profTI[$pi];    [double]$cI    = $profCI[$pi]
      [double]$rct   = $profRct[$pi];   [double]$sC    = $profSC[$pi]
      [double]$aC    = $profAC[$pi];    [double]$stC   = $profStC[$pi]
      [double]$coC   = $profCoC[$pi];   [double]$cvC   = $profCvC[$pi]
      [double]$tcM   = $profTcM[$pi]

      [double]$adj      = $rct / [math]::Max(0.05, $tI)
      [double]$coreRate = 0.08 / [math]::Max(0.05, $cI)

      [double]$skin     = $ENV_C + 1.0
      [double]$core     = $ENV_C
      [double]$peakSkin = $skin
      $tAt70=$null; $tAt80=$null; $tAt90=$null; $tAt100=$null; $tAt110=$null; $tAt120=$null
      [bool]$eqR=$false; $eqTemp=$null; $eqTime=$null

      [int]$nSteps = [int]($dur / $DT)
      for ($i = 0; $i -lt $nSteps; $i++) {
        [double]$seh  = $sE / (1.0 + $sE * 0.12)
        [double]$lc   = $WT * $lkTh
        [double]$gW   = [math]::Max(0.0, $gM - 0.22)
        [double]$rel  = $gW * $lc / 1000.0
        [double]$r1   = ($seh*0.05 + ($pAbs*0.066*$dhg)*0.002) * 3.0*$WT * ([math]::Max($SURF_MU-0.5,0.1)*2.0)
        [double]$r2   = ((0.0078*($seh*$seh)*$lc)*$slipH + 0.145*$rel*$workH/(1.0+($seh*$seh))) * $SURF_MU / $TYRE_W
        [double]$tDist= $skin / [math]::Max(1.0, $tOpt)
        [double]$tf   = 1.0; if ($tDist -gt 1.1) { $tf = [math]::Max(0.30, 1.0-($tDist-1.1)*0.6) }
        [double]$gain = ($r1+$r2) / $HMS * $tf * $pHS
        [double]$cr   = 1.0/(1.0+[math]::Min(0.18,[math]::Max(0.0,$gM-0.20)*0.22))
        [double]$vc   = [math]::Pow([math]::Max(0.01,$effAir),0.8) * $aC * 0.155 * $cr
        [double]$conv = ($skin-$ENV_C)*($stC*0.04+$vc)*$fbc
        [double]$tK=$skin+273.15; [double]$eK=$ENV_C+273.15
        [double]$rad  = ($RUBBER_E*$STEFAN*([math]::Pow($tK,4)-[math]::Pow($eK,4)))*0.0001
        [double]$cRt  = ($ASPH*$tcM*$ea*($skin-$TRACK_C)/$THK)*(1.0/(1.0+$sE*0.1))
        [double]$sCond= ([math]::Max(-25.0,[math]::Min(110.0,$cRt*0.003)))*$WT
        [double]$toC  = ($core-$skin)*$sC
        [double]$sr   = ($gain-$conv-$rad-$sCond+$toC)*$adj/$TYRE_W
        [double]$ps   = $skin
        $skin = [math]::Max(-20.0,[math]::Min(400.0,$skin+$DT*$sr))
        if ($skin -gt $peakSkin) { $peakSkin=$skin }
        [double]$fS   = ($skin-$core)*$sC
        [double]$cCool= ($core-$ENV_C)*($coC*0.12+0.18*$cvC*[math]::Pow([math]::Max(0.01,$effAir),0.8)*0.20)
        [double]$hC   = $DHYB+($DHYE-$DHYB)*$ePG
        [double]$angH = $angVel/(1.0+$angVel/90.0)
        [double]$tH   = ($pAbs*$dhg*$angH*$hC*$rollRes)/$HMS
        $core = [math]::Max(-20.0,[math]::Min(400.0,$core+$DT*($fS+$tH-$cCool)*$coreRate*8.0))
        [double]$t = [double]$i*$DT
        if($null -eq $tAt70  -and $skin -ge 70)  { $tAt70  =[math]::Round($t,1) }
        if($null -eq $tAt80  -and $skin -ge 80)  { $tAt80  =[math]::Round($t,1) }
        if($null -eq $tAt90  -and $skin -ge 90)  { $tAt90  =[math]::Round($t,1) }
        if($null -eq $tAt100 -and $skin -ge 100) { $tAt100 =[math]::Round($t,1) }
        if($null -eq $tAt110 -and $skin -ge 110) { $tAt110 =[math]::Round($t,1) }
        if($null -eq $tAt120 -and $skin -ge 120) { $tAt120 =[math]::Round($t,1) }
        if(-not $eqR -and $t -gt 8.0 -and ([math]::Abs($skin-$ps)/$DT) -lt 0.08) {
          $eqR=$true; $eqTemp=[math]::Round($skin,1); $eqTime=[math]::Round($t,1)
        }
      }

      $Results[$si * $nA * $nP + $ai * $nP + $pi] = [pscustomobject]@{
        tyre=[string]$profNames[$pi]; scenario=[string]$scenTags[$si]
        aeroN=[double]$aeroN; totN=[double]$totN; vMs=[double]$vMs
        aeroRamp=[math]::Round($aeroRamp,3); disc=[math]::Round($disc_pct,1)
        lk=[math]::Round($lk,1); lkTh=[math]::Round($lkTh,1)
        pf=[math]::Round($pf,4); pHS=[math]::Round($pHS,3); fbc=[math]::Round($fbc,3)
        endSkin=[math]::Round($skin,1); endCore=[math]::Round($core,1); peakSkin=[math]::Round($peakSkin,1)
        eqTemp=$eqTemp; eqTime=$eqTime
        tAt70=$tAt70; tAt80=$tAt80; tAt90=$tAt90; tAt100=$tAt100; tAt110=$tAt110; tAt120=$tAt120
      }
    }
  }
}

$populated = ($Results | Where-Object { $_ -ne $null }).Count
Write-Host "Computed $populated results"

# helper: get result by indices
function GR([int]$si,[int]$ai,[int]$pi) { return $script:Results[$si * $script:nA * $script:nP + $ai * $script:nP + $pi] }
[int]$ai0 = 0   # aeroLoads[0] = 0.0
[int]$ai5 = 5   # aeroLoads[5] = 5000.0

# ── Report ────────────────────────────────────────────────────────────────────
$hdr = '{0,-12} {1,6} {2,7} {3,6} {4,7} {5,8} {6,8} {7,8} {8,7}'
for ($si = 0; $si -lt $scenTags.Count; $si++) {
  [double]$vMs = $scenVms[$si]
  [double]$aR=[math]::Max(0.0,[math]::Min(1.0,($vMs-$AERO_V0)/[math]::Max(1.0,$AERO_V1-$AERO_V0)))
  [double]$dMax=100.0*$aR*$AERO_MAXFRAC*(1.0-$AERO_SCALE)
  [void]$sb.AppendLine(('='*80))
  [void]$sb.AppendLine(('  {0}  [{1}]' -f $scenTags[$si],$scenDescs[$si]))
  [void]$sb.AppendLine(('  v={0}m/s  static={1}N  gMag={2}  slipE={3}  propNm={4}  aeroRamp={5:n3}  maxDisc={6:n1}%' -f $vMs,$scenSN[$si],$scenGM[$si],$scenSE[$si],$scenPNm[$si],$aR,$dMax))
  [void]$sb.AppendLine(('-'*80))
  [void]$sb.AppendLine(($hdr -f 'tyre','aeroN','totN','disc%','lkTh','endSkin','peak','eqTemp','t@90'))
  for ($ai = 0; $ai -lt $aeroLoads.Count; $ai++) {
    for ($pi = 0; $pi -lt $profNames.Count; $pi++) {
      $r = GR $si $ai $pi
      $eq  = if($null -ne $r.eqTemp){"$($r.eqTemp)C"}else{'rising'}
      $t90 = if($null -ne $r.tAt90){"$($r.tAt90)s"}else{'-'}
      [void]$sb.AppendLine(($hdr -f $r.tyre,$r.aeroN,$r.totN,$r.disc,$r.lkTh,$r.endSkin,$r.peakSkin,$eq,$t90))
    }
  }
  [void]$sb.AppendLine('')
}

# Aero ramp table
[void]$sb.AppendLine(('='*80))
[void]$sb.AppendLine('AERO RAMP vs MAX DISCOUNT  (ramp * maxFrac * (1-scale) = ramp * 0.216)')
[void]$sb.AppendLine(('{0,10} {1,10} {2,14}' -f 'speed_ms','aeroRamp','maxDiscount%'))
for ($si=0;$si -lt $scenTags.Count;$si++){
  [double]$vMs=$scenVms[$si]
  [double]$aR=[math]::Max(0.0,[math]::Min(1.0,($vMs-$AERO_V0)/[math]::Max(1.0,$AERO_V1-$AERO_V0)))
  [void]$sb.AppendLine(('{0,10:n1} {1,10:n3} {2,14:n2}' -f $vMs,$aR,(100.0*$aR*$AERO_MAXFRAC*(1.0-$AERO_SCALE))))
}

# 5kN deep-dive
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('='*80))
[void]$sb.AppendLine('5kN/WHEEL EDGE CASE  (aeroN=5000 N per wheel = 20kN total)')
[void]$sb.AppendLine(('{0,-12} {1,-20} {2,6} {3,7} {4,8} {5,8} {6,8}' -f 'tyre','scenario','disc%','lkTh','endSkin','peak','eqTemp'))
for ($si=0;$si -lt $scenTags.Count;$si++){
  for($pi=0;$pi -lt $profNames.Count;$pi++){
    $r = GR $si $ai5 $pi
    $eq=if($null -ne $r.eqTemp){"$($r.eqTemp)C"}else{'rising'}
    [void]$sb.AppendLine(('{0,-12} {1,-20} {2,6:n1} {3,7:n1} {4,8:n1} {5,8:n1} {6,8}' -f $r.tyre,$r.scenario,$r.disc,$r.lkTh,$r.endSkin,$r.peakSkin,$eq))
  }
}

# Aero load delta table
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('='*80))
[void]$sb.AppendLine('LOAD SENSITIVITY: peakSkin(5kN) - peakSkin(0N)')
[void]$sb.AppendLine('Expected: hairpin delta > fast-corner delta (discount active at high speed)')
[void]$sb.AppendLine(('{0,-12} {1,-20} {2,9} {3,9} {4,9}' -f 'tyre','scenario','0N_peak','5kN_peak','delta'))
for ($si=0;$si -lt $scenTags.Count;$si++){
  for($pi=0;$pi -lt $profNames.Count;$pi++){
    $r0 = GR $si $ai0 $pi; $r5 = GR $si $ai5 $pi
    [double]$d = $r5.peakSkin - $r0.peakSkin
    $ds = if($d -ge 0){"+$([math]::Round($d,1))"}else{"$([math]::Round($d,1))"}
    $f=if([math]::Abs($d)-lt 1.5){'(negligible)'}elseif($d -gt 20){'!! LARGE'}elseif($d -lt -5 -and $r0.vMs -gt 40){'!! over-discounted'}else{''}
    [void]$sb.AppendLine(('{0,-12} {1,-20} {2,9:n1} {3,9:n1} {4,9} {5}' -f $r0.tyre,$r0.scenario,$r0.peakSkin,$r5.peakSkin,$ds,$f))
  }
}

# Patch vs load
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('='*80))
[void]$sb.AppendLine('CONTACT PATCH vs TOTAL LOAD (31 PSI)')
[void]$sb.AppendLine(('{0,8} {1,8} {2,10} {3,12} {4,12}' -f 'totalN','lk','patchFrac','patchHeatSc','freeBeltCB'))
foreach ($lN in @(800,1500,2500,3200,4000,5200,6700,8200,9000)) {
  [double]$lN2=[double]$lN
  [double]$ea2=[math]::Max(0.004,[math]::Min($WIDTH_M*0.28,$lN2/$PRES_PA))
  [double]$pf2=[math]::Max($PFMIN,[math]::Min($PFMAX,($ea2/$WIDTH_M)/[math]::Max(0.4,2.0*[math]::PI*$RADIUS)))
  [double]$pHS2=[math]::Max(0.40,[math]::Min(1.20,$pf2/[math]::Max(0.05,$PFREF)))
  [double]$fbc2=1.0+(1.0-$pf2)*($FBCM-1.0)
  [double]$lkr2=$lN2/9.81; [double]$lk2=((400.0+$lkr2)*$lkr2/(100.0+$lkr2)-0.15*$lkr2)
  $flg=if($pf2 -ge $PFMAX){'<- AT CEILING'}else{''}
  [void]$sb.AppendLine(('{0,8:n0} {1,8:n1} {2,10:n4} {3,12:n3} {4,12:n3} {5}' -f $lN2,$lk2,$pf2,$pHS2,$fbc2,$flg))
}

# Recommendations
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('='*80))
[void]$sb.AppendLine('RECOMMENDATIONS')
[double]$dMax2=100.0*1.0*$AERO_MAXFRAC*(1.0-$AERO_SCALE)
[void]$sb.AppendLine(('[Current] scale=0.55  maxFrac=0.48  maxDiscount={0:n1}%' -f $dMax2))
# slick hairpin vs fast corner delta
$rh0=GR 0 $ai0 0; $rh5=GR 0 $ai5 0
$rf0=GR 2 $ai0 0; $rf5=GR 2 $ai5 0
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Slick sensitivity (lower discount at low speed = more aero heat):')
  [double]$dH = $rh5.peakSkin - $rh0.peakSkin
  [double]$dF = $rf5.peakSkin - $rf0.peakSkin
  $dHs = if($dH -ge 0) { "+$([math]::Round($dH,1))" } else { "$([math]::Round($dH,1))" }
  $dFs = if($dF -ge 0) { "+$([math]::Round($dF,1))" } else { "$([math]::Round($dF,1))" }
  [void]$sb.AppendLine(("  Hairpin   (aeroRamp=0.00): 0N=$($rh0.peakSkin)C  5kN=$($rh5.peakSkin)C  delta=${dHs}C"))
  [void]$sb.AppendLine(("  FastCorner(aeroRamp=0.85): 0N=$($rf0.peakSkin)C  5kN=$($rf5.peakSkin)C  delta=${dFs}C"))
[void]$sb.AppendLine('  If hairpin delta >> fast-corner delta: discount working correctly.')
$pAtCeil = 0
for($si=0;$si -lt $scenTags.Count;$si++){for($ai=0;$ai -lt $aeroLoads.Count;$ai++){for($pi=0;$pi -lt $profNames.Count;$pi++){if((GR $si $ai $pi).pf -ge $PFMAX){$pAtCeil++}}}}
[void]$sb.AppendLine('')
if($pAtCeil -gt 0){
  [void]$sb.AppendLine("!! patchFrac at ceiling in $pAtCeil scenario(s). Raise patchFracMax to 0.22 for hi-DFC cars.")
}else{
  [void]$sb.AppendLine("  patchFrac below ceiling across all loads. patchFracMax=0.20 OK.")
}
if($dMax2 -lt 15){ [void]$sb.AppendLine("  Discount LOW: raise maxFrac or lower scale.") }
elseif($dMax2 -gt 30){ [void]$sb.AppendLine("  Discount HIGH: lower maxFrac or raise scale.") }
else{ [void]$sb.AppendLine("  Discount in good range (15-30%). Aero heat moderate and speed-dependent.") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('KNOB REFERENCE')
[void]$sb.AppendLine('  aeroHeatScale   : 1.0=aero heats same as weight; 0.0=no heat from aero. Current 0.55')
[void]$sb.AppendLine('  aeroHeatMaxFrac : max aero fraction of load_kg discounted at full speed. Current 0.48')
[void]$sb.AppendLine('  aeroHeatSpeedFull: ramp fully active at this m/s. Current 56m/s (200km/h)')
[void]$sb.AppendLine('  patchFracMax    : contact patch ceiling. Current 0.20; raise to 0.22 for heavy hi-DFC')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('  Aggressive hi-DFC: scale=0.45  maxFrac=0.55  speedFull=50m/s  patchFracMax=0.22')
[void]$sb.AppendLine('  Conservative:      scale=0.60  maxFrac=0.42  speedFull=60m/s  patchFracMax=0.20')

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host $sb.ToString()
Write-Host "WROTE: $out"
