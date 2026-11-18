#!/usr/bin/env bash
# Fetches Xray routing data from the latest Chocolate4U/Iran-v2ray-rules release.
# The same SHA-256 files are used by GeoAssetsDownloader at runtime.
set -euo pipefail
cd "$(dirname "$0")"

BASE=https://github.com/Chocolate4U/Iran-v2ray-rules/releases/latest/download
ASSETS=../android/app/src/main/assets
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$ASSETS"
for f in geoip.dat geosite.dat; do
  curl -fsSL --retry 3 -o "$TMP/$f.sha256sum" "$BASE/$f.sha256sum"
  curl -fsSL --retry 3 -o "$TMP/$f" "$BASE/$f"
  (
    cd "$TMP"
    sha256sum --check "$f.sha256sum"
  )
  install -m 0644 "$TMP/$f" "$ASSETS/$f"
done

test -s "$ASSETS/geoip.dat"
test -s "$ASSETS/geosite.dat"
ls -lh "$ASSETS/geoip.dat" "$ASSETS/geosite.dat"
