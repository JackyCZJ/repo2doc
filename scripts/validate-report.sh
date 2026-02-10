#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  validate-report.sh <ProjectName> [options]

Options:
  --root <dir>                  Document root (default: Report)
  --strict                      Enable strict checks
  --enforce                     Exit non-zero on failures (default: warn only)
  --depth-profile <profile>     standard|audit (default: standard)
  --min-module-docs <n>         Minimum module docs count
  --min-feature-sections <n>    Minimum feature sections per module doc
  --require-feature-snippets    Require code snippets in every feature section
  --require-module-breakdown    Require module breakdown in every feature section
  -h, --help                    Show help
USAGE
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
DEPTH_PROFILE="standard"
MIN_MODULE_DOCS=1
MIN_FEATURE_SECTIONS=0
REQUIRE_FEATURE_SNIPPETS=0
REQUIRE_MODULE_BREAKDOWN=0

SET_MIN_MODULE_DOCS=0
SET_MIN_FEATURE_SECTIONS=0
SET_REQUIRE_FEATURE_SNIPPETS=0
SET_REQUIRE_MODULE_BREAKDOWN=0

# 校验选项值存在，避免缺参时脚本异常退出。
require_option_value() {
  local option="$1"
  local value="${2-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    echo "[FAIL] missing value for ${option}" >&2
    exit 2
  fi
}

# 校验数值参数，保证门禁比较逻辑稳定。
require_non_negative_integer() {
  local option="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "[FAIL] ${option} must be a non-negative integer: ${value}" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_option_value "$1" "${2-}"
      ROOT_BASE="$2"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --enforce)
      ENFORCE=1
      shift
      ;;
    --depth-profile)
      require_option_value "$1" "${2-}"
      DEPTH_PROFILE="$2"
      shift 2
      ;;
    --min-module-docs)
      require_option_value "$1" "${2-}"
      MIN_MODULE_DOCS="$2"
      SET_MIN_MODULE_DOCS=1
      shift 2
      ;;
    --min-feature-sections)
      require_option_value "$1" "${2-}"
      MIN_FEATURE_SECTIONS="$2"
      SET_MIN_FEATURE_SECTIONS=1
      shift 2
      ;;
    --require-feature-snippets)
      REQUIRE_FEATURE_SNIPPETS=1
      SET_REQUIRE_FEATURE_SNIPPETS=1
      shift
      ;;
    --require-module-breakdown)
      REQUIRE_MODULE_BREAKDOWN=1
      SET_REQUIRE_MODULE_BREAKDOWN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

require_non_negative_integer "--min-module-docs" "$MIN_MODULE_DOCS"
require_non_negative_integer "--min-feature-sections" "$MIN_FEATURE_SECTIONS"

case "$DEPTH_PROFILE" in
  standard)
    [[ $SET_MIN_MODULE_DOCS -eq 1 ]] || MIN_MODULE_DOCS=1
    [[ $SET_MIN_FEATURE_SECTIONS -eq 1 ]] || MIN_FEATURE_SECTIONS=2
    ;;
  audit)
    [[ $SET_MIN_MODULE_DOCS -eq 1 ]] || MIN_MODULE_DOCS=2
    [[ $SET_MIN_FEATURE_SECTIONS -eq 1 ]] || MIN_FEATURE_SECTIONS=3
    ;;
  *)
    echo "[FAIL] unsupported depth profile: $DEPTH_PROFILE" >&2
    exit 2
    ;;
esac

# 严格模式默认要求每个功能点有代码片段和逐模块拆解。
if [[ $STRICT -eq 1 ]]; then
  [[ $SET_REQUIRE_FEATURE_SNIPPETS -eq 1 ]] || REQUIRE_FEATURE_SNIPPETS=1
  [[ $SET_REQUIRE_MODULE_BREAKDOWN -eq 1 ]] || REQUIRE_MODULE_BREAKDOWN=1
fi

ROOT="${ROOT_BASE}/${PROJECT}"
if [[ ! -d "$ROOT" ]]; then
  echo "[FAIL] document directory not found: $ROOT"
  exit 2
fi

fail=0
warn=0

report_issue() {
  local level="$1"
  local message="$2"

  if [[ "$level" == "FAIL" ]]; then
    if [[ $ENFORCE -eq 1 ]]; then
      echo "[FAIL] $message"
      fail=1
    else
      echo "[WARN] $message"
      warn=$((warn + 1))
    fi
  else
    echo "[WARN] $message"
    warn=$((warn + 1))
  fi
}

