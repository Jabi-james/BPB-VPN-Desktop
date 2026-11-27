#!/usr/bin/env bash
# Fetch Xray routing data from the same source used by Firefox Spider VPN.
# Like Spider, validate the downloaded protobuf files before replacing the
# currently installed assets. Full tag/content validation runs in geo_assets_test.dart.
set -euo pipefail
cd "$(dirname "$0")"

BASE="https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release"
ASSETS="../android/app/src/main/assets"
MAX_BYTES=$((64 * 1024 * 1024))
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$ASSETS"

# Download both files first. A network failure must not leave a mixed pair.
for f in geoip.dat geosite.dat; do
  curl --fail --location --silent --show-error --retry 3 \
    --output "$TMP/$f" "$BASE/$f"
  size="$(wc -c < "$TMP/$f" | tr -d '[:space:]')"
  if [ "$size" -le 0 ] || [ "$size" -gt "$MAX_BYTES" ]; then
    echo "Invalid size for $f: $size bytes (limit: $MAX_BYTES)" >&2
    exit 1
  fi
done

# Replace only after both downloads completed. The Dart test immediately after
# this step validates protobuf structure and the tags referenced by BPB.
for f in geoip.dat geosite.dat; do
  install -m 0644 "$TMP/$f" "$ASSETS/.$f.tmp"
done
mv -f "$ASSETS/.geoip.dat.tmp" "$ASSETS/geoip.dat"
mv -f "$ASSETS/.geosite.dat.tmp" "$ASSETS/geosite.dat"

test -s "$ASSETS/geoip.dat"
test -s "$ASSETS/geosite.dat"
printf 'iran\\n' > "$ASSETS/geo-country.txt"
ls -lh "$ASSETS/geoip.dat" "$ASSETS/geosite.dat" "$ASSETS/geo-country.txt"
