#!/usr/bin/env bash
# SPEC §1.6 / §11.2: no API keys or OAuth tokens in any client bundle.
# Greps every committable file in the repo for known key shapes.
# Run standalone or from CI before every milestone gate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# One pattern per line: OpenRouter/OpenAI, Anthropic, Google API keys and
# OAuth client secrets, Slack, AWS, GitHub, Stripe live keys, private key
# blocks, Privy, and database URLs that carry a password.
PATTERNS=(
  'sk-or-v1-[A-Za-z0-9]'
  'sk-ant-[A-Za-z0-9]'
  'sk-proj-[A-Za-z0-9]'
  'AIza[0-9A-Za-z_\-]{30}'
  'GOCSPX-[0-9A-Za-z_\-]{20}'
  'xox[baprs]-[0-9A-Za-z]'
  'AKIA[0-9A-Z]{16}'
  'gh[pousr]_[0-9A-Za-z]{36}'
  'github_pat_[0-9A-Za-z_]{40}'
  'sk_live_[0-9A-Za-z]{20}'
  '-----BEGIN( RSA| EC| OPENSSH| ENCRYPTED)? PRIVATE KEY-----'
  'privy_app_secret_[A-Za-z0-9]'
  'postgres(ql)?://[^:/@ <]+:[^@ <]{8,}@'
)

# Every file git would commit: tracked, plus new files that are not ignored
# (server/.env and other ignored files are never read). Generated and vendor
# trees are skipped. Hits print as file:line only, never the matched text,
# so the check itself can't leak a key into a CI log.
cd "$ROOT"
FILES=()
while IFS= read -r -d '' f; do
  case "$f" in
    # The secret scanners' own tests feed them made-up keys on purpose.
    */test/*|*/RunnerTests/*|*.test.ts|*Test.kt|*Tests.swift) continue ;;
    */node_modules/*|*/build/*|*/.next/*|*/dist/*|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.mp4|*.mov|*.ttf|*.otf|*.woff|*.woff2|*.jar|*.aab|*.apk|*.ipa|*.zip|*.pdf) continue ;;
  esac
  [[ -f "$f" ]] && FILES+=("$f")
done < <(git ls-files -z --cached --others --exclude-standard)

if [[ "${#FILES[@]}" -eq 0 ]]; then
  echo "GLYF CI FAIL: no files to scan (is this a git checkout?)" >&2
  exit 1
fi

FAIL=0
for pattern in "${PATTERNS[@]}"; do
  if hits="$(printf '%s\0' "${FILES[@]}" | xargs -0 grep -nIE -e "$pattern" -- 2>/dev/null | cut -d: -f1,2)"; then
    if [[ -n "$hits" ]]; then
      echo "GLYF CI FAIL: possible secret matching '$pattern' at:" >&2
      echo "$hits" >&2
      FAIL=1
    fi
  fi
done

if [[ "$FAIL" == "1" ]]; then exit 1; fi
echo "GLYF CI OK: no secrets detected in ${#FILES[@]} files"
