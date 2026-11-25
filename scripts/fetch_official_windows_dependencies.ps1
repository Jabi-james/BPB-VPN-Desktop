$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$release = "build/windows/x64/runner/Release"
if (!(Test-Path $release)) { throw "Windows release directory not found: $release" }
New-Item -ItemType Directory -Force $env:RUNNER_TEMP | Out-Null

function Get-OfficialTorBundle {
  Write-Host "Resolving the current stable Tor Expert Bundle for Windows x86_64..."
  $page = Invoke-WebRequest -Uri "https://download.torproject.org/tor/" -UseBasicParsing
  $matches = [regex]::Matches($page.Content, 'href\s*=\s*["''](?<url>[^"'']*tor-expert-bundle-windows-x86_64-[^"'']+\.tar\.gz)["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $url = $null
  foreach ($match in $matches) {
    $candidate = [uri]::new([uri]"https://download.torproject.org/tor/", $match.Groups["url"].Value).AbsoluteUri
    if ($candidate -match 'tor-expert-bundle-windows-x86_64-(?<version>\d+\.\d+(?:\.\d+)?(?:\.\d+)?)\.tar\.gz$') {
      $url = $candidate
      $version = $Matches.version
      break
    }
  }
  if (!$url) { throw "Could not locate a stable Windows x86_64 Tor Expert Bundle link on the official Tor page." }

  $archive = Join-Path $env:RUNNER_TEMP ([uri]$url).Segments[-1]
  $signature = "$archive.asc"
  Invoke-WebRequest -Uri $url -OutFile $archive
  Invoke-WebRequest -Uri "$url.asc" -OutFile $signature
  if (!(Test-Path $archive) -or (Get-Item $archive).Length -lt 1MB) { throw "Tor Expert Bundle download is missing or unexpectedly small." }

  $gpg = Get-Command gpg -ErrorAction SilentlyContinue
  if (!$gpg) {
    choco install gnupg --no-progress -y
    $gpg = Get-Command gpg -ErrorAction Stop
  }
  $home = Join-Path $env:RUNNER_TEMP "tor-gpg-home"
  New-Item -ItemType Directory -Force $home | Out-Null
  $key = Join-Path $env:RUNNER_TEMP "tor-signing-key.asc"
  Invoke-WebRequest -Uri "https://keys.openpgp.org/vks/v1/by-fingerprint/EF6E286DDA85EA2A4BA7DE684E2C6E8793298290" -OutFile $key
  $keyInfo = & $gpg.Source --homedir $home --batch --with-colons --show-keys $key 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Unable to inspect the official Tor signing key." }
  $fingerprints = @($keyInfo | Where-Object { $_ -match '^fpr:' } | ForEach-Object { ($_ -split ':')[9] })
  if ($fingerprints -notcontains "EF6E286DDA85EA2A4BA7DE684E2C6E8793298290") { throw "Tor signing key fingerprint mismatch." }
  & $gpg.Source --homedir $home --batch --import $key
  if ($LASTEXITCODE -ne 0) { throw "Unable to import the official Tor signing key." }
  $verify = & $gpg.Source --homedir $home --batch --status-fd 1 --verify $signature $archive 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Tor Expert Bundle signature verification failed: $verify" }
  $valid = @($verify | Where-Object { $_ -match '^\[GNUPG:\] VALIDSIG ' })
  if (!$valid -or $valid[-1] -notmatch 'EF6E286DDA85EA2A4BA7DE684E2C6E8793298290') { throw "Tor signature is not rooted in the pinned Tor Browser Developers key." }

  $extract = Join-Path $env:RUNNER_TEMP "tor-expert"
  New-Item -ItemType Directory -Force $extract | Out-Null
  tar -xzf $archive -C $extract
  $tor = Join-Path $extract "tor/tor.exe"
  $pt = Join-Path $extract "tor/pluggable_transports/lyrebird.exe"
  $geoip = Join-Path $extract "data/geoip"
  $geoip6 = Join-Path $extract "data/geoip6"
  $ptConfig = Join-Path $extract "tor/pluggable_transports/pt_config.json"
  foreach ($file in @($tor, $pt, $geoip, $geoip6, $ptConfig)) {
    if (!(Test-Path $file)) { throw "Expected Tor bundle file missing: $file" }
  }
  $dest = Join-Path $release "tor"
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item $tor (Join-Path $dest "tor.exe") -Force
  Copy-Item $pt (Join-Path $dest "lyrebird.exe") -Force
  Copy-Item $geoip (Join-Path $dest "geoip") -Force
  Copy-Item $geoip6 (Join-Path $dest "geoip6") -Force
  Copy-Item $ptConfig (Join-Path $dest "pt_config.json") -Force
  Write-Host "Verified and packaged Tor Expert Bundle $version (Windows x86_64)."
}

function Get-OfficialAether {
  Write-Host "Resolving the latest stable Aether Windows x86_64 release..."
  $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/CluvexStudio/Aether/releases?per_page=100" -Headers @{ "Accept" = "application/vnd.github+json"; "User-Agent" = "BPB-VPN-Desktop-Build" }
  $releaseInfo = $releases | Where-Object { !$_.draft -and !$_.prerelease } | Sort-Object { [datetime]$_.published_at } -Descending | Select-Object -First 1
  if (!$releaseInfo) { throw "No stable Aether release was found." }
  $asset = $releaseInfo.assets | Where-Object { $_.name -eq "aether-windows-x86_64.zip" } | Select-Object -First 1
  if (!$asset -or !$asset.digest -or $asset.digest -notmatch '^sha256:[0-9a-fA-F]{64}$') { throw "Latest Aether release has no Windows x86_64 asset with a GitHub SHA-256 digest." }
  $archive = Join-Path $env:RUNNER_TEMP $asset.name
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive
  $expected = $asset.digest.Substring(7).ToLowerInvariant()
  $actual = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $expected) { throw "Aether archive SHA-256 mismatch: expected $expected, got $actual" }
  $extract = Join-Path $env:RUNNER_TEMP "aether"
  Expand-Archive -Path $archive -DestinationPath $extract -Force
  $binary = Join-Path $extract "aether.exe"
  $pt = Join-Path $extract "pt"
  $licenses = Join-Path $extract "LICENSES"
  foreach ($path in @($binary, $pt, $licenses)) {
    if (!(Test-Path $path)) { throw "Expected Aether bundle item missing: $path" }
  }
  $dest = Join-Path $release "aether"
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item $binary (Join-Path $dest "aether.exe") -Force
  Copy-Item -Recurse $pt (Join-Path $dest "pt") -Force
  Copy-Item -Recurse $licenses (Join-Path $dest "LICENSES") -Force
  @"
Aether $($releaseInfo.tag_name)
Source: https://github.com/CluvexStudio/Aether
License: AGPL-3.0-only
Third-party license texts and notices are in the LICENSES directory.
"@ | Set-Content -Path (Join-Path $dest "NOTICE.txt") -Encoding utf8
  Write-Host "Verified and packaged Aether $($releaseInfo.tag_name); SHA-256 $actual."
}