# 识别占位文档，避免把空壳模板当成可交付内容。
has_substantive_content_file() {
  local file="$1"
  awk '
    BEGIN { c=0 }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*```/ { next }
    /^[[:space:]]*[-*][[:space:]]*$/ { next }
    /^[[:space:]]*-[[:space:]]*[^:：]+[:：][[:space:]]*$/ { next }
    /^[[:space:]]*(TODO|TBD|待补充|待完善|N\/A)[[:space:]]*$/ { next }
    /粘贴 5-20 行关键实现|关键代码（可选）/ { next }
    { c++ }
    END { exit(c > 0 ? 0 : 1) }
  ' "$file"
}

# 统计匹配次数：优先 rg，缺失时回退 grep。
count_matches_in_files() {
  local regex="$1"
  shift

  if [[ $# -eq 0 ]]; then
    printf '0\n'
    return
  fi

  if command -v rg >/dev/null 2>&1; then
    (rg -No "$regex" "$@" || true) | wc -l | tr -d ' '
  else
    (grep -Eho "$regex" "$@" || true) | wc -l | tr -d ' '
  fi
}

# 统计功能点章节质量：
# - 功能点总数
# - 缺“实现细节”的功能点数
# - 缺“设计原理”的功能点数
# - 缺代码片段的功能点数
# - 缺“涉及模块”的功能点数
# - 缺“模块：...”子章节的功能点数
# - 模块子章节缺“实现细节”的数量
# - 模块子章节缺“设计原理”的数量
collect_feature_section_stats() {
  local file="$1"
  local require_snippet="$2"
  local require_module_breakdown="$3"

  awk -v require_snippet="$require_snippet" -v require_module_breakdown="$require_module_breakdown" '
    function flush_module() {
      if (!in_module) {
        return
      }
      if (!module_has_detail) {
        missing_module_detail += 1
      }
      if (!module_has_principle) {
        missing_module_principle += 1
      }
      in_module = 0
      module_has_detail = 0
      module_has_principle = 0
    }

    function flush_feature() {
      if (!in_feature) {
        return
      }

      flush_module()

      if (!feature_has_detail) {
        missing_feature_detail += 1
      }
      if (!feature_has_principle) {
        missing_feature_principle += 1
      }
      if (require_snippet == 1 && !feature_has_snippet) {
        missing_feature_snippet += 1
      }

      if (require_module_breakdown == 1) {
        if (!feature_has_involved_modules) {
          missing_involved_modules += 1
        }
        if (feature_module_count < 1) {
          missing_module_subsection += 1
        }
      }

      in_feature = 0
      feature_has_detail = 0
      feature_has_principle = 0
      feature_has_snippet = 0
      feature_has_involved_modules = 0
      feature_module_count = 0
    }

    BEGIN {
      feature_count = 0
      missing_feature_detail = 0
      missing_feature_principle = 0
      missing_feature_snippet = 0
      missing_involved_modules = 0
      missing_module_subsection = 0
      missing_module_detail = 0
      missing_module_principle = 0

      in_feature = 0
      in_module = 0
      feature_has_detail = 0
      feature_has_principle = 0
      feature_has_snippet = 0
      feature_has_involved_modules = 0
      feature_module_count = 0
      module_has_detail = 0
      module_has_principle = 0
    }

    /^#{1,6}[[:space:]]+/ {
      if ($0 ~ /功能点总览/) {
        next
      }

      if ($0 ~ /功能点[[:space:]]*[:：]/) {
        flush_feature()
        feature_count += 1
        in_feature = 1
        next
      }

      if (in_feature && $0 ~ /实现细节/) {
        feature_has_detail = 1
      }

      if (in_feature && $0 ~ /设计原理/) {
        feature_has_principle = 1
      }

      if (in_feature && $0 ~ /涉及模块/) {
        feature_has_involved_modules = 1
      }

      if (in_feature && $0 ~ /模块[[:space:]]*[:：]/) {
        flush_module()
        in_module = 1
        feature_module_count += 1
        next
      }
    }

    in_feature && /^```/ {
      feature_has_snippet = 1
    }

    in_module && /^[[:space:]]*[-*][[:space:]]*实现细节[:：]/ {
      module_has_detail = 1
    }

    in_module && /^[[:space:]]*[-*][[:space:]]*设计原理[:：]/ {
      module_has_principle = 1
    }

    END {
      flush_feature()
      printf "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", \
        feature_count, \
        missing_feature_detail, \
        missing_feature_principle, \
        missing_feature_snippet, \
        missing_involved_modules, \
        missing_module_subsection, \
        missing_module_detail, \
        missing_module_principle
    }
  ' "$file"
}

check_required() {
  local path="$1"

  if [[ -f "$path" ]]; then
    echo "[OK] $path"
  else
    report_issue "FAIL" "missing: $path"
  fi
}

required=(
  "00-reading-guide.md"
  "project-overview.md"
  "getting-started.md"
  "feature-summary.md"
)

for f in "${required[@]}"; do
  check_required "$ROOT/$f"
done

ignore_pattern='^(00-reading-guide|project-overview|getting-started|feature-summary)\.md$'

module_docs=()
while IFS= read -r file; do
  base=$(basename "$file")
  if [[ ! "$base" =~ $ignore_pattern ]]; then
    module_docs+=("$file")
  fi
