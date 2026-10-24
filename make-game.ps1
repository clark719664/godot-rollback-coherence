param(
 [ValidateSet('original','latest')][string]$Version = 'original',
 [string]$DependencyPath = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.deps'))),
 [string]$PythonPath = 'python',
 [string]$GamePath = (Join-Path $PSScriptRoot '.runs/game')
)
$ErrorActionPreference = 'Stop'
$godot = Join-Path $DependencyPath 'engine472/Godot_v4.7.2-stable_win64_console.exe'
$addon = if ($Version -eq 'original') {
 Join-Path $DependencyPath 'rapier/godot-rapier-2d-single-enhanced-determinism/addons/godot-rapier2d'
} else { Join-Path $DependencyPath 'rapier-latest/godot-rapier-2d-single/addons/godot-rapier2d' }
& $PythonPath (Join-Path $PSScriptRoot 'full_fixture/run_full.py') --godot $godot --addon $addon --fixture (Join-Path $DependencyPath 'fixture') --run $GamePath --prepare-game
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare manual game; inspect import.log.' }
Write-Output "Open project.godot in $GamePath, or launch the prepared Godot executable with --path `"$GamePath`"."
