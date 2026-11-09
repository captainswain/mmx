# Discover licensed release CRT binaries for app-local deployment, never DebugCRT.
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Visual Studio C++ installation not found' }
$versions = Get-ChildItem (Join-Path $installation 'VC/Redist/MSVC') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending
$runtime = $null
foreach ($version in $versions) {
    $runtime = Get-ChildItem (Join-Path $version.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($runtime) { break }
}
if (-not $runtime) { throw 'Redistributable x64 CRT directory not found' }
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll')) {
    if (-not (Test-Path (Join-Path $runtime.FullName $name))) { throw "Missing $name" }
}
$env:MMX_WINDOWS_CRT_DIR = $runtime.FullName
if ($env:GITHUB_ENV) { "MMX_WINDOWS_CRT_DIR=$($runtime.FullName)" >> $env:GITHUB_ENV }
Write-Output "Using x64 release CRT: $($runtime.FullName)"
