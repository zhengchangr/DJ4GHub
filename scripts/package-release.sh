#!/bin/sh
# DJ4G Hub release packaging script
#
# Local test package (default):
#   ./scripts/package-release.sh
#
# Official distribution (requires Apple Developer ID certificate):
#   IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-release.sh
#
# Notarization (requires developer account):
#   xcrun notarytool submit dist/DJ4GHub-Release/DJ4GHub-Release.zip \
#     --keychain-profile "notary" --wait
#   xcrun stapler staple dist/DJ4GHub-Release/DJ4GHub-Release.zip
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-Release}
IDENTITY=${IDENTITY:--}
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIGURATION/DJ4GHub.app"
OUT="$ROOT/dist/DJ4GHub-$CONFIGURATION"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Building $CONFIGURATION"
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
  -project "$ROOT/DJ4GHub.xcodeproj" \
  -scheme DJ4GHub \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  MACOSX_DEPLOYMENT_TARGET=15.0 \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "==> Copying app"
cp -R "$APP" "$OUT/"

echo "==> Signing (${IDENTITY})"
codesign --force --deep --sign "${IDENTITY}" "$OUT/DJ4GHub.app"

cd "$OUT"
zip -rq "DJ4GHub-$CONFIGURATION.zip" DJ4GHub.app
shasum -a 256 "DJ4GHub-$CONFIGURATION.zip" > "DJ4GHub-$CONFIGURATION.zip.sha256"

echo "==> Done: $OUT/DJ4GHub-$CONFIGURATION.zip"
cat "DJ4GHub-$CONFIGURATION.zip.sha256"
