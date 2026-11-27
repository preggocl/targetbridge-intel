#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
MODE="${1:-}"
if [[ -n "$MODE" && "$MODE" != "--legacy" ]]; then
  echo "Usage: $0 [--legacy]" >&2
  exit 2
fi

if [[ "$MODE" == "--legacy" ]]; then
  BUILD_DIR="${REPO_ROOT}/build-legacy"
  APP_NAME="TargetBridge Intel Receiver Legacy"
  APP_ID="com.targetbridge.intel-receiver-legacy"
  APP_VERSION="${APP_VERSION:-3.3.0}"
  MIN_OS="11.0"
else
  BUILD_DIR="${REPO_ROOT}/build"
  APP_NAME="TargetBridge Receiver"
  APP_ID="com.targetbridge.receiver"
  APP_VERSION="${APP_VERSION:-3.3.0}"
  MIN_OS="11.0"
fi
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
BIN_NAME="TargetBridgeReceiver"
STAMP="$(date +%Y%m%d%H%M%S)"
ARCH="$(uname -m)"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "arm64" ]]; then
  echo "Unsupported Receiver architecture: $ARCH" >&2
  exit 1
fi
ICONSET_DIR="$(mktemp -d)"
ICON_FILE="${ROOT}/TargetBridgeAssets/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
ICNS_PATH="${APP_DIR}/Contents/Resources/TargetBridgeReceiver.icns"

cd "$ROOT/TBReceiverC"
make clean
make APP_VERSION="${APP_VERSION}" APP_BUILD="$STAMP" ARCH="$ARCH" MACOSX_DEPLOYMENT_TARGET="$MIN_OS"

mkdir -p "$BUILD_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Resources/Languages"

cp "$ROOT/TBReceiverC/tbreceiver" "$APP_DIR/Contents/MacOS/$BIN_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$BIN_NAME"
cp "$REPO_ROOT/TargetBridge-Shared/Languages/"*.json "$APP_DIR/Contents/Resources/Languages/"

# Bundle dylib dependencies (ffmpeg and SDL) inside the .app.
# Homebrew's SDL2 is currently sdl2-compat, which loads SDL3 at runtime via
# dlopen. dylibbundler cannot discover that dynamic dependency, so copy it
# explicitly to keep the released receiver self-contained.
mkdir -p "$APP_DIR/Contents/Frameworks"
if ! command -v dylibbundler &>/dev/null; then
  if [[ "$MODE" == "--legacy" ]]; then
    echo "dylibbundler is required; install it explicitly before building the legacy bundle." >&2
    exit 1
  fi
  echo "Installing dylibbundler..."
  brew install dylibbundler
fi
dylibbundler -od -b \
  -x "$APP_DIR/Contents/MacOS/$BIN_NAME" \
  -d "$APP_DIR/Contents/Frameworks/" \
  -p @executable_path/../Frameworks/ \
  >/dev/null 2>&1

SDL3_DYLIB="$(brew --prefix sdl3)/lib/libSDL3.dylib"
if [[ ! -f "$SDL3_DYLIB" ]]; then
  echo "SDL3 runtime library not found: $SDL3_DYLIB" >&2
  exit 1
fi
cp -L "$SDL3_DYLIB" "$APP_DIR/Contents/Frameworks/libSDL3.dylib"

if [[ -f "$ICON_FILE" ]]; then
  mkdir -p "${ICONSET_DIR}/TargetBridgeReceiver.iconset"
  sips -z 16 16     "$ICON_FILE" --out "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_FILE" --out "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_FILE" --out "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_FILE" --out "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_FILE" --out "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_FILE" --out "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_FILE" --out "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_FILE" --out "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_FILE" --out "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_512x512.png" >/dev/null
  cp "$ICON_FILE" "${ICONSET_DIR}/TargetBridgeReceiver.iconset/icon_512x512@2x.png"
  iconutil -c icns "${ICONSET_DIR}/TargetBridgeReceiver.iconset" -o "$ICNS_PATH" >/dev/null 2>&1 || true
fi

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>${APP_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>TargetBridgeReceiver</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>$STAMP</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_OS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
if [[ "$MODE" == "--legacy" ]]; then
  "$SCRIPT_DIR/verify_legacy_receiver_bundle.sh" "$APP_DIR" "$ARCH" "$MIN_OS"
fi
# Sign each bundled dylib first, then the app
if [[ "$MODE" == "--legacy" ]]; then
  while IFS= read -r -d '' dylib; do
    codesign --force --sign - "$dylib"
  done < <(find "$APP_DIR/Contents/Frameworks" -name "*.dylib" -print0)
  codesign --force --deep --sign - "$APP_DIR"
else
  find "$APP_DIR/Contents/Frameworks" -name "*.dylib" | while read dylib; do
    codesign --force --sign - "$dylib" >/dev/null 2>&1 || true
  done
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi
xattr -cr "$APP_DIR" >/dev/null 2>&1 || true
if [[ "$MODE" == "--legacy" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi
rm -rf "$ICONSET_DIR"

echo "${APP_NAME} built: $APP_DIR"
echo "Version: ${APP_VERSION} ($STAMP)"
echo "Build architecture: $ARCH"
