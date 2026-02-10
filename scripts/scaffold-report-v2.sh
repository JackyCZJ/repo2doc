#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SCRIPT_DIR%/scripts}"

usage() {
  cat <<'USAGE'
Usage:
  scaffold-report-v2.sh <ProjectName> [options]

Options:
  --root <dir>               Output root (default: Report)
  --repo <path>              Repository path (required for smart scaffold)
  --modules <csv>            Comma-separated module names (auto-detect if omitted)
  --auto-modules <n>         Auto-pick top N modules by LOC (default: 6)
  --smart                    Enable smart analysis to pre-fill content
  --force                    Overwrite existing files
  -h, --help                 Show help

Examples:
  scaffold-report-v2.sh EasyTier --repo /path/to/easytier --smart
  scaffold-report-v2.sh MyProject --repo /path/to/repo --modules core,web --smart
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PROJECT="$1"
shift

ROOT_BASE="Report"
REPO_PATH=""
MODULES=""
AUTO_MODULES=6
SMART=0
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
    --repo)
      require_option_value "$1" "${2-}"
      REPO_PATH="$2"
      shift 2
      ;;
    --modules)
      require_option_value "$1" "${2-}"
      MODULES="$2"
      shift 2
      ;;
    --auto-modules)
      require_option_value "$1" "${2-}"
      AUTO_MODULES="$2"
      shift 2
      ;;
    --smart)
      SMART=1
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

if [[ -z "$REPO_PATH" ]]; then
  echo "[FAIL] --repo <path> is required" >&2
  exit 2
fi

if [[ ! -d "$REPO_PATH" ]]; then
  echo "[FAIL] repo path not found: $REPO_PATH" >&2
  exit 2
fi

REPO_PATH="$(cd "$REPO_PATH" && pwd -P)"
ROOT="${ROOT_BASE}/${PROJECT}"
mkdir -p "$ROOT"

# Auto-discover modules if not specified
if [[ -z "$MODULES" && $AUTO_MODULES -gt 0 ]]; then
  DISCOVER_SCRIPT="$SCRIPT_DIR/discover-modules.sh"
  if [[ -x "$DISCOVER_SCRIPT" ]]; then
    MODULES="$($DISCOVER_SCRIPT "$REPO_PATH" --top "$AUTO_MODULES" --format csv)"
    echo "[OK] auto-discovered modules: $MODULES"
  else
    echo "[WARN] discover-modules.sh not found, using default: core"
    MODULES="core"
  fi
fi

if [[ -z "$MODULES" ]]; then
  MODULES="core"
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

portable_sed_inplace() {
  local expr="$1"
  local target="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i -e "$expr" "$target"
  else
    sed -i '' -e "$expr" "$target"
  fi
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\&/g'
}

