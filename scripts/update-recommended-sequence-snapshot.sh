#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
SNAPSHOT="$ROOT_DIR/tests/snapshots/readme-quick-check-recommended-sequence.md"

line=$(grep -F -- './scripts/sync-help-to-readme.sh --all && ./scripts/selfcheck.sh --summary' "$README" | head -n 1)
if [ -z "$line" ]; then
  echo "recommended sequence line not found in README" >&2
  exit 1
fi
printf '%s\n' "$line" > "$SNAPSHOT"

echo "updated recommended sequence snapshot: $SNAPSHOT"
