#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT="$ROOT_DIR/tests/snapshots/sync-help-examples.md"

help_text="$($ROOT_DIR/scripts/sync-help-to-readme.sh --help)"
examples_block=$(printf "%s\n" "$help_text" | awk '
  /^Examples:/ { in_examples=1; next }
  in_examples && NF==0 { exit }
  in_examples { print }
')

if [ -z "$examples_block" ]; then
  echo "failed to extract Examples block from sync-help-to-readme.sh --help" >&2
  exit 1
fi

printf "%s\n" "$examples_block" > "$SNAPSHOT"
echo "updated sync-help examples snapshot: $SNAPSHOT"
