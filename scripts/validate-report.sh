#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate-report.sh <ProjectName> [options]

Options:
  --root <dir>          Report root (default: Report)
  --strict              Enable strict checks (citations, implementation cards, mermaid presence)
  --min-citations <n>   Minimum path:line matches required in deep-dive docs (strict mode, default: 5)
  -h, --help            Show help
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PROJECT="$1"
shift

ROOT_BASE="Report"
STRICT=0
MIN_CITATIONS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_BASE="$2"; shift 2 ;;
    --strict)
      STRICT=1; shift ;;
    --min-citations)
      MIN_CITATIONS="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2 ;;
  esac
done

ROOT="${ROOT_BASE}/${PROJECT}"

required=(
  "00-reading-guide.md"
  "A-01-getting-started.md"
  "B-01-deep-dive.md"
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

if [[ $STRICT -eq 1 ]]; then
  deep_docs=()
  [[ -f "$ROOT/B-01-deep-dive.md" ]] && deep_docs+=("$ROOT/B-01-deep-dive.md")
  [[ -f "$ROOT/B-02-layered-highlights-and-hardparts.md" ]] && deep_docs+=("$ROOT/B-02-layered-highlights-and-hardparts.md")
  [[ -f "$ROOT/B-10-temporal-behavior.md" ]] && deep_docs+=("$ROOT/B-10-temporal-behavior.md")
  [[ -f "$ROOT/B-11-state-machine-analysis.md" ]] && deep_docs+=("$ROOT/B-11-state-machine-analysis.md")
  [[ -f "$ROOT/B-12-mechanism-implementation.md" ]] && deep_docs+=("$ROOT/B-12-mechanism-implementation.md")
  [[ -f "$ROOT/B-13-mechanism-flow.md" ]] && deep_docs+=("$ROOT/B-13-mechanism-flow.md")

  if [[ ${#deep_docs[@]} -eq 0 ]]; then
    echo "[FAIL] strict mode: no deep-dive docs found"
    fail=1
  else
    # Citation pattern: something.ext:123
    citation_count=$(rg -No '[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+:[0-9]+' "${deep_docs[@]}" | wc -l | tr -d ' ')
    if [[ "$citation_count" -lt "$MIN_CITATIONS" ]]; then
      echo "[FAIL] strict mode: citations too few ($citation_count < $MIN_CITATIONS)"
      fail=1
    else
      echo "[OK] strict mode: citation count = $citation_count"
    fi

    # At least one implementation card in deep dive docs
    impl_cards=$(rg -N '#### 实现卡片' "${deep_docs[@]}" | wc -l | tr -d ' ')
    if [[ "$impl_cards" -lt 1 ]]; then
      echo "[FAIL] strict mode: missing implementation cards"
      fail=1
    else
      echo "[OK] strict mode: implementation cards = $impl_cards"
    fi

    # Mermaid is recommended in deep dive; require at least one block in strict mode
    mermaid_blocks=$(rg -N '^```mermaid$' "${deep_docs[@]}" | wc -l | tr -d ' ')
    if [[ "$mermaid_blocks" -lt 1 ]]; then
      echo "[FAIL] strict mode: no Mermaid blocks found"
      fail=1
    else
      echo "[OK] strict mode: mermaid blocks = $mermaid_blocks"
    fi
  fi
fi

if [[ $fail -ne 0 ]]; then
  exit 2
fi

echo "Validation passed for $ROOT"
