#!/bin/sh
# DJI 4G Manager release packaging script
#
# Local test package (default):
#   ./scripts/package-release.sh
#
# Official distribution (requires Apple Developer ID certificate):
#   IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-release.sh
#
# Notarization (requires developer account):
#   xcrun notarytool submit dist/DJI4GManager-Release/DJI4GManager-Release.zip \
#     --keychain-profile "notary" --wait
#   xcrun stapler staple dist/DJI4GManager-Release/DJI4GManager-Release.zip
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-Release}
IDENTITY=${IDENTITY:--}
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIGURATION/DJI4GManager.app"
OUT="$ROOT/dist/DJI4GManager-$CONFIGURATION"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Building $CONFIGURATION"
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
  -project "$ROOT/DJI4GManager.xcodeproj" \
  -scheme DJI4GManager \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  MACOSX_DEPLOYMENT_TARGET=15.0 \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "==> Copying app"
cp -R "$APP" "$OUT/"

echo "==> Signing (${IDENTITY})"
codesign --force --deep --sign "${IDENTITY}" "$OUT/DJI4GManager.app"

cd "$OUT"
zip -rq "DJI4GManager-$CONFIGURATION.zip" DJI4GManager.app
shasum -a 256 "DJI4GManager-$CONFIGURATION.zip" > "DJI4GManager-$CONFIGURATION.zip.sha256"

echo "==> Done: $OUT/DJI4GManager-$CONFIGURATION.zip"
cat "DJI4GManager-$CONFIGURATION.zip.sha256"