function Get-OfficialWintun {
  Write-Host "Resolving the newest Wintun build from the official builds directory..."
  $page = Invoke-WebRequest -Uri "https://www.wintun.net/builds/" -UseBasicParsing
  $entries = @()
  foreach ($match in [regex]::Matches($page.Content, 'href\s*=\s*["''](?<file>wintun-(?<version>\d+\.\d+(?:\.\d+)+)\.zip)["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    $entries += [pscustomobject]@{ Version = [version]$match.Groups["version"].Value; Name = $match.Groups["file"].Value }
  }
  $latest = $entries | Sort-Object Version -Descending | Select-Object -First 1
  if (!$latest) { throw "Could not find a versioned Wintun ZIP on the official builds page." }
  $url = "https://www.wintun.net/builds/$($latest.Name)"
  $archive = Join-Path $env:RUNNER_TEMP $latest.Name
  Invoke-WebRequest -Uri $url -OutFile $archive
  if (!(Test-Path $archive) -or (Get-Item $archive).Length -lt 100KB) { throw "Wintun archive download is missing or unexpectedly small." }
  $extract = Join-Path $env:RUNNER_TEMP "wintun"
  Expand-Archive -Path $archive -DestinationPath $extract -Force
  $dll = Join-Path $extract "wintun/bin/amd64/wintun.dll"
  $license = Join-Path $extract "wintun/LICENSE.txt"
  foreach ($path in @($dll, $license)) { if (!(Test-Path $path)) { throw "Expected Wintun item missing: $path" } }
  $signature = Get-AuthenticodeSignature -FilePath $dll
  if ($signature.Status -ne "Valid" -or !$signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'WireGuard') {
    throw "Wintun DLL Authenticode signature is invalid or is not issued to the WireGuard publisher."
  }
  Copy-Item $dll (Join-Path $release "wintun.dll") -Force
  Copy-Item $license (Join-Path $release "LICENSE-Wintun.txt") -Force
  Write-Host "Verified and packaged Wintun $($latest.Version) (AMD64); signer: $($signature.SignerCertificate.Subject)."
}

Get-OfficialTorBundle
Get-OfficialAether
Get-OfficialWintun

$psiphonGoMod = Get-Content "psiphon/go.mod" -Raw
$toolchainMatch = [regex]::Match($psiphonGoMod, '(?m)^toolchain\s+(go[0-9.]+)\s*$')
if (!$toolchainMatch.Success) { throw "Psiphon go.mod does not declare its tested Go toolchain." }
"Psiphon Go toolchain: $($toolchainMatch.Groups[1].Value)"