# Generate smart module content
generate_smart_module_doc() {
  local module_name="$1"
  local output_file="$2"

  if [[ $SMART -eq 0 ]]; then
    # Fall back to basic template
    cat "$SKILL_DIR/templates/module-detail.md" > "$output_file"
    return
  fi

  # Analyze module
  local analysis
  if ! analysis="$($SCRIPT_DIR/analyze-module.sh "$REPO_PATH" "$module_name" --output-format bash 2>/dev/null)"; then
    echo "[WARN] analysis failed for $module_name, using basic template"
    cat "$SKILL_DIR/templates/module-detail.md" > "$output_file"
    return
  fi

  # Parse analysis results
  local total_lines=$(echo "$analysis" | grep "^TOTAL_LINES=" | cut -d= -f2 || echo "0")
  local file_count=$(echo "$analysis" | grep "^FILE_COUNT=" | cut -d= -f2 || echo "0")
  local complexity=$(echo "$analysis" | grep "^COMPLEXITY=" | cut -d= -f2 | tr -d "'" || echo "medium")
  local lang=$(echo "$analysis" | grep "^LANG=" | cut -d= -f2 | tr -d "'" || echo "rust")

  # Get features
  local features=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^FEATURE= ]]; then
      features+=("$(echo "$line" | cut -d= -f2 | tr -d "'")")
    fi
  done <<< "$analysis"

  # Get public items
  local items=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^ITEM= ]]; then
      items+=("$(echo "$line" | cut -d= -f2- | tr -d "'")")
    fi
  done <<< "$analysis"

  # Generate document
  cat > "$output_file" << EOF
# ${module_name} 模块

## 模块定位

${module_name} 是 ${PROJECT} 项目的核心模块之一，包含 ${file_count} 个源文件，约 ${total_lines} 行代码。

该模块主要负责实现 ${features[0]:-${module_name}} 相关功能。

## 功能概括

| 功能 | 说明 | 关键文件 |
|------|------|----------|
EOF

  # Add feature table rows
  local idx=1
  for feat in "${features[@]}"; do
    if [[ $idx -le 5 && -n "$feat" ]]; then
      echo "| ${feat} | 待补充 | 待补充 |" >> "$output_file"
      idx=$((idx + 1))
    fi
  done

  # Add complexity-based feature sections
  local section_num=3
  for feat in "${features[@]}"; do
    if [[ -z "$feat" ]]; then
      continue
    fi

    # Limit sections based on complexity
    if [[ "$complexity" == "simple" && $section_num -gt 4 ]]; then
      break
    elif [[ "$complexity" == "medium" && $section_num -gt 5 ]]; then
      break
    elif [[ $section_num -gt 7 ]]; then
      break
    fi

    cat >> "$output_file" << EOF

## 功能点：${feat}

### 实现细节

${feat} 功能的实现涉及以下关键组件：

1. **组件一**：待补充
2. **组件二**：待补充
3. **组件三**：待补充

### 设计原理

- **设计原则一**：待补充
- **设计原则二**：待补充

### 关键代码片段

\`\`\`${lang}
# 从源码中提取的关键代码
EOF

    # Add sample code from public items
    local item_idx=0
    for item in "${items[@]}"; do
      if [[ $item_idx -lt 2 && -n "$item" ]]; then
        echo "$item" >> "$output_file"
        item_idx=$((item_idx + 1))
      fi
    done

    cat >> "$output_file" << EOF
\`\`\`

### 涉及模块

#### 模块：${feat// /_}

- **职责**：实现 ${feat} 核心逻辑
- **实现细节**：
  - 待补充
- **设计原理**：
  - 待补充
- **与其他模块协作**：
  - 待补充
EOF

    section_num=$((section_num + 1))
  done

  # Add placeholder if no features found
  if [[ ${#features[@]} -eq 0 ]]; then
    cat >> "$output_file" << 'EOF'

## 功能点：核心功能

### 实现细节

待补充

### 设计原理

待补充

### 关键代码片段

```
待补充
```

### 涉及模块

#### 模块：核心模块

- **职责**：待补充
- **实现细节**：待补充
- **设计原理**：待补充
- **与其他模块协作**：待补充
EOF
  fi

  echo "[OK] smart doc: $output_file (${complexity} complexity, ${#features[@]} features)"
}

# Generate project overview with smart analysis
generate_smart_overview() {
  local output_file="$ROOT/project-overview.md"

  if [[ -f "$output_file" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $output_file"
    return
  fi

  # Detect project type and language
  local lang="Unknown"
  local build_tool="Unknown"

  if [[ -f "$REPO_PATH/Cargo.toml" ]]; then
    lang="Rust"
    build_tool="Cargo"
  elif [[ -f "$REPO_PATH/go.mod" ]]; then
    lang="Go"
    build_tool="Go Modules"
  elif [[ -f "$REPO_PATH/package.json" ]]; then
    lang="JavaScript/TypeScript"
    build_tool="npm/yarn/pnpm"
  elif [[ -f "$REPO_PATH/pyproject.toml" || -f "$REPO_PATH/setup.py" ]]; then
    lang="Python"
    build_tool="pip/setuptools/poetry"
  elif [[ -f "$REPO_PATH/pom.xml" ]]; then
    lang="Java"
    build_tool="Maven"
  fi

  # Get README if exists
  local readme_content=""
  if [[ -f "$REPO_PATH/README.md" ]]; then
    readme_content=$(head -50 "$REPO_PATH/README.md" 2>/dev/null | sed 's/^# //' | head -20)
  elif [[ -f "$REPO_PATH/README_CN.md" ]]; then
    readme_content=$(head -50 "$REPO_PATH/README_CN.md" 2>/dev/null | sed 's/^# //' | head -20)
  fi

  cat > "$output_file" << EOF
# 项目总览

## 1. 项目定位

${PROJECT} 是一个使用 ${lang} 开发的项目。

${readme_content}

## 2. 核心场景

待补充

## 3. 架构总览

\`\`\`
${PROJECT} 项目结构
├── 模块一
├── 模块二
└── 模块三
\`\`\`

## 4. 关键目录说明

\`\`\`
${PROJECT}/
├── src/                    # 源代码
├── tests/                  # 测试代码
└── docs/                   # 文档
\`\`\`

## 5. 技术栈

| 类别 | 技术 | 用途 |
|------|------|------|
| 语言 | ${lang} | 主要开发语言 |
| 构建 | ${build_tool} | 构建工具 |

## 6. 版本信息

- **版本**：待补充
- **主要语言**：${lang}
- **许可证**：待补充
EOF

  echo "[OK] $output_file"
}

# Generate smart getting started
generate_smart_getting_started() {
  local output_file="$ROOT/getting-started.md"

  if [[ -f "$output_file" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $output_file"
    return
  fi

  # Detect install methods from repo
  local has_cargo=0
  local has_npm=0
  local has_docker=0
  local has_script=0

  if [[ -f "$REPO_PATH/Cargo.toml" ]]; then
    has_cargo=1
  fi
  if [[ -f "$REPO_PATH/package.json" ]]; then
    has_npm=1
  fi
  if [[ -f "$REPO_PATH/Dockerfile" || -f "$REPO_PATH/docker-compose.yml" ]]; then
    has_docker=1
  fi
  if [[ -d "$REPO_PATH/script" || -f "$REPO_PATH/install.sh" ]]; then
    has_script=1
  fi

  cat > "$output_file" << 'EOF'
# 入门指南（安装与配置）

## 1. 环境要求

### 系统要求

| 平台 | 最低版本 | 架构 |
|------|---------|------|
| Linux | 待补充 | x86_64, ARM64 |
| macOS | 待补充 | x86_64, ARM64 |
| Windows | 待补充 | x86_64 |

### 构建依赖

- 待补充

## 2. 安装步骤

EOF

  local method_num=1
  if [[ $has_script -eq 1 ]]; then
    cat >> "$output_file" << EOF

### 方法一：使用安装脚本（推荐）

\`\`\`bash
# 下载并运行安装脚本
curl -fsSL https://example.com/install.sh | bash
\`\`\`

EOF
    method_num=$((method_num + 1))
  fi

  if [[ $has_cargo -eq 1 ]]; then
    cat >> "$output_file" << 'EOF'

### 方法二：使用 Cargo 安装

```bash
# 从 crates.io 安装
cargo install PROJECT_NAME

# 或从源码安装
git clone https://github.com/user/PROJECT_NAME
cd PROJECT_NAME
cargo install --path .
```

EOF
    method_num=$((method_num + 1))
  fi

  if [[ $has_npm -eq 1 ]]; then
    cat >> "$output_file" << 'EOF'

### 方法三：使用 npm 安装

```bash
npm install -g PROJECT_NAME
```

EOF
    method_num=$((method_num + 1))
  fi

  if [[ $has_docker -eq 1 ]]; then
    cat >> "$output_file" << 'EOF'

### 方法四：使用 Docker

```bash
# 拉取镜像
docker pull PROJECT_NAME:latest

# 运行容器
docker run -d --name PROJECT_NAME PROJECT_NAME:latest
```

EOF
    method_num=$((method_num + 1))
  fi

  cat >> "$output_file" << 'EOF'

### 方法五：从源码构建

```bash
# 克隆仓库
git clone https://github.com/user/PROJECT_NAME
cd PROJECT_NAME

# 构建项目
# 待补充具体构建命令
```

## 3. 配置说明

### 配置文件格式

待补充

### 环境变量

| 变量 | 说明 |
|------|------|
| 待补充 | 待补充 |

## 4. 启动与验证

### 快速启动

```bash
# 待补充启动命令
```

### 验证安装

```bash
# 待补充验证命令
```

## 5. 常见问题

### Q: 安装失败怎么办？

待补充

### Q: 如何配置开机自启？

待补充
EOF

  echo "[OK] $output_file"
}

# Generate smart feature summary
generate_smart_feature_summary() {
  local output_file="$ROOT/feature-summary.md"

  if [[ -f "$output_file" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $output_file"
    return
  fi

  cat > "$output_file" << 'EOF'
# 功能概括

## 1. 主要功能清单

| 功能类别 | 功能说明 | 对应模块 |
|---------|---------|---------|
| 核心功能 | 待补充 | 待补充 |
| 扩展功能 | 待补充 | 待补充 |

## 2. 功能分层

```
┌─────────────────────────────────────┐
│           应用层 (Application)        │
├─────────────────────────────────────┤
│           控制层 (Control)            │
├─────────────────────────────────────┤
│           网络层 (Network)            │
├─────────────────────────────────────┤
│           传输层 (Transport)          │
├─────────────────────────────────────┤
│           链路层 (Link)               │
└─────────────────────────────────────┘
```

## 3. 典型使用流程

### 流程一：快速开始

待补充

### 流程二：高级配置

待补充

## 4. 功能依赖关系

待补充
EOF

  echo "[OK] $output_file"
}

# Generate reading guide
generate_reading_guide() {
  local guide="$ROOT/00-reading-guide.md"

  if [[ -f "$guide" && $FORCE -ne 1 ]]; then
    echo "[SKIP] exists: $guide"
    return
  fi

  {
    echo "# ${PROJECT} 文档导航"
    echo ""
    echo "## 文档简介"
    echo ""
    echo "本文档是 ${PROJECT} 项目的结构化技术文档。"
    echo ""
    echo "## 阅读指南"
    echo ""
    echo "### 快速开始"
    echo ""
    echo "1. **[项目总览](./project-overview.md)** - 了解项目是什么"
    echo "2. **[入门指南](./getting-started.md)** - 安装和启动"
    echo "3. **[功能概括](./feature-summary.md)** - 了解功能"
    echo ""
    echo "### 深入模块"
    echo ""

    IFS=',' read -r -a module_names <<< "$MODULES"
    for raw_name in "${module_names[@]}"; do
      name=$(printf '%s' "$raw_name" | sed -E 's/^ +//; s/ +$//')
      [[ -z "$name" ]] && continue
      slug=$(slugify "$name")
      echo "- [${name}](./${slug}.md)"
    done

    echo ""
    echo "## 术语表"
    echo ""
    echo "| 术语 | 说明 |"
    echo "|------|------|"
    echo "| 待补充 | 待补充 |"
  } > "$guide"

  echo "[OK] $guide"
}

# Main execution
echo "=== Smart Scaffold for ${PROJECT} ==="
echo ""

generate_smart_overview
generate_smart_getting_started
generate_smart_feature_summary

# Generate module docs
IFS=',' read -r -a module_names <<< "$MODULES"
declare -a used_slugs=()

for raw_name in "${module_names[@]}"; do
  name=$(printf '%s' "$raw_name" | sed -E 's/^ +//; s/ +$//')
  [[ -z "$name" ]] && continue

  slug=$(slugify "$name")

  # Handle duplicate slugs
  suffix=2
  while [[ " ${used_slugs[*]} " =~ " ${slug} " ]]; do
    slug="${slug}-${suffix}"
    suffix=$((suffix + 1))
  done
  used_slugs+=("$slug")

  dst="$ROOT/${slug}.md"
  generate_smart_module_doc "$name" "$dst"
done

generate_reading_guide

echo ""
echo "=== Scaffold completed: $ROOT ==="

# Run validation if available
if [[ -x "$SCRIPT_DIR/validate-report.sh" ]]; then
  echo ""
  echo "=== Running validation ==="
  "$SCRIPT_DIR/validate-report.sh" "$PROJECT" --root "$ROOT_BASE" || true
fi
