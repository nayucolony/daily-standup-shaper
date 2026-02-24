#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
SNAPSHOT="$ROOT_DIR/tests/snapshots/readme-quick-check-sync-help-optional-order.md"

if [ ! -f "$README" ]; then
  echo "README not found: $README" >&2
  exit 1
fi

optional_lines=$(awk '
  /^\.\/scripts\/sync-help-to-readme\.sh --update-(one-line-contract-test-links|recommended-sequence-snapshot|sync-line-snapshot|help-examples-snapshot|summary-line-snapshot)$/ {print}
' "$README")

if [ -z "$optional_lines" ]; then
  echo "sync-help optional update commands not found in README" >&2
  exit 1
fi

printf "%s\n" "$optional_lines" > "$SNAPSHOT"
echo "updated sync-help optional-order snapshot: $SNAPSHOT"
