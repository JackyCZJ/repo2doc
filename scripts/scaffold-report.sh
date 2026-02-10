#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scaffold-report.sh <ProjectName> [options]

Options:
  --root <dir>               Output root (default: Report)
  --template-root <dir>      Template root (default: skills/repo2doc/templates)
  --adaptive <csv>           Comma-separated adaptive sections to create
                             Supported: layered,temporal,state-machine,mechanism,flow
  --with-supporting          Also scaffold 01~08 supporting chapters
  --force                    Overwrite existing files
  -h, --help                 Show help

Examples:
  scaffold-report.sh pi-mono
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
ADAPTIVE=""
WITH_SUPPORTING=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_BASE="$2"; shift 2 ;;
    --template-root)
      TPL="$2"; shift 2 ;;
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

copy_template() {
  local src="$1"
  local dst="$2"

  if [[ -f "$dst" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $dst"
    return
  fi

  cp "$src" "$dst"
  echo "[OK] $dst"
}

require_template() {
  local file="$1"
  if [[ ! -f "$TPL/$file" ]]; then
    echo "Missing template: $TPL/$file" >&2
    exit 3
  fi
}

# Minimum contract
for file in \
  00-reading-guide.md \
  A-01-getting-started.md \
  B-01-deep-dive.md \
  appendix-source-index.md; do
  require_template "$file"
  copy_template "$TPL/$file" "$ROOT/$file"
done

# Optional adaptive sections
if [[ -n "$ADAPTIVE" ]]; then
  IFS=',' read -r -a sections <<< "$ADAPTIVE"
  for section in "${sections[@]}"; do
    case "$section" in
      layered)
        require_template "B-02-layered-highlights-and-hardparts.md"
        copy_template "$TPL/B-02-layered-highlights-and-hardparts.md" "$ROOT/B-02-layered-highlights-and-hardparts.md"
        ;;
      temporal)
        cat > "$ROOT/B-10-temporal-behavior.md" <<'EOF'
# B-10 时态行为深析（超时 / 重试 / 顺序 / 并发）

## 1) 时间语义与约束
## 2) 核心时态机制
## 3) 风险与验证建议
EOF
        echo "[OK] $ROOT/B-10-temporal-behavior.md"
        ;;
      state-machine)
        cat > "$ROOT/B-11-state-machine-analysis.md" <<'EOF'
# B-11 状态机深析

## 1) 状态集合与转移条件
## 2) 事件触发与异常分支
## 3) Mermaid 状态图 + 关键实现出处
EOF
        echo "[OK] $ROOT/B-11-state-machine-analysis.md"
        ;;
      mechanism)
        cat > "$ROOT/B-12-mechanism-implementation.md" <<'EOF'
# B-12 机制实现深析

## 1) 机制定义与边界
## 2) 关键实现卡片（What/Where/How/Why）
## 3) 机制演进建议
EOF
        echo "[OK] $ROOT/B-12-mechanism-implementation.md"
        ;;
      flow)
        cat > "$ROOT/B-13-mechanism-flow.md" <<'EOF'
# B-13 机制流程深析

## 1) 触发 -> 入口 -> 编排 -> 外部交互 -> 收敛
## 2) 失败路径与补偿逻辑
## 3) Mermaid 时序图 + 代码出处
EOF
        echo "[OK] $ROOT/B-13-mechanism-flow.md"
        ;;
      *)
        echo "[WARN] unsupported adaptive section: $section"
        ;;
    esac
  done
fi

# Optional supporting chapters
if [[ $WITH_SUPPORTING -eq 1 ]]; then
  for n in 01-system-overview 02-module-map 03-core-flows 04-deep-dives 05-data-and-state 06-runtime-and-config 07-risks-and-techdebt 08-optimization-roadmap; do
    file="$ROOT/${n}.md"
    if [[ -f "$file" && $FORCE -ne 1 ]]; then
      echo "[SKIP] exists: $file"
      continue
    fi
    cat > "$file" <<EOF
# ${n}

## Objective

## Key findings

## Evidence map

## Implications

## Open questions
EOF
    echo "[OK] $file"
  done
fi

# Placeholder replacement (portable for macOS sed)
sed -i '' "s/{{ProjectName}}/${PROJECT}/g" "$ROOT/00-reading-guide.md" || true

echo "Scaffolded: $ROOT"
