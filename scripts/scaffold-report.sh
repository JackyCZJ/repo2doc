#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scaffold-report.sh <ProjectName> [options]

Options:
  --root <dir>               Output root (default: Report)
  --template-root <dir>      Template root (default: skills/repo2doc/templates)
  --modules <csv>            Comma-separated module names (default: core)
  --adaptive <csv>           Comma-separated adaptive sections to create
                             Supported: layered,temporal,state-machine,mechanism,flow
  --with-supporting          Also scaffold supporting chapters
  --force                    Overwrite existing files
  -h, --help                 Show help

Examples:
  scaffold-report.sh pi-mono --modules api,worker,scheduler
  scaffold-report.sh pi-mono --adaptive layered,state-machine,flow
  scaffold-report.sh pi-mono --with-supporting --force
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PROJECT="$1"
shift

ROOT_BASE="Report"
TPL="skills/repo2doc/templates"
MODULES="core"
ADAPTIVE=""
WITH_SUPPORTING=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_BASE="$2"; shift 2 ;;
    --template-root)
      TPL="$2"; shift 2 ;;
    --modules)
      MODULES="$2"; shift 2 ;;
    --adaptive)
      ADAPTIVE="$2"; shift 2 ;;
    --with-supporting)
      WITH_SUPPORTING=1; shift ;;
    --force)
      FORCE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2 ;;
  esac
done

ROOT="${ROOT_BASE}/${PROJECT}"
mkdir -p "$ROOT"

slugify() {
  local input="$1"
  local slug
  slug=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  if [[ -z "$slug" ]]; then
    slug="module"
  fi
  printf '%s\n' "$slug"
}

