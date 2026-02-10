#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ProjectName>"
  exit 1
fi

PROJECT="$1"
ROOT="Report/${PROJECT}"
TPL="skills/repo2doc/templates"

mkdir -p "$ROOT"
cp "$TPL/00-reading-guide.md" "$ROOT/00-reading-guide.md"
cp "$TPL/A-01-getting-started.md" "$ROOT/A-01-getting-started.md"
cp "$TPL/B-01-deep-dive.md" "$ROOT/B-01-deep-dive.md"
cp "$TPL/B-02-layered-highlights-and-hardparts.md" "$ROOT/B-02-layered-highlights-and-hardparts.md"
cp "$TPL/appendix-source-index.md" "$ROOT/appendix-source-index.md"

# Placeholder replacement
sed -i '' "s/{{ProjectName}}/${PROJECT}/g" "$ROOT/00-reading-guide.md"

echo "Scaffolded: $ROOT"
