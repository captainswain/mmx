# Sign build executables before packaging, then the installer after packaging.
param([Parameter(Mandatory=$true)][string[]]$Paths)
$ErrorActionPreference = 'Stop'
if (-not $env:MMX_CERT_THUMBPRINT -or -not $env:MMX_TIMESTAMP_URL) {
  throw 'Set MMX_CERT_THUMBPRINT and MMX_TIMESTAMP_URL on the signing host.'
}
$tool = Get-Command signtool.exe -ErrorAction SilentlyContinue
if (-not $tool) { throw 'Add the Windows SDK signtool.exe directory to PATH.' }
foreach ($path in $Paths) {
  & $tool.Source sign /sha1 $env:MMX_CERT_THUMBPRINT /fd SHA256 /tr $env:MMX_TIMESTAMP_URL /td SHA256 $path
  if ($LASTEXITCODE -ne 0) { throw "Signing failed: $path" }
  & $tool.Source verify /pa $path
  if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $path" }
  Get-FileHash -Algorithm SHA256 $path | Format-List
}