write_text() {
  local dst="$1"
  local content="$2"

  if [[ -f "$dst" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $dst"
    return
  fi

  printf '%s\n' "$content" > "$dst"
  echo "[OK] $dst"
}

copy_or_fallback() {
  local template="$1"
  local dst="$2"
  local fallback="$3"

  if [[ -f "$dst" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $dst"
    return
  fi

  if [[ -f "$TPL/$template" ]]; then
    cp "$TPL/$template" "$dst"
  else
    printf '%s\n' "$fallback" > "$dst"
  fi

  echo "[OK] $dst"
}

# Core docs (semantic names, not template names)
copy_or_fallback \
  "A-01-getting-started.md" \
  "$ROOT/project-overview.md" \
  "# 项目概览与快速开始

## 1) 项目是什么

## 2) 安装

## 3) 基础使用

## 4) 基础 QA

## 5) 入门建议路线"

copy_or_fallback \
  "appendix-source-index.md" \
  "$ROOT/appendix-source-index.md" \
  "# 源码证据索引

| 结论ID | 证据路径 | 说明 |
|---|---|---|"

declare -a module_files=()
declare -a used_slugs=()

slug_used() {
  local target="$1"
  local existing
  for existing in "${used_slugs[@]-}"; do
    if [[ "$existing" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

IFS=',' read -r -a module_names <<< "$MODULES"
for raw_name in "${module_names[@]}"; do
  name=$(printf '%s' "$raw_name" | sed -E 's/^ +//; s/ +$//')
  [[ -z "$name" ]] && continue

  slug=$(slugify "$name")
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
    continue
  fi

  if [[ -f "$TPL/B-01-deep-dive.md" ]]; then
    cp "$TPL/B-01-deep-dive.md" "$dst"
    sed -i '' "1s|^# .*|# ${name} 模块深度解析|" "$dst"
  else
    cat > "$dst" <<EOF
# ${name} 模块深度解析

## 1) 架构总览

## 2) 难点

## 3) 亮点

## 4) 基于亮点的技术细节展开
EOF
  fi

  module_files+=("$(basename "$dst")")
  echo "[OK] $dst"
done

if [[ ${#module_files[@]} -eq 0 ]]; then
  dst="$ROOT/core.md"
  write_text "$dst" "# core 模块深度解析

## 1) 架构总览

## 2) 难点

## 3) 亮点

## 4) 基于亮点的技术细节展开"
  module_files+=("core.md")
fi

declare -a adaptive_files=()
if [[ -n "$ADAPTIVE" ]]; then
  IFS=',' read -r -a sections <<< "$ADAPTIVE"
  for section in "${sections[@]}"; do
    case "$section" in
      layered)
        dst="$ROOT/layered-highlights-and-hardparts.md"
        if [[ -f "$dst" && $FORCE -ne 1 ]]; then
          echo "[SKIP] exists: $dst"
        elif [[ -f "$TPL/B-02-layered-highlights-and-hardparts.md" ]]; then
          cp "$TPL/B-02-layered-highlights-and-hardparts.md" "$dst"
          echo "[OK] $dst"
        else
          cat > "$dst" <<'EOF'
# 分层深度解析（亮点 / 难点 / 技术细节）

## 1. 分层总图（Mermaid）

## 2. Layer-X

### 职责
### 亮点
### 难点
### 基于亮点的技术细节
EOF
          echo "[OK] $dst"
        fi
        adaptive_files+=("layered-highlights-and-hardparts.md")
        ;;
      temporal)
        dst="$ROOT/temporal-behavior.md"
        write_text "$dst" "# 时态行为深析（超时 / 重试 / 顺序 / 并发）

## 1) 时间语义与约束
## 2) 核心时态机制
## 3) 风险与验证建议"
        adaptive_files+=("temporal-behavior.md")
        ;;
      state-machine)
        dst="$ROOT/state-machine-analysis.md"
        write_text "$dst" "# 状态机深析

## 1) 状态集合与转移条件
## 2) 事件触发与异常分支
## 3) Mermaid 状态图 + 关键实现出处"
        adaptive_files+=("state-machine-analysis.md")
        ;;
      mechanism)
        dst="$ROOT/mechanism-implementation.md"
        write_text "$dst" "# 机制实现深析

## 1) 机制定义与边界
## 2) 关键实现卡片（What/Where/How/Why）
## 3) 机制演进建议"
        adaptive_files+=("mechanism-implementation.md")
        ;;
      flow)
        dst="$ROOT/mechanism-flow.md"
        write_text "$dst" "# 机制流程深析

## 1) 触发 -> 入口 -> 编排 -> 外部交互 -> 收敛
## 2) 失败路径与补偿逻辑
## 3) Mermaid 时序图 + 代码出处"
        adaptive_files+=("mechanism-flow.md")
        ;;
      *)
        echo "[WARN] unsupported adaptive section: $section"
        ;;
    esac
  done
fi

declare -a supporting_files=()
if [[ $WITH_SUPPORTING -eq 1 ]]; then
  chapters=(
    system-overview
    module-map
    core-flows
    deep-dives
    data-and-state
    runtime-and-config
    risks-and-techdebt
    optimization-roadmap
  )

  for chapter in "${chapters[@]}"; do
    file="$ROOT/${chapter}.md"
    if [[ -f "$file" && $FORCE -ne 1 ]]; then
      echo "[SKIP] exists: $file"
      supporting_files+=("$(basename "$file")")
      continue
    fi

    cat > "$file" <<EOF
# ${chapter}

## Objective

## Key findings

## Evidence map

## Implications

## Open questions
EOF

    supporting_files+=("$(basename "$file")")
    echo "[OK] $file"
  done
fi

# Build reading guide from generated docs.
guide="$ROOT/00-reading-guide.md"
if [[ -f "$guide" && $FORCE -ne 1 ]]; then
  echo "[SKIP] exists: $guide"
else
  {
    echo "# ${PROJECT} 报告导航"
    echo
    echo "## 项目概览"
    echo "- [项目概览与快速开始](./project-overview.md)"
    echo
    echo "## 模块深度文档"
    for f in "${module_files[@]}"; do
      title="${f%.md}"
      echo "- [${title}](./${f})"
    done

    if [[ ${#adaptive_files[@]} -gt 0 ]]; then
      echo
      echo "## 自适应专题"
      for f in "${adaptive_files[@]}"; do
        title="${f%.md}"
        echo "- [${title}](./${f})"
      done
    fi

    if [[ ${#supporting_files[@]} -gt 0 ]]; then
      echo
      echo "## 支撑章节"
      for f in "${supporting_files[@]}"; do
        title="${f%.md}"
        echo "- [${title}](./${f})"
      done
    fi

    echo
    echo "## 附录"
    echo "- [源码证据索引](./appendix-source-index.md)"
  } > "$guide"
  echo "[OK] $guide"
fi

# Replace project placeholder if any template still contains it.
if command -v rg >/dev/null 2>&1; then
  while IFS= read -r file; do
    sed -i '' "s/{{ProjectName}}/${PROJECT}/g" "$file"
  done < <(rg -F -l '{{ProjectName}}' "$ROOT")
fi

echo "Scaffolded: $ROOT"