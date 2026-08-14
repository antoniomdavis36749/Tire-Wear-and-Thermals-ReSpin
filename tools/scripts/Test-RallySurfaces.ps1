# Rally tire family x ALL surfaces
# Live: names matching rally/tarmac/asphalt → STANDALONE_MODIFIERS.rally (profile1/2 = "rally")
# Surface scale still follows treadCoef; profile bias uses has("rally") on profile tags.
$ErrorActionPreference = 'Stop'
$out = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'output') 'rally-surface-test.txt'

function Lerp([double]$a,[double]$b,[double]$t){ return $a+($b-$a)*$t }
function Clamp([double]$v,[double]$lo,[double]$hi){ if($v -lt $lo){return $lo}; if($v -gt $hi){return $hi}; return $v }

$gripCoeffs = @(
  @{tag='sport_plus'; c=@(1.12,0.22,-0.08)},
  @{tag='sport'; c=@(1.02,0.16,-0.06)},
  @{tag='rally'; c=@(0.98,0.14,-0.05)},
  @{tag='standard'; c=@(0.92,0.12,-0.04)},
  @{tag='allterrain'; c=@(0.82,0.10,-0.03)},
  @{tag='mudterrain'; c=@(0.76,0.08,-0.02)}
)
function Baseline([string]$profile) {
  $p = $profile.ToLowerInvariant()
  # Live: tarmac/asphalt names resolve to profile tags "rally"/"rally"
  if ($p.Contains('tarmac') -or ($p.Contains('asphalt') -and -not $p.Contains('supersport'))) {
    $c = @(0.98,0.14,-0.05); return $c[0]+$c[1]+$c[2]
  }
  foreach ($row in $gripCoeffs) {
    if ($p.Contains($row.tag)) { $c=$row.c; return $c[0]+$c[1]+$c[2] }
  }
  return 0.90
}

function SurfaceScale([string]$surface, [double]$tread, [double]$drainage) {
  switch ($surface) {
    'dry_paved'   { $a = Lerp 1.04 0.90 $tread; return ,@($a, 1.15) }
    'hard_smooth' { $a = Lerp 0.96 0.90 $tread; return ,@($a, 1.10) }
    'wet_paved'   {
      $wet = (Lerp 0.82 0.98 $drainage) * (Lerp 0.94 1.02 $tread)
      $dry = Lerp 1.04 0.90 $tread
      $a = [math]::Min($wet, $dry * 0.92)
      return ,@($a, 1.15)
    }
    'gravel'      { $a = Lerp 0.55 1.05 $tread; return ,@($a, 1.00) }
    'gravel_wet'  { $a = Lerp 0.48 0.95 $tread; return ,@($a, 0.88) }
    'dirt'        { $a = Lerp 0.62 1.02 $tread; return ,@($a, 0.95) }
    'mud'         { $a = Lerp 0.34 1.08 $tread; return ,@($a, 0.85) }
    'sand'        { $a = Lerp 0.42 1.04 $tread; return ,@($a, 0.90) }
    'snow'        { $a = Lerp 0.36 1.00 $tread; return ,@($a, 0.60) }
    'ice'         { $a = Lerp 0.42 0.78 $tread; return ,@($a, 0.30) }
    'rock'        { $a = Lerp 0.88 1.05 $tread; return ,@($a, 1.40) }
    'generic'     { return ,@(1.0, 1.30) }
    default       { return ,@(1.0, 1.30) }
  }
}

