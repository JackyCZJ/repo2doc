#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  analyze-module.sh <repo-path> <module-name> [options]

Options:
  --lang <lang>            Language: rust|go|python|java (auto-detect if omitted)
  --output-format <fmt>    Output: json|markdown|bash (default: bash)
  --max-features <n>       Max features to extract (default: 5)
  --max-lines-per-snippet  Max lines per code snippet (default: 30)
  -h, --help               Show help

Examples:
  analyze-module.sh /path/to/repo easytier
  analyze-module.sh /path/to/repo src/peers --lang rust --output-format json
USAGE
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

REPO_PATH="$1"
MODULE_NAME="$2"
shift 2

OUTPUT_FORMAT="bash"
MAX_FEATURES=5
MAX_LINES=30
LANG=""

require_option_value() {
  local option="$1"
  local value="${2-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    echo "[FAIL] missing value for ${option}" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang)
      require_option_value "$1" "${2-}"
      LANG="$2"
      shift 2
      ;;
    --output-format)
      require_option_value "$1" "${2-}"
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    --max-features)
      require_option_value "$1" "${2-}"
      MAX_FEATURES="$2"
      shift 2
      ;;
    --max-lines-per-snippet)
      require_option_value "$1" "${2-}"
      MAX_LINES="$2"
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

if [[ ! -d "$REPO_PATH" ]]; then
  echo "[FAIL] repo path not found: $REPO_PATH" >&2
  exit 2
fi

REPO_PATH="$(cd "$REPO_PATH" && pwd -P)"

# Auto-detect language if not specified
if [[ -z "$LANG" ]]; then
  if [[ -f "$REPO_PATH/Cargo.toml" ]]; then
    LANG="rust"
  elif [[ -f "$REPO_PATH/go.mod" ]]; then
    LANG="go"
  elif [[ -f "$REPO_PATH/setup.py" || -f "$REPO_PATH/pyproject.toml" || -d "$REPO_PATH/requirements" ]]; then
    LANG="python"
  elif [[ -f "$REPO_PATH/pom.xml" || -f "$REPO_PATH/build.gradle" ]]; then
    LANG="java"
  else
    LANG="rust"
  fi
fi

# Find module directory
find_module_dir() {
  local name="$1"
  local candidates=()

  # Direct match
  if [[ -d "$REPO_PATH/$name" ]]; then
    echo "$REPO_PATH/$name"
    return
  fi

  # src/ subdirectory
  if [[ -d "$REPO_PATH/src/$name" ]]; then
    echo "$REPO_PATH/src/$name"
    return
  fi

  # Search in common locations
  for dir in "$REPO_PATH"/*/"$name" "$REPO_PATH"/crates/*/"$name" "$REPO_PATH"/packages/*/"$name"; do
    if [[ -d "$dir" ]]; then
      echo "$dir"
      return
    fi
  done

  # Partial match
  local found
  found=$(find "$REPO_PATH" -maxdepth 3 -type d -name "*$name*" 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then
    echo "$found"
    return
  fi

  echo ""
}

MODULE_DIR=$(find_module_dir "$MODULE_NAME")
if [[ -z "$MODULE_DIR" ]]; then
  echo "[FAIL] module not found: $MODULE_NAME" >&2
  exit 2
fi

# Get source files based on language
get_source_files() {
  case "$LANG" in
    rust)
      find "$MODULE_DIR" -type f -name "*.rs" ! -name "*.min.rs" 2>/dev/null
      ;;
    go)
      find "$MODULE_DIR" -type f -name "*.go" ! -name "*_test.go" 2>/dev/null
      ;;
    python)
      find "$MODULE_DIR" -type f \( -name "*.py" -o -name "*.pyi" \) 2>/dev/null
      ;;
    java)
      find "$MODULE_DIR" -type f -name "*.java" 2>/dev/null
      ;;
    *)
      find "$MODULE_DIR" -type f \( -name "*.rs" -o -name "*.go" -o -name "*.py" -o -name "*.java" \) 2>/dev/null
      ;;
  esac
}

SOURCE_FILES=$(get_source_files)
# Allow empty source files for directories with only configs
if [[ -z "$SOURCE_FILES" ]]; then
  SOURCE_FILES=""
  TOTAL_LINES=0
  FILE_COUNT=0
  COMPLEXITY="simple"
fi

# Calculate metrics
if [[ -n "$SOURCE_FILES" ]]; then
  TOTAL_LINES=$(echo "$SOURCE_FILES" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
  FILE_COUNT=$(echo "$SOURCE_FILES" | wc -l | tr -d ' ')
else
  TOTAL_LINES=0
  FILE_COUNT=0
fi

# Determine complexity level
if [[ $TOTAL_LINES -lt 500 ]]; then
  COMPLEXITY="simple"
elif [[ $TOTAL_LINES -lt 2000 ]]; then
  COMPLEXITY="medium"
else
  COMPLEXITY="complex"
fi

# Extract public structs/traits/functions based on language
extract_public_items() {
  case "$LANG" in
    rust)
      echo "$SOURCE_FILES" | xargs grep -h "^pub \(struct\|trait\|fn\|enum\|type\|const\)" 2>/dev/null | \
        head -50 | sed 's/{$//' | sed 's/;$//' | awk '{print $2, $0}' | sort | uniq
      ;;
    go)
      echo "$SOURCE_FILES" | xargs grep -h "^func\|^type\|^const\|^var" 2>/dev/null | \
        head -50 | sed 's/ {$//' | awk '{print $2, $0}' | sort | uniq
      ;;
    python)
      echo "$SOURCE_FILES" | xargs grep -h "^class\|^def\|^async def" 2>/dev/null | \
        head -50 | sed 's/:$//' | awk '{print $2, $0}' | sort | uniq
      ;;
    java)
      echo "$SOURCE_FILES" | xargs grep -h "^\s*public\|^\s*class\|^\s*interface" 2>/dev/null | \
        head -50 | sed 's/ {$//' | awk '{print $NF, $0}' | sort | uniq
      ;;
  esac
}

# Extract function signatures with doc comments
extract_documented_items() {
  case "$LANG" in
    rust)
      # Extract items with doc comments (/// or //!)
      echo "$SOURCE_FILES" | while read -r file; do
        awk '
          /^\s*\/\/\/\s*/ { doc = doc $0 "\n"; next }
          /^\s*\/\/\/!\s*/ { doc = doc $0 "\n"; next }
          /^pub (struct|trait|fn|enum)/ {
            if (doc != "") {
              print "DOC:" doc
              doc = ""
            }
            print $0
            print "---"
          }
          { doc = "" }
        ' "$file" 2>/dev/null
      done | head -100
      ;;
    *)
      extract_public_items
      ;;
  esac
}

