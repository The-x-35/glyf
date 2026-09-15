#!/usr/bin/env bash
# Runs a Ruby script with the xcodeproj gem available, using CocoaPods'
# bundled gem environment (no global gem install needed).
# Usage: tools/xcodeproj-env.sh tools/add_keyboard_target.rb
set -euo pipefail

CELLAR="$(ls -d /opt/homebrew/Cellar/cocoapods/*/libexec 2>/dev/null | tail -1)"
RUBY_BIN="/opt/homebrew/opt/ruby/bin/ruby"

if [[ -z "$CELLAR" || ! -x "$RUBY_BIN" ]]; then
  echo "Needs Homebrew CocoaPods (provides the xcodeproj gem) and Homebrew Ruby." >&2
  exit 1
fi

GEM_HOME="$CELLAR" exec "$RUBY_BIN" "$@"
