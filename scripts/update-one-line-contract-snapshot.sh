#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
SNAPSHOT="$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract.md"

awk '/# 受け入れ条件（1行）:/{print; if (getline nextline > 0 && nextline ~ /^# 対応テスト:/) print nextline; exit}' "$README" \
  | sed -E 's/#L[0-9]+/#L<line>/g' > "$SNAPSHOT"

echo "updated one-line contract snapshot: $SNAPSHOT"
