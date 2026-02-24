#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
SNAPSHOT="$ROOT_DIR/tests/snapshots/readme-sync-help-failure-template.md"

retry_line=$(grep -F -- '# retry: ./scripts/sync-help-to-readme.sh --all' "$README" | head -n 1 | sed -E 's/^#[[:space:]]*//')
diff_line=$(grep -F -- '# diff: git diff -- README.md tests/snapshots' "$README" | head -n 1 | sed -E 's/^#[[:space:]]*//')

if [ -z "$retry_line" ] || [ -z "$diff_line" ]; then
  echo "sync-help failure template lines not found in README" >&2
  exit 1
fi

printf '%s\n%s\n' "$retry_line" "$diff_line" > "$SNAPSHOT"

echo "updated sync-help failure template snapshot: $SNAPSHOT"
