#Requires -Version 5.1
<#
  Canonical contact-patch thermal helper (mirrors live luukstyrethermalsandwear.lua).
  Dot-source from soft-sims: . (Join-Path $PSScriptRoot 'lib\PatchThermal.ps1')
  No area-shrink on soft sink — conduction uses depth/rough denom separately.
#>

function Clamp-Patch([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

# Live THERMAL_TOPOLOGY patch knobs (Phase B/C/D)
function Get-LivePatchTopo {
  return @{
    patchFracMin = 0.035
    patchFracHeatMin = 0.025
    patchFracMax = 0.22
    patchFracRef = 0.070
    patchHeatEmaTau = 0.10
    patchHertzDeflBlend = 0.35
    patchDeflWidthFrac = 0.55
    contactDepthEmaTau = 0.08
    patchUtilBlend = 0.12
    softSinkHeatCoef = 1.2
    softSinkRoughCoef = 0.35
    softSinkHeatFloor = 0.72
    freeBeltCoolMult = 1.32
    hystSkinShare = 0.18
  }
}

<#
.SYNOPSIS
  Hertz F/P + deflection blend → patchFrac / patchHeatScale (live Phase B path).
#>
function Get-PatchThermal {
  param(
    [double]$LoadRawN,
    [double]$DynamicPressurePSI,
    [double]$TyreWidthM,
    [double]$TyreRadiusM,
    [double]$ContactDepthM = 0.0,
    [double]$PeakForceN = 0.0,
    [double]$Rough = 0.0,
    [hashtable]$Topo = $null,
    [switch]$NoDepthBoost,
    [switch]$NoUtilNudge,
    [switch]$NoSoftSinkDamp
  )
  if ($null -eq $Topo) { $Topo = Get-LivePatchTopo }

  $hertzArea = [math]::Max(0.004, [math]::Min($TyreWidthM * 0.24,
    $LoadRawN / [math]::Max(10000.0, $DynamicPressurePSI * 6894.76)))
  $deflArea = $hertzArea
  if ($ContactDepthM -gt 1e-4 -and $TyreRadiusM -gt 0.05 -and $TyreWidthM -gt 0.04) {
    $d = [math]::Min($ContactDepthM, $TyreRadiusM * 0.35)
    $chord = 2.0 * [math]::Sqrt([math]::Max(0.0, 2.0 * $TyreRadiusM * $d - $d * $d))
    $deflArea = [math]::Max(0.004, [math]::Min($TyreWidthM * 0.28,
      $TyreWidthM * $chord * [double]$Topo.patchDeflWidthFrac))
  }
  $depthBlend = (Clamp-Patch (($ContactDepthM - 0.005) / 0.040) 0 1) * [double]$Topo.patchHertzDeflBlend
  $estArea = $hertzArea * (1.0 - $depthBlend) + $deflArea * $depthBlend

  $patchFracRaw = 0.0
  if ($TyreWidthM -gt 0.04 -and $TyreRadiusM -gt 0.05) {
    $patchFracRaw = ($estArea / $TyreWidthM) / [math]::Max(0.4, 2.0 * [math]::PI * $TyreRadiusM)
  }
  $patchFrac = Clamp-Patch $patchFracRaw ([double]$Topo.patchFracMin) ([double]$Topo.patchFracMax)
  $patchFracHeat = Clamp-Patch $patchFracRaw `
    ([double]$(if ($Topo.ContainsKey('patchFracHeatMin')) { $Topo.patchFracHeatMin } else { $Topo.patchFracMin })) `
    ([double]$Topo.patchFracMax)

  $depthHeatBoost = 1.0
  if (-not $NoDepthBoost -and $ContactDepthM -gt 0.006) {
    $depthHeatBoost = 1.0 + [math]::Min(0.16, ($ContactDepthM - 0.006) * 2.0)
  }

  $peakWork = 1.0
  if ($PeakForceN -gt 100 -and $LoadRawN -gt 100) {
    $peakWork = Clamp-Patch ($PeakForceN / [math]::Max($LoadRawN, 1.0)) 0.85 1.35
  }
  $utilNudge = 1.0
  if (-not $NoUtilNudge) {
    $utilNudge = 1.0 + (($peakWork - 1.0) * [double]$(if ($Topo.ContainsKey('patchUtilBlend')) { $Topo.patchUtilBlend } else { 0 }))
  }

  $patchHeatScale = Clamp-Patch (
    ($patchFracHeat / [math]::Max(0.05, [double]$Topo.patchFracRef)) * $depthHeatBoost * $utilNudge
  ) 0.40 1.20

  $freeBeltBias = 1.0 + (1.0 - $patchFrac) * ([double]$Topo.freeBeltCoolMult - 1.0)

  $softSinkDamp = 1.0
  if (-not $NoSoftSinkDamp) {
    $softSinkDamp = 1.0 / (1.0 + [math]::Max(0.0, $ContactDepthM) * [double]$Topo.softSinkHeatCoef +
      $Rough * [double]$Topo.softSinkRoughCoef)
    $softSinkDamp = [math]::Max([double]$Topo.softSinkHeatFloor, $softSinkDamp)
  }

  # Soft-surface conduction denom (live — no area shrink)
  $condDenom = 1.0 + [math]::Max(0.0, $ContactDepthM) * 4.0 + $Rough * 0.5

  return [ordered]@{
    HertzArea      = $hertzArea
    DeflArea       = $deflArea
    EstArea        = $estArea
    DepthBlend     = $depthBlend
    PatchFracRaw   = $patchFracRaw
    PatchFrac      = $patchFrac
    PatchFracHeat  = $patchFracHeat
    DepthHeatBoost = $depthHeatBoost
    PatchHeatScale = $patchHeatScale
    FreeBeltBias   = $freeBeltBias
    SoftSinkDamp   = $softSinkDamp
    CondDenom      = $condDenom
    PeakWorkFactor = $peakWork
    UtilNudge      = $utilNudge
  }
}
