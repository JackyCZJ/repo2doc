#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scaffold-report.sh <ProjectName> [options]

Options:
  --root <dir>               Output root (default: Report)
  --modules <csv>            Comma-separated module names (default: core)
  --repo <path>              Repository path (used by --auto-modules)
  --auto-modules <n>         Auto-pick top N modules by LOC from repo
  --lang <lang>              Output language: zh|en (default: zh)
  --minimal                  Create minimal scaffold (empty files only)
  --force                    Overwrite existing files
  -h, --help                 Show help

Examples:
  scaffold-report.sh tvscreener --modules app,field
  scaffold-report.sh tvscreener --repo /path/to/repo --auto-modules 6
  scaffold-report.sh tvscreener --lang en --modules core
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
MODULES="core"
REPO_PATH=""
AUTO_MODULES=0
LANG="zh"
MINIMAL=0
FORCE=0

require_option_value() {
  local option="$1"
  local value="${2-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    echo "[FAIL] missing value for ${option}" >&2
    exit 2
  fi
}

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
    --lang)
      require_option_value "$1" "${2-}"
      LANG="$2"
      shift 2
      ;;
    --minimal)
      MINIMAL=1
      shift
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

case "$LANG" in
  zh|en)
    ;;
  *)
    echo "[FAIL] unsupported language: $LANG (must be 'zh' or 'en')" >&2
    exit 2
    ;;
esac

ROOT="${ROOT_BASE}/${PROJECT}"
mkdir -p "$ROOT"

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

