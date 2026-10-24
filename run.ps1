param(
 [ValidateSet('original','latest')][string]$Version = 'original',
 [string]$GodotPath,
 [string]$AddonPath,
 [string]$RunPath
)
$ErrorActionPreference = 'Stop'
$base = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'work/dependencies'))
if (!$GodotPath) { $GodotPath = Join-Path $base 'engine472/Godot_v4.7.2-stable_win64_console.exe' }
if (!$AddonPath) {
 if ($Version -eq 'original') { $AddonPath = Join-Path $base 'rapier/godot-rapier-2d-single-enhanced-determinism/addons/godot-rapier2d' }
 else { $AddonPath = Join-Path $base 'rapier-latest/godot-rapier-2d-single/addons/godot-rapier2d' }
}
if (!$RunPath) { $RunPath = Join-Path $base "review-$Version" }
if (!(Test-Path -LiteralPath $GodotPath)) { throw 'Godot executable missing; run prepare.ps1 or supply -GodotPath.' }
if (!(Test-Path -LiteralPath $AddonPath)) { throw 'Rapier addon missing; run prepare.ps1 or supply -AddonPath.' }
New-Item -ItemType Directory -Force $RunPath,(Join-Path $RunPath 'addons') | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'project/*') $RunPath -Force
Copy-Item -LiteralPath $AddonPath -Destination (Join-Path $RunPath 'addons') -Recurse -Force
& $GodotPath --headless --path $RunPath --editor --import --quit *> (Join-Path $RunPath 'import.log')
if ($LASTEXITCODE -ne 0) {
 & $GodotPath --headless --path $RunPath --editor --import --quit *> (Join-Path $RunPath 'import-retry.log')
 if ($LASTEXITCODE -ne 0) { throw 'Godot import failed twice; inspect import logs.' }
}
& $GodotPath --headless --path $RunPath --script baseline.gd *> (Join-Path $RunPath 'baseline.log')
if ($LASTEXITCODE -ne 1) { throw 'Baseline did not fail with expected exit1.' }
$baselineLine = Get-Content (Join-Path $RunPath 'baseline.log') | Where-Object { $_.StartsWith('{"before":') }
if (!$baselineLine) { throw 'Baseline script did not produce its real physics sample.' }
$baseline = $baselineLine | ConvertFrom-Json
if ($baseline.restored.hit -or $baseline.restored.server_x -ne 300 -or $baseline.restored.node_x -ne 0) { throw 'Baseline did not reproduce the expected transform/query divergence.' }
& $GodotPath --headless --path $RunPath --script frame_control.gd *> (Join-Path $RunPath 'frame-control.log')
if ($LASTEXITCODE -ne 0) { throw 'Normal-frame control failed.' }
& $GodotPath --headless --path $RunPath --script matrix.gd -- --simulate-noop-restore *> (Join-Path $RunPath 'noop-restore.log')
if ($LASTEXITCODE -ne 1 -or !(Select-String -LiteralPath (Join-Path $RunPath 'noop-restore.log') -SimpleMatch 'RESTORE_ERROR=')) { throw 'No-op restoration fault was not detected.' }
& $GodotPath --headless --path $RunPath --script matrix.gd *> (Join-Path $RunPath 'matrix.log')
if ($LASTEXITCODE -ne 0) { throw 'Real-engine matrix failed; inspect matrix.log.' }
$line = Get-Content (Join-Path $RunPath 'matrix.log') | Where-Object { $_.StartsWith('RESULTS_JSON=') }
if (!$line) { throw 'Godot did not produce matrix measurements.' }
$result = $line.Substring(13) | ConvertFrom-Json
if ($result.Count -ne 72) { throw "Expected72 cases, got $($result.Count)." }
$result | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $RunPath 'results.json')
$result | Group-Object mode | ForEach-Object {
 [PSCustomObject]@{ Mode=$_.Name; Queries=($_.Group.queries | Measure-Object -Sum).Sum;
  MissedHits=($_.Group.missed_hits | Measure-Object -Sum).Sum; FalseHits=($_.Group.false_hits | Measure-Object -Sum).Sum;
  HealthMismatches=($_.Group.health_mismatches | Measure-Object -Sum).Sum; ClockMismatches=($_.Group.clock_mismatches | Measure-Object -Sum).Sum }
} | Format-Table
Write-Output "PASS: baseline reproduced; normal-frame control passed;72 matrix cases verified. Logs: $RunPath"
