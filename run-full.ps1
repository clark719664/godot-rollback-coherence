param(
 [ValidateSet('original','latest')][string]$Version = 'original',
 [string]$DependencyPath = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.deps'))),
 [string]$GodotPath,
 [string]$PythonPath = 'python',
 [string]$RunPath = (Join-Path $PSScriptRoot '.runs/full'),
 [int]$Port = 25341
)
$ErrorActionPreference = 'Stop'
if (!$GodotPath) { $GodotPath = Join-Path $DependencyPath 'engine472/Godot_v4.7.2-stable_win64_console.exe' }
$addon = if ($Version -eq 'original') {
 Join-Path $DependencyPath 'rapier/godot-rapier-2d-single-enhanced-determinism/addons/godot-rapier2d'
} else { Join-Path $DependencyPath 'rapier-latest/godot-rapier-2d-single/addons/godot-rapier2d' }
& $PythonPath (Join-Path $PSScriptRoot 'full_fixture/run_full.py') --godot $GodotPath --addon $addon --fixture (Join-Path $DependencyPath 'fixture') --run (Join-Path $RunPath $Version) --port $Port
if ($LASTEXITCODE -ne 0) { throw 'Full fixture integration regression failed; inspect peer logs and summary.json.' }
