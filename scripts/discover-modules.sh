#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  discover-modules.sh <repo-path> [options]

Options:
  --top <n>            Number of modules to return (default: 6)
  --format <type>      Output format: table|csv (default: table)
  -h, --help           Show help

Examples:
  discover-modules.sh /path/to/repo
  discover-modules.sh /path/to/repo --top 8 --format csv
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

REPO_PATH="$1"
shift

TOP_N=6
FORMAT="table"

# 统一校验选项参数是否存在，避免 "--top" 这类缺参情况直接触发脚本错误。
require_option_value() {
  local option="$1"
  local value="${2-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    echo "[FAIL] missing value for ${option}" >&2
    exit 2
  fi
}

# 统一校验数值参数，保证排序和截断逻辑稳定可预测。
require_positive_integer() {
  local option="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "[FAIL] ${option} must be a positive integer: ${value}" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --top)
      require_option_value "$1" "${2-}"
      TOP_N="$2"
      shift 2
      ;;
    --format)
      require_option_value "$1" "${2-}"
      FORMAT="$2"
      shift 2
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

require_positive_integer "--top" "$TOP_N"

case "$FORMAT" in
  table|csv)
    ;;
  *)
    echo "[FAIL] unsupported format: $FORMAT" >&2
    exit 2
    ;;
esac

if [[ ! -d "$REPO_PATH" ]]; then
  echo "[FAIL] repo path not found: $REPO_PATH" >&2
  exit 2
fi

# 统一转绝对路径，避免传入 "." 时被隐藏目录过滤规则误伤。
REPO_PATH="$(cd "$REPO_PATH" && pwd -P)"

# 根据路径结构提取“模块键”，让 monorepo 与单仓库都能得到稳定模块名。
module_key() {
  local rel="$1"
  local first
  local second

  first="${rel%%/*}"
  if [[ "$first" == "$rel" ]]; then
    printf 'root\n'
    return
  fi

  second="${rel#*/}"
  second="${second%%/*}"

  case "$first" in
    packages|apps|services|modules|crates|libs|cmd)
      if [[ -n "$second" && "$second" != "$rel" ]]; then
        printf '%s/%s\n' "$first" "$second"
      else
        printf '%s\n' "$first"
      fi
      ;;
    src)
      if [[ -n "$second" && "$second" != "$rel" ]]; then
        printf '%s\n' "$second"
      else
        printf 'src\n'
      fi
      ;;
    *)
      printf '%s\n' "$first"
      ;;
  esac
}


tmp_records="$(mktemp)"
trap 'rm -f "$tmp_records"' EXIT

while IFS= read -r -d '' file; do
  rel="${file#"$REPO_PATH"/}"
  key="$(module_key "$rel")"

  case "$key" in
    .github|docs|doc|examples|example|tests|test|report|reports)
      continue
      ;;
  esac

  lines="$(wc -l < "$file" | tr -d ' ')"
  printf '%s\t%s\n' "$lines" "$key" >> "$tmp_records"
done < <(
  find "$REPO_PATH" -type f \
    \( -name '*.rs' -o -name '*.go' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.java' -o -name '*.kt' -o -name '*.swift' -o -name '*.rb' -o -name '*.php' -o -name '*.cs' -o -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' -o -name '*.m' -o -name '*.mm' -o -name '*.scala' -o -name '*.lua' -o -name '*.sh' \) \
    -not -name '*.min.js' \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/target/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/out/*' \
    -not -path '*/vendor/*' \
    -not -path '*/coverage/*' \
    -not -path '*/Report/*' \
    -not -path '*/reports/*' \
    -not -path '*/.next/*' \
    -not -path '*/.turbo/*' \
    -not -path '*/.*/*' \
    -print0
)

if [[ ! -s "$tmp_records" ]]; then
  echo "[FAIL] no source files found under: $REPO_PATH" >&2
  exit 2
fi

ranked="$(
  awk -F'\t' '{
    lines[$2] += $1;
    files[$2] += 1;
  }
  END {
    for (k in lines) {
      printf "%d\t%d\t%s\n", lines[k], files[k], k;
    }
  }' "$tmp_records" | sort -nrk1,1 | head -n "$TOP_N"
)"

if [[ -z "$ranked" ]]; then
  echo "[FAIL] module ranking result is empty" >&2
  exit 2
fi

if [[ "$FORMAT" == "csv" ]]; then
  printf '%s\n' "$ranked" | awk -F'\t' '{print $3}' | paste -sd, -
  exit 0
fi

printf 'Rank\tModule\tFiles\tLOC\n'
idx=1
while IFS=$'\t' read -r loc file_count module; do
  printf '%d\t%s\t%s\t%s\n' "$idx" "$module" "$file_count" "$loc"
  idx=$((idx + 1))
done <<< "$ranked"
