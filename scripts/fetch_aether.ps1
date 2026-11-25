param(
  [Parameter(Mandatory = $true)][string]$ReleaseDirectory,
  [Parameter(Mandatory = $true)][string]$TempDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
New-Item -ItemType Directory -Force $TempDirectory, $ReleaseDirectory | Out-Null

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Invoke-VerifiedDownload([string]$Url, [string]$Path, [string]$ExpectedHash) {
  Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  Invoke-WebRequest -Uri $Url -OutFile $Path
  $actual = Get-Sha256 $Path
  if ($actual -ne $ExpectedHash.ToLowerInvariant()) { throw "SHA-256 mismatch for $Url. Expected $ExpectedHash, got $actual" }
}
function Test-AetherPackage([string]$Directory) {
  $exe = Join-Path $Directory "aether.exe"
  foreach ($required in @($exe, (Join-Path $Directory "pt"), (Join-Path $Directory "LICENSES"))) {
    if (!(Test-Path -LiteralPath $required)) { throw "Aether package item missing: $required" }
  }
  $help = (& $exe --help 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) { throw "Aether --help exited with code $LASTEXITCODE" }
  foreach ($flag in @("--masque", "--wg", "--scan", "--bind", "--upstream", "--stats")) {
    if ($help -notmatch [regex]::Escape($flag)) { throw "Aether compatibility check failed: required CLI option $flag is missing" }
  }
}
function Install-Aether([string]$Version, [string]$Hash, [string]$Source) {
  $archive = Join-Path $tempRoot "aether-$Version.zip"
  $url = "https://github.com/CluvexStudio/Aether/releases/download/$Version/aether-windows-x86_64.zip"
  Invoke-VerifiedDownload $url $archive $Hash
  $extract = Join-Path $tempRoot "aether-$Version"
  Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
  Test-AetherPackage $extract
  $dest = Join-Path $release "aether"
  Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item (Join-Path $extract "aether.exe") (Join-Path $dest "aether.exe")
  Copy-Item -Recurse (Join-Path $extract "pt") (Join-Path $dest "pt")
  Copy-Item -Recurse (Join-Path $extract "LICENSES") (Join-Path $dest "LICENSES")
  @"
Aether $Version
Source: https://github.com/CluvexStudio/Aether
License: AGPL-3.0-only
Third-party license texts and notices are in the LICENSES directory.
"@ | Set-Content -Path (Join-Path $dest "NOTICE.txt") -Encoding utf8
  Write-Host "Aether $Version accepted ($Source); checksum and required CLI options verified."
}
$aetherInstalled = $false
try {
  $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/CluvexStudio/Aether/releases/latest"
  if ($latest.draft -or $latest.prerelease -or $latest.tag_name -notmatch '^v\d+\.\d+\.\d+$') { throw "Latest Aether release is not a stable semantic version." }
  $asset = @($latest.assets | Where-Object { $_.name -eq "aether-windows-x86_64.zip" }) | Select-Object -First 1
  if (!$asset -or $asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw "Latest Aether release has no Windows x64 archive with a SHA-256 digest." }
  Install-Aether $latest.tag_name $Matches[1] "latest stable release"
  $aetherInstalled = $true
} catch { Write-Warning "Latest Aether release rejected or unavailable: $($_.Exception.Message)" }
if (!$aetherInstalled) {
  Install-Aether "v2.4.0" "21b1444628d37121e873878e2eddd7932215418af1a2a12470caee5809026f1a" "last known-good fallback"
}

