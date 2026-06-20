#!/bin/bash
# Build the app and zip it for distribution (e.g. a GitHub Release asset).
# Uses ditto so the bundle, signature, and metadata survive the round-trip.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

cd build
ZIP="HEIC-to-Resolve.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "HEIC to Resolve.app" "$ZIP"

echo "==> Packaged: build/$ZIP"
shasum -a 256 "$ZIP"
