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
  --enforce             Exit non-zero on check failures (default: warn only)
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
ENFORCE=0
MIN_CITATIONS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_BASE="$2"; shift 2 ;;
    --strict)
      STRICT=1; shift ;;
    --min-citations)
      MIN_CITATIONS="$2"; shift 2 ;;
    --enforce)
      ENFORCE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2 ;;
  esac
done

ROOT="${ROOT_BASE}/${PROJECT}"

if [[ ! -d "$ROOT" ]]; then
  echo "[FAIL] report directory not found: $ROOT"
  exit 2
fi

fail=0
warn=0

check_required() {
  local path="$1"
  if [[ -f "$path" ]]; then
    echo "[OK] $path"
  else
    if [[ $ENFORCE -eq 1 ]]; then
      echo "[FAIL] missing: $path"
      fail=1
    else
      echo "[WARN] missing: $path"
      warn=$((warn + 1))
    fi
  fi
}

required=(
  "00-reading-guide.md"
  "project-overview.md"
  "appendix-source-index.md"
)

for f in "${required[@]}"; do
  check_required "$ROOT/$f"
done

ignore_pattern='^(00-reading-guide|project-overview|appendix-source-index|system-overview|module-map|core-flows|deep-dives|data-and-state|runtime-and-config|risks-and-techdebt|optimization-roadmap|layered-highlights-and-hardparts|temporal-behavior|state-machine-analysis|mechanism-implementation|mechanism-flow|A-01-getting-started|B-01-deep-dive|B-02-layered-highlights-and-hardparts|B-10-temporal-behavior|B-11-state-machine-analysis|B-12-mechanism-implementation|B-13-mechanism-flow)\.md$'

module_docs=()
while IFS= read -r file; do
  base=$(basename "$file")
  if [[ ! "$base" =~ $ignore_pattern ]]; then
    module_docs+=("$file")
  fi
done < <(find "$ROOT" -maxdepth 1 -type f -name '*.md' | sort)

if [[ ${#module_docs[@]} -lt 1 ]]; then
  if [[ $ENFORCE -eq 1 ]]; then
    echo "[FAIL] no module-specific deep-dive docs found"
    fail=1
  else
    echo "[WARN] no module-specific deep-dive docs found"
    warn=$((warn + 1))
  fi
else
  echo "[OK] module docs: ${#module_docs[@]}"
fi

if [[ $STRICT -eq 1 ]]; then
  deep_docs=("${module_docs[@]}")

  for optional in \
    "$ROOT/layered-highlights-and-hardparts.md" \
    "$ROOT/temporal-behavior.md" \
    "$ROOT/state-machine-analysis.md" \
    "$ROOT/mechanism-implementation.md" \
    "$ROOT/mechanism-flow.md" \
    "$ROOT/B-02-layered-highlights-and-hardparts.md" \
    "$ROOT/B-10-temporal-behavior.md" \
    "$ROOT/B-11-state-machine-analysis.md" \
    "$ROOT/B-12-mechanism-implementation.md" \
    "$ROOT/B-13-mechanism-flow.md"; do
    [[ -f "$optional" ]] && deep_docs+=("$optional")
  done

  if [[ ${#deep_docs[@]} -eq 0 ]]; then
    if [[ $ENFORCE -eq 1 ]]; then
      echo "[FAIL] strict mode: no deep-dive docs found"
      fail=1
    else
      echo "[WARN] strict mode: no deep-dive docs found"
      warn=$((warn + 1))
    fi
  else
    citation_count=$(rg -No '[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+:[0-9]+' "${deep_docs[@]}" | wc -l | tr -d ' ')
    if [[ "$citation_count" -lt "$MIN_CITATIONS" ]]; then
      if [[ $ENFORCE -eq 1 ]]; then
        echo "[FAIL] strict mode: citations too few ($citation_count < $MIN_CITATIONS)"
        fail=1
      else
        echo "[WARN] strict mode: citations too few ($citation_count < $MIN_CITATIONS)"
        warn=$((warn + 1))
      fi
    else
      echo "[OK] strict mode: citation count = $citation_count"
    fi

    impl_cards=$(rg -N '#### 实现卡片' "${deep_docs[@]}" | wc -l | tr -d ' ')
    if [[ "$impl_cards" -lt 1 ]]; then
      if [[ $ENFORCE -eq 1 ]]; then
        echo "[FAIL] strict mode: missing implementation cards"
        fail=1
      else
        echo "[WARN] strict mode: missing implementation cards"
        warn=$((warn + 1))
      fi
    else
      echo "[OK] strict mode: implementation cards = $impl_cards"
    fi

    mermaid_blocks=$(rg -N '^```mermaid$' "${deep_docs[@]}" | wc -l | tr -d ' ')
    if [[ "$mermaid_blocks" -lt 1 ]]; then
      if [[ $ENFORCE -eq 1 ]]; then
        echo "[FAIL] strict mode: no Mermaid blocks found"
        fail=1
      else
        echo "[WARN] strict mode: no Mermaid blocks found"
        warn=$((warn + 1))
      fi
    else
      echo "[OK] strict mode: mermaid blocks = $mermaid_blocks"
    fi
  fi
fi

if [[ $fail -ne 0 ]]; then
  exit 2
fi

if [[ $warn -gt 0 ]]; then
  echo "Validation completed with warnings for $ROOT"
else
  echo "Validation passed for $ROOT"
fi