# Live applyProfileSurfaceBias (profile tags: rally tires always have profile1="rally")
function ProfileBias([double]$g, [string]$surface, [string]$profile) {
  $p = $profile.ToLowerInvariant()
  $isRally = $p.Contains('rally') -or $p.Contains('tarmac') -or ($p.Contains('asphalt') -and -not $p.Contains('supersport'))
  $isPaddle=$p.Contains('paddle'); $isWinter=$p.Contains('winter')
  $isCrawler=$p.Contains('crawler'); $isMT=$p.Contains('mudterrain'); $isAT=$p.Contains('allterrain')
  $isSlick=$p.Contains('slick'); $isRain=($p -eq 'rain'); $isDrift=$p.Contains('drift'); $isDrag=$p.Contains('drag')
  $isSportPlus=$p.Contains('sport_plus')
  $isSport=$p.Contains('sport') -and -not $isSportPlus -and -not $p.Contains('supersport')
  $isStreetLoose=($p.Contains('standard') -or $isSport -or $p.Contains('vintage')) -and -not $isRally -and -not $isAT -and -not $isMT -and -not $isCrawler -and -not $isSlick -and -not $isDrag -and -not $isPaddle
  $isStreetAsphalt=($p.Contains('standard') -or $p.Contains('vintage')) -and -not $isRally -and -not $isAT -and -not $isMT -and -not $isCrawler -and -not $isSlick -and -not $isDrag -and -not $isPaddle

  switch ($surface) {
    'sand' {
      if($isPaddle){return $g*1.35} elseif($isMT){return $g*1.10} elseif($isAT -or $isCrawler){return $g*1.06}
      elseif($isStreetLoose){return $g*0.90} elseif($isSlick -or $isDrag){return $g*0.88}
    }
    'mud' {
      if($isPaddle){return $g*1.25} elseif($isMT -or $isCrawler){return $g*1.14}
      elseif($isRally -or $isAT){return $g*1.08}
      elseif($isStreetLoose){return $g*0.86} elseif($isSlick -or $isDrag){return $g*0.82}
    }
    'rock' {
      if($isCrawler){return $g*1.18} elseif($isAT){return $g*1.06}
      elseif($isPaddle){return $g*0.80} elseif($isSlick){return $g*0.94}
    }
    { $_ -in @('gravel','dirt') } {
      if($isRally){return $g*1.20} elseif($isAT){return $g*1.10} elseif($isMT){return $g*1.06}
      elseif($isStreetLoose){return $g*0.90}
      elseif($isSlick -or $isDrag){return $g*0.90} elseif($isDrift){return $g*0.95}
    }
    'gravel_wet' {
      if($isRally){return $g*1.14} elseif($isAT){return $g*1.08}
      elseif($isMT -or $isCrawler){return $g*1.10}
      elseif($isRain){return $g*1.06} elseif($isStreetLoose){return $g*0.88} elseif($isSlick){return $g*0.85}
    }
    { $_ -in @('snow','ice') } {
      if($isWinter){return $g*1.22} elseif($isRain){return $g*1.08}
      elseif($isAT){return $g*1.05} elseif($isStreetLoose){return $g*0.92} elseif($isSlick -or $isDrag){return $g*0.82}
    }
    'wet_paved' {
      if($isRain){return $g*1.06} elseif($isWinter){return $g*1.04}
      elseif($isSlick -or $isDrag){return $g*0.92}
    }
    { $_ -in @('dry_paved','hard_smooth') } {
      if($isSlick -or $isDrag){return $g*1.0}
      elseif($isMT -or $isCrawler){return $g*0.96}
      elseif($isPaddle){return $g*0.90}
      elseif($isStreetAsphalt){return $g*1.02}
    }
  }
  return $g
}

# Rally family: same STANDALONE rally mods; tread spans tarmac → hard gravel.
# Alias rows confirm tarmac/asphalt name routing (live maps them to profile "rally").
$tires = @(
  @{ class='rally'; name='rally_tarmac';         tread=0.35; gm=0.96; drain=0.75; wet=1.038; dry=1.00 },
  @{ class='rally'; name='rally_gravel_soft';    tread=0.55; gm=0.96; drain=0.75; wet=1.038; dry=1.00 },
  @{ class='rally'; name='rally_gravel_medium';  tread=0.70; gm=0.96; drain=0.75; wet=1.038; dry=1.00 },
  @{ class='rally'; name='rally_gravel_hard';    tread=0.85; gm=0.96; drain=0.75; wet=1.038; dry=1.00 },
  @{ class='alias'; name='tarmac';               tread=0.35; gm=0.96; drain=0.75; wet=1.038; dry=1.00 },
  @{ class='alias'; name='asphalt_rally';        tread=0.40; gm=0.96; drain=0.75; wet=1.038; dry=1.00 },
  # Controls: sport + standard (street-family surface bias; not rally)
  @{ class='ctrl';  name='sport';                tread=0.50; gm=1.00; drain=0.72; wet=1.03;  dry=1.02 },
  @{ class='ctrl';  name='standard';             tread=0.70; gm=1.00; drain=0.80; wet=1.05;  dry=1.00 }
)

$surfaces = @('dry_paved','hard_smooth','wet_paved','gravel','gravel_wet','dirt','mud','sand','snow','ice','rock','generic')
$mu = @{
  dry_paved=1.00; hard_smooth=0.85; wet_paved=0.70; gravel=0.75; gravel_wet=0.55
  dirt=0.70; mud=0.50; sand=0.55; snow=0.35; ice=0.18; rock=0.90; generic=0.80
}

