#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ProjectName>"
  exit 1
fi

PROJECT="$1"
ROOT="Report/${PROJECT}"

required=(
  "00-reading-guide.md"
  "A-01-getting-started.md"
  "B-01-deep-dive.md"
  "B-02-layered-highlights-and-hardparts.md"
  "appendix-source-index.md"
)

fail=0
for f in "${required[@]}"; do
  if [[ ! -f "$ROOT/$f" ]]; then
    echo "[FAIL] missing: $ROOT/$f"
    fail=1
  else
    echo "[OK] $ROOT/$f"
  fi
done

if [[ $fail -ne 0 ]]; then
  exit 2
fi

echo "Validation passed for $ROOT"