done < <(find "$ROOT" -maxdepth 1 -type f -name '*.md' | sort)

if [[ ${#module_docs[@]} -lt "$MIN_MODULE_DOCS" ]]; then
  report_issue "FAIL" "module docs too few (${#module_docs[@]} < $MIN_MODULE_DOCS)"
else
  echo "[OK] module docs: ${#module_docs[@]}"
fi

placeholder_docs=()
while IFS= read -r file; do
  if ! has_substantive_content_file "$file"; then
    placeholder_docs+=("$(basename "$file")")
  fi
done < <(find "$ROOT" -maxdepth 1 -type f -name '*.md' | sort)

if [[ ${#placeholder_docs[@]} -gt 0 ]]; then
  joined=$(printf '%s, ' "${placeholder_docs[@]}")
  joined="${joined%, }"
  report_issue "FAIL" "empty/placeholder docs detected: $joined"
else
  echo "[OK] no empty placeholder docs"
fi

# 文档正文禁止出现工具过程痕迹，避免把执行日志写进交付文档。
PROCESS_TRACE_REGEX='repo2doc|skills/repo2doc|scaffold-report\.sh|validate-report\.sh|discover-modules\.sh|执行轨迹|报告骨架|报告输出目录|本报告|报告导航|本文档由|由[^\n]*(技能|skill|脚本)[^\n]*(生成|产出|输出)'
trace_docs=()
while IFS= read -r file; do
  if [[ "$(count_matches_in_files "$PROCESS_TRACE_REGEX" "$file")" -gt 0 ]]; then
    trace_docs+=("$(basename "$file")")
  fi
done < <(find "$ROOT" -maxdepth 1 -type f -name '*.md' | sort)

if [[ ${#trace_docs[@]} -gt 0 ]]; then
  joined=$(printf '%s, ' "${trace_docs[@]}")
  joined="${joined%, }"
  report_issue "FAIL" "process/tool traces detected in docs: $joined"
else
  echo "[OK] no process/tool traces in docs"
fi

if [[ ${#module_docs[@]} -gt 0 ]]; then
  module_quality_fail=0

  for doc in "${module_docs[@]}"; do
    base=$(basename "$doc")
    stats="$(collect_feature_section_stats "$doc" "$REQUIRE_FEATURE_SNIPPETS" "$REQUIRE_MODULE_BREAKDOWN")"

    IFS=$'\t' read -r feature_count missing_feature_detail missing_feature_principle missing_feature_snippet missing_involved_modules missing_module_subsection missing_module_detail missing_module_principle <<< "$stats"

    local_issue=()
    if [[ "$feature_count" -lt "$MIN_FEATURE_SECTIONS" ]]; then
      local_issue+=("feature-sections $feature_count < $MIN_FEATURE_SECTIONS")
    fi
    if [[ "$missing_feature_detail" -gt 0 ]]; then
      local_issue+=("missing '实现细节' in $missing_feature_detail section(s)")
    fi
    if [[ "$missing_feature_principle" -gt 0 ]]; then
      local_issue+=("missing '设计原理' in $missing_feature_principle section(s)")
    fi
    if [[ "$REQUIRE_FEATURE_SNIPPETS" -eq 1 && "$missing_feature_snippet" -gt 0 ]]; then
      local_issue+=("feature-snippets missing in $missing_feature_snippet section(s)")
    fi
    if [[ "$REQUIRE_MODULE_BREAKDOWN" -eq 1 && "$missing_involved_modules" -gt 0 ]]; then
      local_issue+=("missing '涉及模块' in $missing_involved_modules section(s)")
    fi
    if [[ "$REQUIRE_MODULE_BREAKDOWN" -eq 1 && "$missing_module_subsection" -gt 0 ]]; then
      local_issue+=("missing '模块：...' subsection in $missing_module_subsection section(s)")
    fi
    if [[ "$REQUIRE_MODULE_BREAKDOWN" -eq 1 && "$missing_module_detail" -gt 0 ]]; then
      local_issue+=("module subsection missing '实现细节' in $missing_module_detail case(s)")
    fi
    if [[ "$REQUIRE_MODULE_BREAKDOWN" -eq 1 && "$missing_module_principle" -gt 0 ]]; then
      local_issue+=("module subsection missing '设计原理' in $missing_module_principle case(s)")
    fi

    if [[ ${#local_issue[@]} -gt 0 ]]; then
      joined=$(printf '%s; ' "${local_issue[@]}")
      joined="${joined%; }"
      echo "[WARN] module quality weak: $base ($joined)"
      module_quality_fail=1
    else
      echo "[OK] module quality: $base"
    fi
  done

  if [[ $module_quality_fail -ne 0 ]]; then
    if [[ $ENFORCE -eq 1 ]]; then
      fail=1
    else
      warn=$((warn + 1))
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
