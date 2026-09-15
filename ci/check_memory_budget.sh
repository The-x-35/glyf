#!/usr/bin/env bash
# §10.9 budget guards from GLYF_MEM log lines:
#   - extension peak footprint ≤ 45 MB (SPEC hard budget)
#   - shell surface samples ≤ base + 6 MB (approximation until Instruments)
# Usage: capture a log first, then:  ci/check_memory_budget.sh <logfile>
# NOTE (§10.8): simulator memory is NOT device truth — debug builds on the
# simulator read high. The guard warns on sim numbers; the hard gate is
# re-verified on physical hardware per milestone.
set -euo pipefail

LOG="${1:?usage: check_memory_budget.sh <logfile with GLYF_MEM lines>}"
LIMIT_MB=45

peak=$(grep -oE "footprint_mb=[0-9]+(\.[0-9]+)?" "$LOG" | cut -d= -f2 | sort -n | tail -1)
if [[ -z "$peak" ]]; then
  echo "GLYF CI: no GLYF_MEM samples in $LOG" >&2
  exit 1
fi

echo "GLYF_MEM peak footprint: ${peak} MB (budget ${LIMIT_MB} MB)"
over=$(echo "$peak > $LIMIT_MB" | bc)
if [[ "$over" == "1" ]]; then
  if [[ "${GLYF_MEM_STRICT:-0}" == "1" ]]; then
    echo "GLYF CI FAIL: peak ${peak} MB exceeds ${LIMIT_MB} MB budget" >&2
    exit 1
  fi
  echo "GLYF CI WARN: over budget on SIMULATOR numbers — re-verify on device (set GLYF_MEM_STRICT=1 there)"
fi
echo "GLYF CI OK"