create_file() {
  local dst="$1"
  local content="$2"

  if [[ -f "$dst" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $dst"
    return
  fi

  printf '%s' "$content" > "$dst"
  echo "[OK] $dst"
}

generate_project_overview() {
  if [[ "$LANG" == "en" ]]; then
    cat <<'EOF'
# Project Overview

## 1. Project Positioning

One-sentence description of the core problem this project solves.

- Target users:
- Core scenarios:
- Differentiation:

## 2. Architecture Overview

```
[External Systems/Users]
      │
      ▼
[Entry/API Layer] ──→ [Core Business Layer] ──→ [Data/Storage Layer]
                          │
                          ▼
                    [Infrastructure/Utils Layer]
```

Key data flows:
1.
2.

## 3. Key Directory Structure

| Directory | Description | Responsibility |
|-----------|-------------|----------------|
| `src/` | Main source directory | Core business logic |
| ... | ... | ... |

## 4. Tech Stack

- Language:
- Build tool:
- Core dependencies:

EOF
  else
    cat <<'EOF'
# 项目总览

## 1. 项目定位

一句话描述项目解决的核心问题。

- 目标用户：
- 核心场景：
- 差异化：

## 2. 架构总览

```
[外部系统/用户]
      │
      ▼
[入口层/API层] ──→ [核心业务层] ──→ [数据/存储层]
                          │
                          ▼
                    [基础设施/工具层]
```

关键数据流：
1.
2.

## 3. 关键目录说明

| 目录 | 说明 | 对应职责 |
|------|------|----------|
| `src/` | 源代码主目录 | 核心业务实现 |
| ... | ... | ... |

## 4. 技术栈

- 语言：
- 构建工具：
- 核心依赖：

EOF
  fi
}

generate_getting_started() {
  if [[ "$LANG" == "en" ]]; then
    cat <<'EOF'
# Getting Started

## 1. Environment Requirements

| Dependency | Version | Required/Optional | Notes |
|------------|---------|-------------------|-------|
| | | | |

## 2. Installation

### From Source

```bash
git clone <repo-url>
cd
```

### Package Manager

```bash

```

## 3. Configuration

- Global config:
- Project config:

## 4. Verification

```bash
# Check version

# Run tests

```

## 5. FAQ

EOF
  else
    cat <<'EOF'
# 入门指南

## 1. 环境要求

| 依赖 | 版本 | 必需/可选 | 说明 |
|------|------|-----------|------|
| | | | |

## 2. 安装步骤

### 从源码安装

```bash
git clone <repo-url>
cd
```

### 包管理器安装

```bash

```

## 3. 配置说明

- 全局配置：
- 项目配置：

## 4. 验证安装

```bash
# 检查版本

# 运行测试

```

## 5. 常见问题

EOF
  fi
}

generate_feature_summary() {
  if [[ "$LANG" == "en" ]]; then
    cat <<'EOF'
# Feature Summary

## 1. Feature List

| Feature | Description | Status | Module |
|---------|-------------|--------|--------|
| | | | |

## 2. Feature Layers

- **User Layer (CLI/API/UI)**:
- **Business Logic Layer**:
- **Infrastructure Layer**:

## 3. Typical Workflows

### Workflow 1:

1.
2.
3.

## 4. Feature Dependencies

EOF
  else
    cat <<'EOF'
# 功能概括

## 1. 功能清单

| 功能 | 说明 | 状态 | 对应模块 |
|------|------|------|----------|
| | | | |

## 2. 功能分层

- **用户层（CLI/API/界面）**：
- **业务逻辑层**：
- **基础设施层**：

## 3. 典型流程

### 流程 1：

1.
2.
3.

## 4. 功能依赖

EOF
  fi
}

generate_module_doc() {
  local name="$1"
  if [[ "$LANG" == "en" ]]; then
    cat <<EOF
# ${name} Module

## 1. Module Positioning

- Position in architecture:
- Core responsibilities:
- Relations with upstream/downstream modules:

## 2. Feature Summary

| Feature | Description |
|---------|-------------|
| | |

## 3. Feature: <name>

### Implementation Details

- Entry point/interface:
- Core algorithm/flow:
- Key data structures:
- State management:

### Design Principles

- Why this design:
- Trade-offs considered:
- Core problem solved:

### Key Code Snippets

\`\`\`

\`\`\`

### Involved Modules

#### Module: <name>

- **Responsibility**:
- **Implementation Details**:
- **Design Principles**:
- **Collaboration**:

EOF
  else
    cat <<EOF
# ${name} 模块

## 1. 模块定位

- 在架构中的位置：
- 核心职责：
- 与上下游模块的关系：

## 2. 功能概括

| 功能点 | 一句话描述 |
|--------|------------|
| | |

## 3. 功能点：<名称>

### 实现细节

- 入口点/对外接口：
- 核心算法或处理流程：
- 关键数据结构：
- 状态管理策略：

### 设计原理

- 为什么这样设计：
- 权衡了哪些方案：
- 解决了什么核心问题：

### 关键代码片段

\`\`\`

\`\`\`

### 涉及模块

#### 模块：<名称>

- **职责**：
- **实现细节**：
- **设计原理**：
- **协作关系**：

EOF
  fi
}

generate_reading_guide() {
  local module_files=("$@")
  if [[ "$LANG" == "en" ]]; then
    {
      echo "# ${PROJECT} Documentation Guide"
      echo
      echo "## Project-Level Documents"
      echo "- [Project Overview](./project-overview.md)"
      echo "- [Getting Started (Installation & Configuration)](./getting-started.md)"
      echo "- [Feature Summary](./feature-summary.md)"
      echo
      echo "## Module Documents"
      for f in "${module_files[@]}"; do
        local title="${f%.md}"
        echo "- [${title}](./${f})"
      done
    }
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
      for f in "${module_files[@]}"; do
        local title="${f%.md}"
        echo "- [${title}](./${f})"
      done
    }
  fi
}

# Create project-level documents
if [[ $MINIMAL -eq 1 ]]; then
  create_file "$ROOT/project-overview.md" "# $(if [[ "$LANG" == "en" ]]; then echo "Project Overview"; else echo "项目总览"; fi)\n\n"
  create_file "$ROOT/getting-started.md" "# $(if [[ "$LANG" == "en" ]]; then echo "Getting Started"; else echo "入门指南"; fi)\n\n"
  create_file "$ROOT/feature-summary.md" "# $(if [[ "$LANG" == "en" ]]; then echo "Feature Summary"; else echo "功能概括"; fi)\n\n"
else
  create_file "$ROOT/project-overview.md" "$(generate_project_overview)"
  create_file "$ROOT/getting-started.md" "$(generate_getting_started)"
  create_file "$ROOT/feature-summary.md" "$(generate_feature_summary)"
fi

declare -a module_files=()
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
    continue
  fi

  if [[ $MINIMAL -eq 1 ]]; then
    if [[ "$LANG" == "en" ]]; then
      create_file "$dst" "# ${name} Module\n\n"
    else
      create_file "$dst" "# ${name} 模块\n\n"
    fi
  else
    create_file "$dst" "$(generate_module_doc "$name")"
  fi
  module_files+=("$(basename "$dst")")
done

if [[ ${#module_files[@]} -eq 0 ]]; then
  dst="$ROOT/core.md"
  if [[ $MINIMAL -eq 1 ]]; then
    if [[ "$LANG" == "en" ]]; then
      create_file "$dst" "# core Module\n\n"
    else
      create_file "$dst" "# core 模块\n\n"
    fi
  else
    create_file "$dst" "$(generate_module_doc "core")"
  fi
  module_files+=("core.md")
fi

guide="$ROOT/00-reading-guide.md"
if [[ -f "$guide" && $FORCE -ne 1 ]]; then
  echo "[SKIP] exists: $guide"
else
  generate_reading_guide "${module_files[@]}" > "$guide"
  echo "[OK] $guide"
fi

echo "Scaffolded: $ROOT"
echo ""
echo "Next steps:"
if [[ "$LANG" == "en" ]]; then
  echo "  1. Edit project-overview.md - define project positioning and architecture"
  echo "  2. Edit getting-started.md - add installation and setup steps"
  echo "  3. Edit feature-summary.md - list and categorize features"
  echo "  4. Edit module docs - document implementation details and design principles"
  echo "  5. Run: scripts/validate-report.sh ${PROJECT} --strict --enforce"
else
  echo "  1. 编辑 project-overview.md - 定义项目定位和架构"
  echo "  2. 编辑 getting-started.md - 添加安装和配置步骤"
  echo "  3. 编辑 feature-summary.md - 列出并分类功能"
  echo "  4. 编辑模块文档 - 记录实现细节和设计原理"
  echo "  5. 运行: scripts/validate-report.sh ${PROJECT} --strict --enforce"
fi
