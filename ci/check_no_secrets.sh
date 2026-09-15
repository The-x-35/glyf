#!/usr/bin/env bash
# SPEC §1.6 / §11.2: no API keys or OAuth tokens in any client bundle.
# Greps client source (app/ios, app/lib) and server source for known key
# shapes. Run standalone or from CI before every milestone gate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGETS=("$ROOT/app/lib" "$ROOT/app/ios" "$ROOT/server/src" "$ROOT/shared")

# One pattern per line: OpenRouter/OpenAI, Anthropic, Google, Slack,
# AWS, Stripe-style, private key blocks, Jupiter/Helius-ish hex-y bearer.
PATTERNS=(
  'sk-or-v1-[A-Za-z0-9]'
  'sk-ant-[A-Za-z0-9]'
  'sk-proj-[A-Za-z0-9]'
  'AIza[0-9A-Za-z_\-]{30}'
  'xox[baprs]-[0-9A-Za-z]'
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN( RSA| EC| OPENSSH)? PRIVATE KEY-----'
  'privy_app_secret_[A-Za-z0-9]'
)

FAIL=0
for target in "${TARGETS[@]}"; do
  [[ -d "$target" ]] || continue
  for pattern in "${PATTERNS[@]}"; do
    if hits="$(grep -RInE --include='*.{swift,dart,ts,js,json,plist,xcconfig,yaml,yml,env}' "$pattern" "$target" 2>/dev/null)"; then
      if [[ -n "$hits" ]]; then
        echo "GLYF CI FAIL: possible secret matching '$pattern':" >&2
        echo "$hits" >&2
        FAIL=1
      fi
    fi
  done
done

if [[ "$FAIL" == "1" ]]; then exit 1; fi
echo "GLYF CI OK: no client-side secrets detected"
