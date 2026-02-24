#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
CLI="$ROOT_DIR/bin/shape-standup"

START_MARK='<!-- AUTO_SYNC_HELP_OPTIONS:START -->'
END_MARK='<!-- AUTO_SYNC_HELP_OPTIONS:END -->'

if [ ! -f "$README" ]; then
  echo "README not found: $README" >&2
  exit 1
fi

help_options="$($CLI --help | awk '
  /^Options:/ { in_opts=1; next }
  in_opts && NF==0 { exit }
  in_opts { print }
')"

if [ -z "$help_options" ]; then
  echo "failed to extract help options from: $CLI --help" >&2
  exit 1
fi

replacement_block=$(cat <<BLOCK
$START_MARK
\`\`\`text
$help_options
\`\`\`
$END_MARK
BLOCK
)

python3 - "$README" "$START_MARK" "$END_MARK" "$replacement_block" <<'PY'
import sys
from pathlib import Path

readme_path, start, end, block = sys.argv[1:5]
text = Path(readme_path).read_text(encoding='utf-8')

if start in text and end in text:
    s = text.index(start)
    e = text.index(end, s) + len(end)
    new_text = text[:s] + block + text[e:]
else:
    section = (
        "\n## CLI Options (auto-synced)\n"
        "`./bin/shape-standup --help` の Options を機械同期しています。\n\n"
        f"{block}\n"
    )
    anchor = "## CLI help snapshot (strict/quiet consistency)"
    if anchor in text:
        i = text.index(anchor)
        new_text = text[:i] + section + text[i:]
    else:
        new_text = text.rstrip() + "\n" + section

Path(readme_path).write_text(new_text, encoding='utf-8')
PY

echo "synced help options to README: $README"
