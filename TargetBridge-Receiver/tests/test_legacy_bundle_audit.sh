#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDITOR="$SCRIPT_DIR/../scripts/verify_legacy_receiver_bundle.sh"
TEMP_DIR="$(mktemp -d)"
HOST_ARCH="$(uname -m)"
if [[ "$HOST_ARCH" == "arm64" ]]; then
  OTHER_ARCH="x86_64"
else
  OTHER_ARCH="arm64"
fi
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_bundle() {
  local name="$1"
  local min_os="$2"
  local arch="$3"
  local imports_legacy_symbol="$4"
  local app="$TEMP_DIR/$name.app"
  local source="$TEMP_DIR/$name.c"
  mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.targetbridge.intel-receiver-legacy</string>
<key>LSMinimumSystemVersion</key><string>11.0</string>
</dict></plist>
EOF
  if [[ "$imports_legacy_symbol" == "yes" ]]; then
    cat > "$source" <<'EOF'
extern void CVBufferCopyAttachments(void);
int main(void) { CVBufferCopyAttachments(); return 0; }
EOF
    /usr/bin/clang -arch "$arch" -mmacosx-version-min="$min_os" \
      -Wl,-undefined,dynamic_lookup "$source" \
      -o "$app/Contents/MacOS/TargetBridgeReceiver"
  else
    cat > "$source" <<'EOF'
int main(void) { return 0; }
EOF
    /usr/bin/clang -arch "$arch" -mmacosx-version-min="$min_os" \
      "$source" -o "$app/Contents/MacOS/TargetBridgeReceiver"
  fi
  printf '%s' "$app"
}

valid_bundle="$(make_bundle valid 11.0 "$HOST_ARCH" no)"
"$AUDITOR" "$valid_bundle" "$HOST_ARCH" 11.0

too_new_bundle="$(make_bundle too-new 14.0 "$HOST_ARCH" no)"
if "$AUDITOR" "$too_new_bundle" "$HOST_ARCH" 11.0; then
  fail "accepted a Mach-O targeting macOS 14"
fi

wrong_arch_bundle="$(make_bundle wrong-arch 11.0 "$OTHER_ARCH" no)"
if "$AUDITOR" "$wrong_arch_bundle" "$HOST_ARCH" 11.0; then
  fail "accepted a bundle without the requested architecture"
fi

symbol_bundle="$(make_bundle old-symbol 11.0 "$HOST_ARCH" yes)"
if "$AUDITOR" "$symbol_bundle" "$HOST_ARCH" 11.0; then
  fail "accepted the unavailable Big Sur CoreVideo import"
fi

external_bundle="$TEMP_DIR/external-dependency.app"
mkdir -p "$external_bundle/Contents/MacOS" "$external_bundle/Contents/Frameworks"
cp "$valid_bundle/Contents/Info.plist" "$external_bundle/Contents/Info.plist"
cat > "$TEMP_DIR/dependency.c" <<'EOF'
int legacy_audit_dependency(void) { return 0; }
EOF
cat > "$TEMP_DIR/external-main.c" <<'EOF'
extern int legacy_audit_dependency(void);
int main(void) { return legacy_audit_dependency(); }
EOF
/usr/bin/clang -dynamiclib -arch "$HOST_ARCH" -mmacosx-version-min=11.0 \
  -install_name /opt/homebrew/lib/liblegacy-audit.dylib \
  "$TEMP_DIR/dependency.c" -o "$TEMP_DIR/liblegacy-audit.dylib"
/usr/bin/clang -arch "$HOST_ARCH" -mmacosx-version-min=11.0 \
  "$TEMP_DIR/external-main.c" "$TEMP_DIR/liblegacy-audit.dylib" \
  -o "$external_bundle/Contents/MacOS/TargetBridgeReceiver"
cp "$TEMP_DIR/liblegacy-audit.dylib" "$external_bundle/Contents/Frameworks/"
if "$AUDITOR" "$external_bundle" "$HOST_ARCH" 11.0; then
  fail "accepted a dependency still linked from Homebrew outside the app"
fi

rpath_bundle="$TEMP_DIR/external-runpath.app"
mkdir -p "$rpath_bundle/Contents/MacOS" "$rpath_bundle/Contents/Frameworks"
cp "$valid_bundle/Contents/Info.plist" "$rpath_bundle/Contents/Info.plist"
/usr/bin/clang -dynamiclib -arch "$HOST_ARCH" -mmacosx-version-min=11.0 \
  -install_name @rpath/liblegacy-audit.dylib \
  "$TEMP_DIR/dependency.c" -o "$TEMP_DIR/liblegacy-audit.dylib"
/usr/bin/clang -arch "$HOST_ARCH" -mmacosx-version-min=11.0 \
  -Wl,-rpath,/opt/homebrew/lib "$TEMP_DIR/external-main.c" \
  "$TEMP_DIR/liblegacy-audit.dylib" \
  -o "$rpath_bundle/Contents/MacOS/TargetBridgeReceiver"
cp "$TEMP_DIR/liblegacy-audit.dylib" "$rpath_bundle/Contents/Frameworks/"
if "$AUDITOR" "$rpath_bundle" "$HOST_ARCH" 11.0; then
  fail "accepted a Homebrew runpath outside the app"
fi

echo "PASS: legacy Receiver bundle audit accepts compatible fixtures and rejects incompatible ones."
