#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
SELFCHECK="$ROOT_DIR/scripts/selfcheck.sh"
LINKS_SNAPSHOT="$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract-links.md"

labels=(
  "accepts 0foo (README one-line acceptance)"
  "rejects Foo (README one-line acceptance)"
  "rejects fooA (uppercase suffix, README one-line acceptance)"
  "rejects foo/bar (slash delimiter, README one-line acceptance)"
)

make_link() {
  local label="$1"
  local line_no
  line_no=$(grep -nF "${label}" "$SELFCHECK" | head -n 1 | cut -d: -f1)
  if [ -z "$line_no" ]; then
    echo "failed to find selfcheck label: $label" >&2
    exit 1
  fi
  printf '[`%s`](./scripts/selfcheck.sh#L%s)' "$label" "$line_no"
}

links=()
for label in "${labels[@]}"; do
  links+=("$(make_link "$label")")
done

readme_line="# 対応テスト: ${links[0]}, ${links[1]}, ${links[2]}, ${links[3]}"

python3 - "$README" "$readme_line" <<'PY'
import sys
from pathlib import Path

readme_path, new_line = sys.argv[1:3]
text = Path(readme_path).read_text(encoding='utf-8')
lines = text.splitlines()

for i, line in enumerate(lines):
    if line.startswith("# 対応テスト:"):
        lines[i] = new_line
        Path(readme_path).write_text("\n".join(lines) + "\n", encoding='utf-8')
        break
else:
    raise SystemExit("# 対応テスト: line not found in README")
PY

printf '%s\n' "${links[@]}" | sed -E 's/#L[0-9]+/#L<line>/g' > "$LINKS_SNAPSHOT"

echo "updated README #対応テスト links and snapshot: $LINKS_SNAPSHOT"