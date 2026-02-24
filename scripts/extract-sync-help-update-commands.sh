#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNC_HELP_EXAMPLES_SNAPSHOT="$ROOT_DIR/tests/snapshots/sync-help-examples.md"
INCLUDE_OPTIONAL_ORDER="${1:-}"

if [ ! -f "$SYNC_HELP_EXAMPLES_SNAPSHOT" ]; then
  echo "sync-help examples snapshot not found: $SYNC_HELP_EXAMPLES_SNAPSHOT" >&2
  exit 1
fi

awk -v include_optional_order="$INCLUDE_OPTIONAL_ORDER" '
  {
    line=$0
    sub(/^[[:space:]]+/, "", line)
  }
  line ~ /^\.\/scripts\/sync-help-to-readme\.sh --update-/ {
    if (line ~ /--update-sync-help-optional-order-snapshot$/ && include_optional_order != "--include-optional-order") {
      next
    }
    print line
  }
' "$SYNC_HELP_EXAMPLES_SNAPSHOT"