function EffGrip($tire, [string]$surface) {
  $g = (Baseline $tire.name) * [double]$tire.gm
  $sc = SurfaceScale $surface ([double]$tire.tread) ([double]$tire.drain)
  $g = $g * [double]$sc[0]
  $g = ProfileBias $g $surface $tire.name
  if ($surface -eq 'wet_paved' -or $surface -eq 'gravel_wet') {
    $g = $g * [double]$tire.wet
    if ($surface -eq 'wet_paved') {
      $drySc = SurfaceScale 'dry_paved' ([double]$tire.tread) ([double]$tire.drain)
      $wetSc = SurfaceScale 'wet_paved' ([double]$tire.tread) ([double]$tire.drain)
      $dryBias = 1.0
      $pn = $tire.name.ToLowerInvariant()
      if ($pn.Contains('mudterrain') -or $pn.Contains('crawler') -or $pn.Contains('offroad') -or $pn.Contains('logger')) { $dryBias = 0.96 }
      elseif ($pn.Contains('highway') -or $pn.Contains('trailer')) { $dryBias = 1.02 }
      $ratioCap = ([double]$drySc[0] * [double]$tire.dry * $dryBias) / [math]::Max(0.001, [double]$wetSc[0] * [double]$tire.wet) * 0.98
      if ($ratioCap -lt 1.0) { $g = $g * $ratioCap }
    }
  } elseif ($surface -eq 'dry_paved' -or $surface -eq 'hard_smooth') {
    $g = $g * [double]$tire.dry
  }
  $beam = Clamp ([double]$mu[$surface]) 0.18 1.20
  return [math]::Round([math]::Min($g, [double]$sc[1] / $beam), 3)
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('RALLY TIRE TYPES x ALL SURFACES')
[void]$sb.AppendLine('Warm 100% condition; standalone rally mods; tread drives surfaceScale')
[void]$sb.AppendLine('Aliases tarmac/asphalt_rally = same mods as rally (live name routing)')
[void]$sb.AppendLine('')

$hdr = 'profile'.PadRight(28)
foreach ($s in $surfaces) { $hdr += ('{0,10}' -f $s) }
[void]$sb.AppendLine($hdr)

$rows = @{}
foreach ($tire in $tires) {
  $line = ('[{0}] {1}' -f $tire.class, $tire.name).PadRight(28)
  $row = @{}
  foreach ($s in $surfaces) {
    $v = EffGrip $tire $s
    $row[$s] = $v
    $line += ('{0,10:n3}' -f $v)
  }
  $rows[$tire.name] = $row
  [void]$sb.AppendLine($line)
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== LOGIC CHECKS ===')
$fail = 0; $pass = 0
function Expect([bool]$ok, [string]$msg) {
  if ($ok) { $script:pass++; [void]$sb.AppendLine("PASS  $msg") }
  else { $script:fail++; [void]$sb.AppendLine("FAIL  $msg") }
}

$rallyNames = @('rally_tarmac','rally_gravel_soft','rally_gravel_medium','rally_gravel_hard','tarmac','asphalt_rally')

# Pavement: tarmac tread beats hard gravel
Expect ($rows['rally_tarmac']['dry_paved'] -gt $rows['rally_gravel_hard']['dry_paved']) 'tarmac > hard gravel on dry_paved'
Expect ($rows['rally_tarmac']['dry_paved'] -gt $rows['rally_gravel_medium']['dry_paved']) 'tarmac > medium gravel on dry_paved'

# Loose: higher tread wins among rally family
foreach ($s in @('gravel','dirt','mud','sand')) {
  Expect ($rows['rally_gravel_hard'][$s] -gt $rows['rally_tarmac'][$s]) "hard gravel > tarmac on $s"
  Expect ($rows['rally_gravel_medium'][$s] -gt $rows['rally_tarmac'][$s]) "medium gravel > tarmac on $s"
  Expect ($rows['rally_gravel_soft'][$s] -gt $rows['rally_tarmac'][$s]) "soft gravel > tarmac on $s"
}

# Rally bias: medium gravel beats sport control on gravel/dirt
Expect ($rows['rally_gravel_medium']['gravel'] -gt $rows['sport']['gravel']) 'rally_medium > sport on gravel'
Expect ($rows['rally_gravel_medium']['dirt'] -gt $rows['sport']['dirt']) 'rally_medium > sport on dirt'
Expect ($rows['rally_gravel_medium']['gravel_wet'] -gt $rows['sport']['gravel_wet']) 'rally_medium > sport on gravel_wet'
# Mud still worse than gravel (clog-softening must not erase surface hierarchy)
Expect ($rows['rally_gravel_medium']['mud'] -lt $rows['rally_gravel_medium']['gravel']) 'rally_medium mud < gravel'
Expect ($rows['rally_gravel_soft']['mud'] -lt $rows['rally_gravel_soft']['gravel']) 'rally_soft mud < gravel'
# Loose baseline floor after gravel/dirt bias bump (1.12 → 1.20)
Expect ($rows['rally_gravel_medium']['gravel'] -gt 1.05) 'rally_medium gravel bite (>1.05)'
Expect ($rows['rally_gravel_soft']['gravel'] -gt 0.95) 'rally_soft gravel bite (>0.95)'

# Alias parity with matching tread
Expect ([math]::Abs($rows['tarmac']['dry_paved'] - $rows['rally_tarmac']['dry_paved']) -lt 0.001) 'tarmac alias ~= rally_tarmac on dry_paved'
Expect ([math]::Abs($rows['tarmac']['gravel'] - $rows['rally_tarmac']['gravel']) -lt 0.001) 'tarmac alias ~= rally_tarmac on gravel'

# Wet/ice sanity for every rally (+ aliases)
foreach ($n in $rallyNames) {
  Expect ($rows[$n]['ice'] -lt $rows[$n]['dirt']) "$n ice < dirt"
  Expect ($rows[$n]['ice'] -lt $rows[$n]['dry_paved']) "$n ice < dry_paved"
  Expect ($rows[$n]['wet_paved'] -lt $rows[$n]['dry_paved']) "$n wet_paved < dry_paved"
  Expect ($rows[$n]['wet_paved'] -gt 0.45) "$n wet_paved usable (>0.45)"
  Expect ($rows[$n]['gravel'] -gt 0.55) "$n gravel usable (>0.55)"
}

# Soft < medium < hard on gravel (monotonic tread benefit)
Expect ($rows['rally_gravel_soft']['gravel'] -lt $rows['rally_gravel_medium']['gravel']) 'soft < medium on gravel'
Expect ($rows['rally_gravel_medium']['gravel'] -lt $rows['rally_gravel_hard']['gravel']) 'medium < hard on gravel'

# Tarmac competitive on asphalt vs sport (not a cheat — allow ~0.10 gap; sport still leads)
Expect ($rows['rally_tarmac']['dry_paved'] -ge $rows['sport']['dry_paved'] - 0.10) 'rally_tarmac ~>= sport on dry_paved (within 0.10)'

# Street asphalt vs loose relative gap (after standard gm bump + street-family bias)
$stdDry = [double]$rows['standard']['dry_paved']
$stdGrav = [double]$rows['standard']['gravel']
$stdDirt = [double]$rows['standard']['dirt']
$stdMud = [double]$rows['standard']['mud']
$stdAG = $stdDry / [math]::Max(0.001, $stdGrav)
$stdAD = $stdDry / [math]::Max(0.001, $stdDirt)
$stdAM = $stdDry / [math]::Max(0.001, $stdMud)
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('STREET_ASPHALT_LOOSE standard dry={0:n3} gravel={1:n3} dirt={2:n3} mud={3:n3}' -f $stdDry,$stdGrav,$stdDirt,$stdMud))
[void]$sb.AppendLine(('  ratios asphalt:gravel={0:n3} asphalt:dirt={1:n3} asphalt:mud={2:n3}' -f $stdAG,$stdAD,$stdAM))
Expect ($stdDry -gt $stdGrav) 'standard dry_paved > gravel'
Expect ($stdDry -gt $stdDirt) 'standard dry_paved > dirt'
Expect ($stdMud -lt $stdGrav) 'standard mud < gravel'
Expect ($stdAG -ge 1.12) ("standard asphalt:gravel gap >=1.12 (got {0:n3})" -f $stdAG)
Expect ($stdAD -ge 1.12) ("standard asphalt:dirt gap >=1.12 (got {0:n3})" -f $stdAD)
# Rally loose still clearly ahead of street on gravel after street penalty
Expect ($rows['rally_gravel_medium']['gravel'] -gt $rows['standard']['gravel']) 'rally_medium > standard on gravel'

[void]$sb.AppendLine('')
[void]$sb.AppendLine("RESULT: $pass passed, $fail failed")

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== BEST RALLY PER SURFACE (excl. sport ctrl) ===')
foreach ($s in $surfaces) {
  $best = $null; $bestV = -1
  foreach ($n in $rallyNames) {
    $v = $rows[$n][$s]
    if ($v -gt $bestV) { $bestV = $v; $best = $n }
  }
  [void]$sb.AppendLine(('{0,-12} {1} ({2:n3})' -f $s, $best, $bestV))
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
if ($fail -gt 0) { Write-Output "FAIL count=$fail"; exit 1 }
Write-Output "OK pass=$pass"
