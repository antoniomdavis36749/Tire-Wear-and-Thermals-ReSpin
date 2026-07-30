$tel = Join-Path $PSScriptRoot 'wc-gt4-lap-telemetry.csv'
$lines = Get-Content $tel
Write-Output "lines=$($lines.Count)"
$raw = $lines | Where-Object { $_ -and ($_ -notmatch '^#') -and ($_ -notmatch '^wall,') }
$n = 0; $skMin = 999.0; $skMax = -999.0; $skSum = 0.0
$gMin = 999.0; $gMax = -999.0; $gSum = 0.0; $cMin = 999.0
$wall0 = $null; $wall1 = $null
foreach ($line in $raw) {
  $p = $line -split ','
  if ($p.Count -lt 14) { continue }
  $n++
  $wall = [double]$p[0]
  if ($null -eq $wall0 -or $wall -lt $wall0) { $wall0 = $wall }
  if ($null -eq $wall1 -or $wall -gt $wall1) { $wall1 = $wall }
  $sk = ([double]$p[4] + [double]$p[5] + [double]$p[6]) / 3.0
  $g = [double]$p[13]
  $c = [double]$p[3]
  if ($sk -lt $skMin) { $skMin = $sk }
  if ($sk -gt $skMax) { $skMax = $sk }
  $skSum += $sk
  if ($g -lt $gMin) { $gMin = $g }
  if ($g -gt $gMax) { $gMax = $g }
  $gSum += $g
  if ($c -lt $cMin) { $cMin = $c }
}
Write-Output "samples=$n durationSec=$([math]::Round($wall1 - $wall0, 1))"
Write-Output ("skin min/avg/max={0}/{1}/{2}" -f [math]::Round($skMin,1), [math]::Round($skSum/$n,1), [math]::Round($skMax,1))
Write-Output ("grip min/avg/max={0}/{1}/{2}" -f [math]::Round($gMin,3), [math]::Round($gSum/$n,3), [math]::Round($gMax,3))
Write-Output ("condMin={0}" -f [math]::Round($cMin,1))
