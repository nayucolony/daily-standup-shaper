#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
SNAPSHOT="$ROOT_DIR/tests/snapshots/readme-sync-help-failure-heading.md"

heading_line=$(grep -F -- '# 失敗時はこの2行テンプレで復旧/確認' "$README" | head -n 1 | sed -E 's/^#[[:space:]]*//')
if [ -z "$heading_line" ]; then
  echo "sync-help failure heading line not found in README" >&2
  exit 1
fi

printf '%s\n' "$heading_line" > "$SNAPSHOT"

echo "updated sync-help failure heading snapshot: $SNAPSHOT"
