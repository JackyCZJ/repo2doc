#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/scripts}"

# 断言文件存在且包含关键文本，便于快速定位回归问题。
assert_file_contains() {
  local file="$1"
  local pattern="$2"

  if [[ ! -f "$file" ]]; then
    echo "[FAIL] expected file missing: $file" >&2
    exit 1
  fi

  if ! grep -Fq "$pattern" "$file"; then
    echo "[FAIL] expected pattern not found in $file: $pattern" >&2
    echo "------ file content ------" >&2
    cat "$file" >&2
    echo "--------------------------" >&2
    exit 1
  fi
}

# 断言命令应失败，用于验证门禁参数是否生效。
assert_command_fails() {
  local desc="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    echo "[FAIL] command should fail but succeeded: $desc" >&2
    exit 1
  fi

  echo "[OK] expected failure: $desc"
}

TMP_DIR="$(mktemp -d /tmp/repo2doc-smoke.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[INFO] tmp dir: $TMP_DIR"

assert_command_fails "discover invalid --top" \
  "$SCRIPT_DIR/discover-modules.sh" "$REPO_ROOT" --top nope

discover_csv="$("$SCRIPT_DIR"/discover-modules.sh "$REPO_ROOT" --top 3 --format csv)"
if [[ -z "$discover_csv" ]]; then
  echo "[FAIL] discover csv output is empty" >&2
  exit 1
fi
echo "[OK] discover csv: $discover_csv"

(
  cd /tmp
  "$SCRIPT_DIR/scaffold-report.sh" "DemoDoc" \
    --root "$TMP_DIR" \
    --modules "App,Field"
)

DOC_DIR="$TMP_DIR/DemoDoc"
assert_file_contains "$DOC_DIR/00-reading-guide.md" "# DemoDoc 文档导航"
assert_file_contains "$DOC_DIR/00-reading-guide.md" "[项目总览](./project-overview.md)"
assert_file_contains "$DOC_DIR/00-reading-guide.md" "[入门指南（安装与配置）](./getting-started.md)"
assert_file_contains "$DOC_DIR/00-reading-guide.md" "[功能概括](./feature-summary.md)"
assert_file_contains "$DOC_DIR/00-reading-guide.md" "[App](./app.md)"
assert_file_contains "$DOC_DIR/00-reading-guide.md" "[Field](./field.md)"

assert_file_contains "$DOC_DIR/app.md" "### 3.4 涉及模块"
assert_file_contains "$DOC_DIR/app.md" "#### 模块：模块 A"

"$SCRIPT_DIR/validate-report.sh" "DemoDoc" --root "$TMP_DIR" >/dev/null
echo "[OK] validate warn-only mode succeeded"

assert_command_fails "validate strict enforce should fail for untouched scaffold" \
  "$SCRIPT_DIR/validate-report.sh" "DemoDoc" --root "$TMP_DIR" --strict --depth-profile audit --enforce

assert_command_fails "validate enforce should fail when feature section threshold is too high" \
  "$SCRIPT_DIR/validate-report.sh" "DemoDoc" --root "$TMP_DIR" --enforce --min-feature-sections 10

echo "本文档由 skill 生成" >> "$DOC_DIR/app.md"
assert_command_fails "validate enforce should fail on process/tool trace text" \
  "$SCRIPT_DIR/validate-report.sh" "DemoDoc" --root "$TMP_DIR" --enforce

# Test analyze-module.sh
analyze_output=$("$SCRIPT_DIR/analyze-module.sh" "$REPO_ROOT" scripts --output-format bash 2>/dev/null)
if [[ -z "$analyze_output" ]]; then
  echo "[FAIL] analyze-module output is empty" >&2
  exit 1
fi
if ! echo "$analyze_output" | grep -q "MODULE_NAME="; then
  echo "[FAIL] analyze-module output missing MODULE_NAME" >&2
  exit 1
fi
echo "[OK] analyze-module bash output"

analyze_json=$("$SCRIPT_DIR/analyze-module.sh" "$REPO_ROOT" scripts --output-format json 2>/dev/null)
if ! echo "$analyze_json" | grep -q '"module":'; then
  echo "[FAIL] analyze-module json output missing module field" >&2
  exit 1
fi
echo "[OK] analyze-module json output"

echo "[PASS] repo2doc smoke tests passed"
