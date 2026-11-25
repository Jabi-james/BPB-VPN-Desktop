$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$release = "build/windows/x64/runner/Release"
$tempRoot = Join-Path $env:RUNNER_TEMP "bpb-dependencies"
New-Item -ItemType Directory -Force $tempRoot, $release | Out-Null

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Invoke-VerifiedDownload([string]$Url, [string]$Path, [string]$ExpectedHash) {
  Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  Invoke-WebRequest -Uri $Url -OutFile $Path
  $actual = Get-Sha256 $Path
  if ($actual -ne $ExpectedHash.ToLowerInvariant()) { throw "SHA-256 mismatch for $Url. Expected $ExpectedHash, got $actual" }
}
# Aether is the only independently maintained VPN engine in this desktop port.
# Keep its release validation isolated from BPB-managed and Windows runtime assets.
& (Join-Path $PSScriptRoot "fetch_aether.ps1") -ReleaseDirectory $release -TempDirectory $tempRoot
if ($LASTEXITCODE -ne 0) { throw "Aether dependency validation failed with exit code $LASTEXITCODE" }

function Get-LatestTorStableVersion {
  $index = (Invoke-WebRequest -Uri "https://dist.torproject.org/torbrowser/").Content
  $versions = @([regex]::Matches($index, 'href="(\d+\.\d+\.\d+)/"') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending)
  if ($versions.Count -eq 0) { throw "No stable Tor Browser release directory was found." }
  return $versions[0].ToString()
}
function Get-TorArchiveHash([string]$Version, [string]$ArchiveName) {
  $url = "https://dist.torproject.org/torbrowser/$Version/sha256sums-signed-build.txt"
  $sumText = (Invoke-WebRequest -Uri $url).Content
  foreach ($line in ($sumText -split "\r?\n")) {
    if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') {
      $listedName = $Matches[2].Trim().TrimStart("./")
      if ($listedName -eq $ArchiveName -or $listedName.EndsWith("/$ArchiveName")) { return $Matches[1].ToLowerInvariant() }
    }
  }
  throw "The official signed-build checksum list for Tor $Version does not contain $ArchiveName."
}
function Test-TorPackage([string]$Directory) {
  $tor = Join-Path $Directory "tor/tor.exe"
  $lyrebird = Join-Path $Directory "tor/pluggable_transports/lyrebird.exe"
  $geoip = Join-Path $Directory "data/geoip"
  $geoip6 = Join-Path $Directory "data/geoip6"
  $ptConfig = Join-Path $Directory "tor/pluggable_transports/pt_config.json"
  foreach ($path in @($tor, $lyrebird, $geoip, $geoip6, $ptConfig)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Tor package item missing: $path" }
  }
  $versionOutput = (& $tor --version 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch 'Tor') { throw "Tor executable version check failed." }
  $options = (& $tor --list-torrc-options 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) { throw "Tor option compatibility check failed." }
  # Tor's own command-line tests check this output by searching for each option
  # name, rather than requiring it to occupy an otherwise-empty line. Keep the
  # same tolerant matching so harmless output formatting cannot reject a valid build.
  foreach ($option in @("ClientTransportPlugin", "GeoIPFile", "GeoIPv6File", "ControlPort", "CookieAuthentication")) {
    if ($options -notmatch "(?i)\b$([regex]::Escape($option))\b") {
      $sample = ($options -split "\r?\n" | Select-Object -First 30) -join " | "
      throw "Tor compatibility check failed: required option $option is missing from --list-torrc-options output. First output lines: $sample"
    }
  }
  $config = Get-Content -LiteralPath $ptConfig -Raw | ConvertFrom-Json
  # Tor Browser changed pt_config.json in November 2026: transport definitions
  # now live under "transports", while built-in bridge lists are generated
  # separately and may not include every supported transport. Older bundles
  # expose the ClientTransportPlugin commands under "pluggableTransports".
  $supportedTransports = @()
  $transportsProperty = $config.PSObject.Properties["transports"]
  $legacyProperty = $config.PSObject.Properties["pluggableTransports"]
  if ($null -ne $transportsProperty -and $null -ne $transportsProperty.Value) {
    foreach ($transport in $transportsProperty.Value.PSObject.Properties) {
      $protocolsProperty = $transport.Value.PSObject.Properties["protocols"]
      if ($null -ne $protocolsProperty) {
        $supportedTransports += @($protocolsProperty.Value | ForEach-Object { [string]$_ })
      }
    }
  } elseif ($null -ne $legacyProperty -and $null -ne $legacyProperty.Value) {
    $legacy = $legacyProperty.Value
    if ($legacy -is [System.Collections.IDictionary] -or $legacy -is [pscustomobject]) {
      foreach ($transport in $legacy.PSObject.Properties) {
        $supportedTransports += [string]$transport.Value
      }
    } else {
      $supportedTransports += @($legacy | ForEach-Object { [string]$_ })
    }
  } else {
    throw "Tor pt_config.json contains neither transports nor pluggableTransports definitions."
  }
  foreach ($transport in @("obfs4", "snowflake", "webtunnel")) {
    $supported = @($supportedTransports | Where-Object { $_ -match "(?i)\b$([regex]::Escape($transport))\b" })
    if ($supported.Count -eq 0) { throw "Tor pluggable transport configuration does not support $transport." }
  }
}
function Install-Tor([string]$Version, [string]$ExpectedHash, [string]$Source) {
  $name = "tor-expert-bundle-windows-x86_64-$Version.tar.gz"
  $url = "https://dist.torproject.org/torbrowser/$Version/$name"
  $archive = Join-Path $tempRoot $name
  Invoke-VerifiedDownload $url $archive $ExpectedHash
  $extract = Join-Path $tempRoot "tor-$Version"
  Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $extract | Out-Null
  & tar -xzf $archive -C $extract
  if ($LASTEXITCODE -ne 0) { throw "Could not extract Tor $Version archive." }
  Test-TorPackage $extract
  $torDir = Join-Path $release "tor"
  Remove-Item -LiteralPath $torDir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $torDir | Out-Null
  Copy-Item (Join-Path $extract "tor/tor.exe") (Join-Path $torDir "tor.exe")
  Copy-Item (Join-Path $extract "tor/pluggable_transports/lyrebird.exe") (Join-Path $torDir "lyrebird.exe")
  Copy-Item (Join-Path $extract "data/geoip") (Join-Path $torDir "geoip")
  Copy-Item (Join-Path $extract "data/geoip6") (Join-Path $torDir "geoip6")
  Copy-Item (Join-Path $extract "tor/pluggable_transports/pt_config.json") (Join-Path $torDir "pt_config.json")
  Write-Host "Tor Expert Bundle $Version accepted ($Source); checksum, executable and required options verified."
}
$torInstalled = $false
try {
  $torVersion = Get-LatestTorStableVersion
  $torName = "tor-expert-bundle-windows-x86_64-$torVersion.tar.gz"
  $torHash = Get-TorArchiveHash $torVersion $torName
  Install-Tor $torVersion $torHash "latest stable release and official signed-build checksum list"
  $torInstalled = $true
} catch { Write-Warning "Latest Tor bundle rejected or unavailable: $($_.Exception.Message)" }
if (!$torInstalled) {
  Install-Tor "16.0.3" "b70cabe2b93b5b1fd144466e42afaabe7a1a470228912657b3b5776e9cb7a9f1" "last known-good fallback"
}

