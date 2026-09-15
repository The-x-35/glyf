#!/usr/bin/env bash
# SPEC §1.1: Flutter.framework must NEVER link into the keyboard extension.
# The extension lives in a ~40-70 MB jetsam budget; Flutter alone blows it.
#
# Two modes:
#   - Xcode build phase on Runner (uses TARGET_BUILD_DIR/FULL_PRODUCT_NAME)
#   - standalone: ci/check_keyboard_clean.sh [path/to/Runner.app]
set -euo pipefail

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${FULL_PRODUCT_NAME:-}" ]]; then
  APP="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
else
  APP="${1:-app/build/ios/iphonesimulator/Runner.app}"
fi

APPEX="$APP/PlugIns/GlyfKeyboard.appex"
BIN="$APPEX/GlyfKeyboard"

if [[ ! -d "$APPEX" ]]; then
  echo "GLYF CI FAIL: keyboard extension not embedded at $APPEX" >&2
  exit 1
fi
if [[ ! -f "$BIN" ]]; then
  echo "GLYF CI FAIL: extension binary missing at $BIN" >&2
  exit 1
fi

if otool -L "$BIN" | grep -qi "flutter"; then
  echo "GLYF CI FAIL: GlyfKeyboard links Flutter (SPEC §1.1):" >&2
  otool -L "$BIN" | grep -i flutter >&2
  exit 1
fi

if [[ -d "$APPEX/Frameworks" ]] && ls "$APPEX/Frameworks" | grep -qi "flutter"; then
  echo "GLYF CI FAIL: Flutter framework embedded inside the appex (SPEC §1.1)" >&2
  exit 1
fi

echo "GLYF CI OK: keyboard extension is Flutter-free"
