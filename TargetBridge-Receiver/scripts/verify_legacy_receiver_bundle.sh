#!/bin/bash
set -euo pipefail

APP_DIR="${1:?Usage: verify_legacy_receiver_bundle.sh APP_PATH [ARCH] [MIN_OS]}"
EXPECTED_ARCH="${2:-$(uname -m)}"
REQUIRED_MIN_OS="${3:-11.0}"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/TargetBridgeReceiver"

if [[ ! -d "$APP_DIR" || ! -f "$INFO_PLIST" || ! -f "$EXECUTABLE" ]]; then
  echo "Legacy Receiver bundle is incomplete: $APP_DIR" >&2
  exit 1
fi

bundle_min_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ "$bundle_min_os" != "$REQUIRED_MIN_OS" ]]; then
  echo "Bundle minimum is $bundle_min_os; expected $REQUIRED_MIN_OS." >&2
  exit 1
fi
if [[ "$bundle_id" != "com.targetbridge.intel-receiver-legacy" ]]; then
  echo "Legacy Receiver bundle identifier is not isolated: $bundle_id" >&2
  exit 1
fi

mach_o_count=0
while IFS= read -r -d '' binary; do
  description="$(/usr/bin/file -b "$binary")"
  [[ "$description" == *Mach-O* ]] || continue
  mach_o_count=$((mach_o_count + 1))

  architectures="$(/usr/bin/lipo -archs "$binary")"
  case " $architectures " in
    *" $EXPECTED_ARCH "*) ;;
    *) echo "Missing $EXPECTED_ARCH slice in $binary ($architectures)." >&2; exit 1 ;;
  esac

  while IFS= read -r dependency; do
    case "$dependency" in
      @*|/System/Library/*|/usr/lib/*) ;;
      *) echo "$binary depends on a non-system path outside the app: $dependency" >&2; exit 1 ;;
    esac
  done < <(/usr/bin/otool -L "$binary" | /usr/bin/awk 'NR > 1 { print $1 }')

  while IFS= read -r runpath; do
    case "$runpath" in
      @*|/System/Library/*|/usr/lib/*) ;;
      *) echo "$binary has a runpath outside the app: $runpath" >&2; exit 1 ;;
    esac
  done < <(/usr/bin/otool -l "$binary" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { in_runpath = 1; next }
    in_runpath && $1 == "path" { print $2; in_runpath = 0 }
  ')

  build_info="$(/usr/bin/xcrun vtool -show-build "$binary" 2>/dev/null || true)"
  minos_values="$(printf '%s\n' "$build_info" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { format = "modern" }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { format = "legacy" }
    format == "modern" && $1 == "minos" { print $2 }
    format == "legacy" && $1 == "version" { print $2 }
  ')"
  if [[ -z "$minos_values" ]]; then
    echo "Could not read a macOS deployment target from $binary." >&2
    exit 1
  fi
  while IFS= read -r minos; do
    if ! /usr/bin/awk -v found="$minos" -v required="$REQUIRED_MIN_OS" 'BEGIN { split(found,a,"."); split(required,b,"."); if (a[1] < b[1] || (a[1] == b[1] && a[2] <= b[2])) exit 0; exit 1 }'; then
      echo "$binary targets macOS $minos, newer than $REQUIRED_MIN_OS." >&2
      exit 1
    fi
  done <<< "$minos_values"

  if /usr/bin/nm -u "$binary" 2>/dev/null | /usr/bin/grep -q '_CVBufferCopyAttachments$'; then
    echo "$binary imports _CVBufferCopyAttachments, which is unavailable on macOS 11." >&2
    exit 1
  fi
done < <(/usr/bin/find "$APP_DIR/Contents" -type f -print0)

if (( mach_o_count == 0 )); then
  echo "No Mach-O binaries found in $APP_DIR." >&2
  exit 1
fi

echo "Legacy bundle audit passed: $mach_o_count Mach-O files, $EXPECTED_ARCH, macOS $REQUIRED_MIN_OS."
