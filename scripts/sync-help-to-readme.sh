#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
CLI="$ROOT_DIR/bin/shape-standup"
ONE_LINE_CONTRACT_SNAPSHOT="$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract.md"

START_MARK='<!-- AUTO_SYNC_HELP_OPTIONS:START -->'
END_MARK='<!-- AUTO_SYNC_HELP_OPTIONS:END -->'

usage() {
  cat <<'USAGE'
Usage: ./scripts/sync-help-to-readme.sh [--update-one-line-contract-snapshot|--update-one-line-contract-test-links|--all]

Options:
  --update-one-line-contract-snapshot   Update tests/snapshots/readme-quick-check-one-line-contract.md only.
  --update-one-line-contract-test-links Update README '# 対応テスト' links + tests/snapshots/readme-quick-check-one-line-contract-links.md.
  --all                                 Sync README help options + one-line contract snapshot + test-link line/snapshot.
USAGE
}

update_help_options=false
update_one_line_contract=false
update_one_line_contract_test_links=false

case "${1:-}" in
  "")
    update_help_options=true
    ;;
  --update-one-line-contract-snapshot)
    update_one_line_contract=true
    ;;
  --update-one-line-contract-test-links)
    update_one_line_contract_test_links=true
    ;;
  --all)
    update_help_options=true
    update_one_line_contract=true
    update_one_line_contract_test_links=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if [ ! -f "$README" ]; then
  echo "README not found: $README" >&2
  exit 1
fi

if [ "$update_help_options" = true ]; then
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
fi

if [ "$update_one_line_contract" = true ]; then
  "$ROOT_DIR/scripts/update-one-line-contract-snapshot.sh"
fi

if [ "$update_one_line_contract_test_links" = true ]; then
  "$ROOT_DIR/scripts/update-one-line-contract-test-links.sh"
fi
