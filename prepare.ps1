param([string]$DependencyPath = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'work/dependencies'))))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $DependencyPath | Out-Null
foreach ($dependency in (Get-Content (Join-Path $PSScriptRoot 'dependencies.json') | ConvertFrom-Json)) {
 $archive = Join-Path $DependencyPath $dependency.archive
 if (!(Test-Path -LiteralPath $archive)) { Invoke-WebRequest $dependency.url -OutFile $archive }
 if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $dependency.sha256) { throw "Checksum mismatch: $archive" }
 Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $DependencyPath $dependency.name) -Force
}
Write-Output "Verified portable dependencies ready: $DependencyPath"
