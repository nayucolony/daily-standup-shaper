#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT="$ROOT_DIR/tests/snapshots/readme-quick-check-sync-help-optional-order.md"

optional_lines="$($ROOT_DIR/scripts/extract-sync-help-update-commands.sh)"

if [ -z "$optional_lines" ]; then
  echo "sync-help optional update commands not found in README" >&2
  exit 1
fi

printf "%s\n" "$optional_lines" > "$SNAPSHOT"
echo "updated sync-help optional-order snapshot: $SNAPSHOT"