# Wintun has no supported machine-readable stable-release endpoint. Keep its known-good
# version pinned until the vendor publishes a verifiable release feed; never guess a URL.
$wintunArchive = Join-Path $tempRoot "wintun-0.14.1.zip"
Invoke-VerifiedDownload "https://www.wintun.net/builds/wintun-0.14.1.zip" $wintunArchive "07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51"
$wintunExtract = Join-Path $tempRoot "wintun"
Remove-Item -LiteralPath $wintunExtract -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $wintunArchive -DestinationPath $wintunExtract -Force
$dll = Join-Path $wintunExtract "wintun/bin/amd64/wintun.dll"
$license = Join-Path $wintunExtract "wintun/LICENSE.txt"
foreach ($path in @($dll, $license)) {
  if (!(Test-Path -LiteralPath $path)) { throw "Wintun package item missing: $path" }
}
Copy-Item $dll (Join-Path $release "wintun.dll")
Copy-Item $license (Join-Path $release "LICENSE-Wintun.txt")
Write-Host "Wintun 0.14.1 accepted; official archive checksum and x64 runtime files verified."

$configSource = "android/app/src/main/assets/psiphon_config.json"
$configDest = Join-Path $release "psiphon_config.json"
if (!(Test-Path -LiteralPath $configSource)) { throw "Psiphon configuration asset missing: $configSource" }
Copy-Item $configSource $configDest -Force
Write-Host "Tor, Wintun and Psiphon runtime assets were validated and staged; Aether was validated separately."
