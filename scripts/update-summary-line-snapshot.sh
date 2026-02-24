#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
SNAPSHOT="$ROOT_DIR/tests/snapshots/readme-sync-help-summary-line.md"

line=$(grep -E -- '^\./scripts/selfcheck\.sh --summary$' "$README" | head -n 1)
if [ -z "$line" ]; then
  echo "standalone summary command not found in README" >&2
  exit 1
fi
printf '%s\n' "$line" > "$SNAPSHOT"

echo "updated summary line snapshot: $SNAPSHOT"