# Infer feature names from file paths and item names
infer_features() {
  local items="$1"

  # Extract meaningful nouns from file paths and public items
  echo "$SOURCE_FILES" | while read -r file; do
    basename "$file" | sed 's/\.[^.]*$//' | sed 's/_/ /g' | sed 's/-/_/g'
  done | sort | uniq -c | sort -rn | head -20 | awk '{print $2}'

  echo "$items" | while read -r line; do
    if [[ -n "$line" ]]; then
      # Extract name from "name full_definition"
      name=$(echo "$line" | awk '{print $1}')
      # Convert CamelCase or snake_case to words
      echo "$name" | sed 's/\([A-Z]\)/ &/g' | sed 's/_/ /g' | sed 's/^ //'
    fi
  done | sort | uniq -c | sort -rn | head -20 | awk '{print $2}'
}

PUBLIC_ITEMS=$(extract_public_items)
FEATURES=$(infer_features "$PUBLIC_ITEMS" | head -n "$MAX_FEATURES")

# Generate output
generate_bash_output() {
  echo "MODULE_NAME='$MODULE_NAME'"
  echo "MODULE_DIR='$MODULE_DIR'"
  echo "LANG='$LANG'"
  echo "TOTAL_LINES=$TOTAL_LINES"
  echo "FILE_COUNT=$FILE_COUNT"
  echo "COMPLEXITY='$COMPLEXITY'"
  echo ""
  echo "# Features (inferred)"
  echo "$FEATURES" | while read -r feat; do
    if [[ -n "$feat" ]]; then
      echo "FEATURE='$feat'"
    fi
  done
  echo ""
  echo "# Public Items (sample)"
  echo "$PUBLIC_ITEMS" | head -10 | while read -r item; do
    if [[ -n "$item" ]]; then
      echo "ITEM='$item'"
    fi
  done
}

generate_json_output() {
  echo "{"
  echo "  \"module\": \"$MODULE_NAME\","
  echo "  \"directory\": \"$MODULE_DIR\","
  echo "  \"language\": \"$LANG\","
  echo "  \"metrics\": {"
  echo "    \"total_lines\": $TOTAL_LINES,"
  echo "    \"file_count\": $FILE_COUNT,"
  echo "    \"complexity\": \"$COMPLEXITY\""
  echo "  },"
  echo "  \"features\": ["
  local first=1
  echo "$FEATURES" | while read -r feat; do
    if [[ -n "$feat" ]]; then
      if [[ $first -eq 1 ]]; then
        first=0
      else
        echo ","
      fi
      echo -n "    \"$feat\""
    fi
  done
  echo ""
  echo "  ],"
  echo "  \"public_items\": ["
  first=1
  echo "$PUBLIC_ITEMS" | head -20 | while read -r item; do
    if [[ -n "$item" ]]; then
      if [[ $first -eq 1 ]]; then
        first=0
      else
        echo ","
      fi
      name=$(echo "$item" | awk '{print $1}')
      def=$(echo "$item" | cut -d' ' -f2-)
      echo -n "    {\"name\": \"$name\", \"definition\": \"$def\"}"
    fi
  done
  echo ""
  echo "  ]"
  echo "}"
}

generate_markdown_output() {
  echo "## 模块分析: $MODULE_NAME"
  echo ""
  echo "### 基本信息"
  echo ""
  echo "| 属性 | 值 |"
  echo "|------|-----|"
  echo "| 语言 | $LANG |"
  echo "| 代码行数 | $TOTAL_LINES |"
  echo "| 文件数 | $FILE_COUNT |"
  echo "| 复杂度 | $COMPLEXITY |"
  echo ""
  echo "### 推断的功能点"
  echo ""
  echo "$FEATURES" | while read -r feat; do
    if [[ -n "$feat" ]]; then
      echo "- $feat"
    fi
  done
  echo ""
  echo "### 主要公共接口"
  echo ""
  echo "\`\`\`$LANG"
  echo "$PUBLIC_ITEMS" | head -15
  echo "\`\`\`"
}

case "$OUTPUT_FORMAT" in
  bash)
    generate_bash_output
    ;;
  json)
    generate_json_output
    ;;
  markdown)
    generate_markdown_output
    ;;
  *)
    echo "[FAIL] unsupported output format: $OUTPUT_FORMAT" >&2
    exit 2
    ;;
esac
