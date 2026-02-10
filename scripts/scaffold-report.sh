#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scaffold-report.sh <ProjectName> [options]

Options:
  --root <dir>               Output root (default: Report)
  --template-root <dir>      Template root (default: <skill>/templates)
  --modules <csv>            Comma-separated module names (default: core)
  --repo <path>              Repository path (used by --auto-modules)
  --auto-modules <n>         Auto-pick top N modules by LOC from repo
  --force                    Overwrite existing files
  -h, --help                 Show help

Examples:
  scaffold-report.sh tvscreener --modules app,field
  scaffold-report.sh tvscreener --repo /path/to/repo --auto-modules 6
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PROJECT="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_BASE="Report"
TPL="${SCRIPT_DIR%/scripts}/templates"
MODULES="core"
REPO_PATH=""
AUTO_MODULES=0
FORCE=0

# 统一校验选项参数，避免缺参导致 set -u 中断。
require_option_value() {
  local option="$1"
  local value="${2-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    echo "[FAIL] missing value for ${option}" >&2
    exit 2
  fi
}

# 校验整数参数，保证后续算术判断稳定可预测。
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
    --template-root)
      require_option_value "$1" "${2-}"
      TPL="$2"
      shift 2
      ;;
    --modules)
      require_option_value "$1" "${2-}"
      MODULES="$2"
      shift 2
      ;;
    --repo)
      require_option_value "$1" "${2-}"
      REPO_PATH="$2"
      shift 2
      ;;
    --auto-modules)
      require_option_value "$1" "${2-}"
      AUTO_MODULES="$2"
      shift 2
      ;;
    --force)
      FORCE=1
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

require_non_negative_integer "--auto-modules" "$AUTO_MODULES"

# 解析模板目录：支持绝对路径、当前目录相对路径、脚本目录相对路径。
resolve_template_root() {
  local candidate="$1"

  if [[ -d "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -d "$PWD/$candidate" ]]; then
    printf '%s\n' "$PWD/$candidate"
    return 0
  fi

  if [[ -d "${SCRIPT_DIR%/scripts}/$candidate" ]]; then
    printf '%s\n' "${SCRIPT_DIR%/scripts}/$candidate"
    return 0
  fi

  printf '%s\n' "$candidate"
}

TPL="$(resolve_template_root "$TPL")"
ROOT="${ROOT_BASE}/${PROJECT}"
mkdir -p "$ROOT"

if [[ ! -d "$TPL" ]]; then
  echo "[FAIL] template root not found: $TPL" >&2
  exit 2
fi

if [[ "$AUTO_MODULES" -gt 0 ]]; then
  if [[ -z "$REPO_PATH" ]]; then
    echo "[FAIL] --auto-modules requires --repo <path>" >&2
    exit 2
  fi

  DISCOVER_SCRIPT="$SCRIPT_DIR/discover-modules.sh"
  if [[ ! -x "$DISCOVER_SCRIPT" ]]; then
    echo "[FAIL] module discovery script missing or not executable: $DISCOVER_SCRIPT" >&2
    exit 2
  fi

  auto_modules="$($DISCOVER_SCRIPT "$REPO_PATH" --top "$AUTO_MODULES" --format csv)"
  if [[ -n "$auto_modules" ]]; then
    MODULES="$auto_modules"
    echo "[OK] auto modules: $MODULES"
  else
    echo "[WARN] auto module discovery returned empty; fallback to --modules: $MODULES"
  fi
fi

slugify() {
  local input="$1"
  local slug

  slug=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  if [[ -z "$slug" ]]; then
    slug="module"
  fi
  printf '%s\n' "$slug"
}

# 兼容 GNU/BSD sed 的原地替换，确保跨平台可用。
portable_sed_inplace() {
  local expr="$1"
  local target="$2"

  if sed --version >/dev/null 2>&1; then
    sed -i -e "$expr" "$target"
  else
    sed -i '' -e "$expr" "$target"
  fi
}

# 转义 sed replacement 特殊字符，避免项目名或标题替换失败。
escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
}

write_template_or_fail() {
  local template="$1"
  local dst="$2"

  if [[ -f "$dst" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $dst"
    return
  fi

  if [[ ! -f "$TPL/$template" ]]; then
    echo "[FAIL] template missing: $TPL/$template" >&2
    exit 2
  fi

  cp "$TPL/$template" "$dst"
  echo "[OK] $dst"
}

write_template_or_fail "project-overview.md" "$ROOT/project-overview.md"
write_template_or_fail "getting-started.md" "$ROOT/getting-started.md"
write_template_or_fail "feature-summary.md" "$ROOT/feature-summary.md"

declare -a module_files=()
declare -a module_titles=()
declare -a used_slugs=()

slug_used() {
  local target="$1"
  local s
  for s in "${used_slugs[@]-}"; do
    if [[ "$s" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

IFS=',' read -r -a module_names <<< "$MODULES"
for raw_name in "${module_names[@]}"; do
  name=$(printf '%s' "$raw_name" | sed -E 's/^ +//; s/ +$//')
  [[ -z "$name" ]] && continue

  slug="$(slugify "$name")"
  if slug_used "$slug"; then
    suffix=2
    while slug_used "${slug}-${suffix}"; do
      suffix=$((suffix + 1))
    done
    slug="${slug}-${suffix}"
  fi
  used_slugs+=("$slug")

  dst="$ROOT/${slug}.md"
  if [[ -f "$dst" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $dst"
    module_files+=("$(basename "$dst")")
    module_titles+=("$name")
    continue
  fi

  cp "$TPL/module-detail.md" "$dst"
  escaped_title="$(escape_sed_replacement "# ${name} 模块文档")"
  portable_sed_inplace "1s|^# .*|${escaped_title}|" "$dst"

  module_files+=("$(basename "$dst")")
  module_titles+=("$name")
  echo "[OK] $dst"
done

if [[ ${#module_files[@]} -eq 0 ]]; then
  dst="$ROOT/core.md"
  cp "$TPL/module-detail.md" "$dst"
  portable_sed_inplace "1s|^# .*|# core 模块文档|" "$dst"
  module_files+=("core.md")
  module_titles+=("core")
  echo "[OK] $dst"
fi

guide="$ROOT/00-reading-guide.md"
if [[ -f "$guide" && $FORCE -ne 1 ]]; then
  echo "[SKIP] exists: $guide"
else
  {
    echo "# ${PROJECT} 文档导航"
    echo
    echo "## 项目级文档"
    echo "- [项目总览](./project-overview.md)"
    echo "- [入门指南（安装与配置）](./getting-started.md)"
    echo "- [功能概括](./feature-summary.md)"
    echo
    echo "## 模块文档"
    for idx in "${!module_files[@]}"; do
      f="${module_files[$idx]}"
      title="${module_titles[$idx]:-${f%.md}}"
      echo "- [${title}](./${f})"
    done
  } > "$guide"
  echo "[OK] $guide"
fi

if command -v rg >/dev/null 2>&1; then
  escaped_project="$(escape_sed_replacement "$PROJECT")"
  while IFS= read -r file; do
    portable_sed_inplace "s|{{ProjectName}}|${escaped_project}|g" "$file"
  done < <(rg -F -l '{{ProjectName}}' "$ROOT")
fi

echo "Scaffolded: $ROOT"
