#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT_DIR/bin/shape-standup"

SUMMARY_MODE=false
if [ "${1:-}" = "--summary" ]; then
  SUMMARY_MODE=true
  shift
fi
if [ "$#" -gt 0 ]; then
  echo "Usage: ./scripts/selfcheck.sh [--summary]" >&2
  exit 1
fi

FORCE_FAIL_CASE="${SELF_CHECK_FORCE_FAIL_CASE:-}"
SKIP_SUMMARY_FAILCASE_TEST="${SELF_CHECK_SKIP_SUMMARY_FAILCASE_TEST:-0}"
INVALID_FORCE_FAIL_CASE_NAME="invalid-self-check-force-fail-case"

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CASE=""
TMP_FILES=()

new_tmp_file() {
  local tmp_file
  tmp_file=$(mktemp /tmp/shape_selfcheck_XXXXXX)
  TMP_FILES+=("$tmp_file")
  printf "%s" "$tmp_file"
}

cleanup_tmp_files() {
  local tmp_file
  for tmp_file in "${TMP_FILES[@]:-}"; do
    rm -f "$tmp_file" || true
  done
}

on_exit() {
  local code=$?
  cleanup_tmp_files
  if [ "$SUMMARY_MODE" = true ]; then
    if [ "$code" -eq 0 ]; then
      echo "SELF_CHECK_SUMMARY: passed=${PASSED_CHECKS}/${TOTAL_CHECKS} failed_case=none"
    else
      echo "SELF_CHECK_SUMMARY: passed=${PASSED_CHECKS}/${TOTAL_CHECKS} failed_case=${FAILED_CASE:-unknown}"
    fi
  fi
}
trap on_exit EXIT

pass() {
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  if [ "$SUMMARY_MODE" = false ]; then
    echo "PASS: $1"
  fi
}
fail() {
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  FAILED_CASE="$1"
  if [ "$SUMMARY_MODE" = false ]; then
    echo "FAIL: $1" >&2
    if [ "${2:-}" != "" ]; then
      echo "--- expected ---" >&2
      echo "$2" >&2
      echo "--- actual ---" >&2
      echo "$3" >&2
    fi
  fi
  exit 1
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$name"
  else
    fail "$name" "$expected" "$actual"
  fi
}

STRICT_QUIET_DEBUG=""
run_strict_quiet_case() {
  local mode="$1" input="$2" args="$3" expect_pattern="$4"
  local stderr_file
  stderr_file=$(new_tmp_file)

  set +e
  local stdout
  stdout=$(printf "%s\n" "$input" | "$CLI" $args 2>"$stderr_file")
  local code=$?
  set -e

  local stderr
  stderr=$(cat "$stderr_file")

  if [ "$code" -eq 2 ] && [ -z "$stderr" ] && echo "$stdout" | grep -q "$expect_pattern"; then
    return 0
  fi

  STRICT_QUIET_DEBUG="mode=${mode} code=${code} stderr=${stderr:-<empty>}"
  return 1
}

expect_fail_contains() {
  local name="$1" cmd="$2" expected="$3"
  set +e
  local out
  out=$(eval "$cmd" 2>&1)
  local code=$?
  set -e
  if [ "$code" -ne 0 ] && echo "$out" | grep -q "$expected"; then
    pass "$name"
  else
    fail "$name" "non-zero exit with expected text: $expected" "$out (code=$code)"
  fi
}

summary_contract_actual() {
  local summary_code="$1" summary_lines="$2" first_line="$3"
  printf "summary_code=%s summary_lines=%s first_line=%s" "$summary_code" "$summary_lines" "${first_line:-<empty>}"
}

RUN_SELF_CHECK_OUT=""
RUN_SELF_CHECK_CODE=0
run_selfcheck_capture() {
  local force_fail_case="${1:-}"
  local mode="${2:-normal}"

  local -a cmd=("$0")
  if [ "$mode" = "summary" ]; then
    cmd+=("--summary")
  fi

  set +e
  RUN_SELF_CHECK_OUT=$(SELF_CHECK_FORCE_FAIL_CASE="$force_fail_case" SELF_CHECK_SKIP_SUMMARY_FAILCASE_TEST=1 "${cmd[@]}" 2>&1)
  RUN_SELF_CHECK_CODE=$?
  set -e
}

summary_line_count() {
  local text="$1"
  printf "%s\n" "$text" | grep -E -c '^SELF_CHECK_SUMMARY:' || true
}

summary_detail_line_count() {
  local text="$1"
  printf "%s\n" "$text" | grep -E -c '^(PASS|FAIL): ' || true
}

summary_first_nonempty_line() {
  local text="$1"
  printf "%s\n" "$text" | sed -n '/./{p;q;}'
}

extract_failed_case_from_summary_line() {
  local line="$1"
  printf "%s\n" "$line" | sed -n 's/^SELF_CHECK_SUMMARY: passed=[0-9][0-9]*\/[0-9][0-9]* failed_case=\([a-z0-9._-][a-z0-9._-]*\)$/\1/p'
}

assert_failed_case_extraction() {
  local case_name="$1" expected="$2" line="$3"
  assert_eq "failed_case boundary contrast ${case_name}" "$expected" "$(extract_failed_case_from_summary_line "$line")"
}

assert_readme_snapshot() {
  local name="$1" expected_path="$2" actual="$3"
  local expected
  expected=$(cat "$expected_path")
  assert_eq "$name" "$expected" "$actual"
}

assert_sync_help_all_invariants() {
  local before_help="$1" after_help="$2"
  local before_contract="$3" after_contract="$4"
  local before_test_links="$5" after_test_links="$6"
  local before_test_links_snapshot="$7" after_test_links_snapshot="$8"
  local before_recommended_snapshot="$9" after_recommended_snapshot="${10}"
  local before_sync_line_snapshot="${11}" after_sync_line_snapshot="${12}"
  local before_summary_line_snapshot="${13}" after_summary_line_snapshot="${14}"
  local before_help_examples_snapshot="${15}" after_help_examples_snapshot="${16}"
  local before_optional_order_snapshot="${17}" after_optional_order_snapshot="${18}"

  local mismatch=""
  [ "$before_help" = "$after_help" ] || mismatch="${mismatch} help/options"
  [ "$before_contract" = "$after_contract" ] || mismatch="${mismatch} one-line-contract"
  [ "$before_test_links" = "$after_test_links" ] || mismatch="${mismatch} test-links-line"
  [ "$before_test_links_snapshot" = "$after_test_links_snapshot" ] || mismatch="${mismatch} test-links-snapshot"
  [ "$before_recommended_snapshot" = "$after_recommended_snapshot" ] || mismatch="${mismatch} recommended-sequence-snapshot"
  [ "$before_sync_line_snapshot" = "$after_sync_line_snapshot" ] || mismatch="${mismatch} sync-line-snapshot"
  [ "$before_summary_line_snapshot" = "$after_summary_line_snapshot" ] || mismatch="${mismatch} summary-line-snapshot"
  [ "$before_help_examples_snapshot" = "$after_help_examples_snapshot" ] || mismatch="${mismatch} help-examples-snapshot"
  [ "$before_optional_order_snapshot" = "$after_optional_order_snapshot" ] || mismatch="${mismatch} optional-order-snapshot"

  if [ -z "$mismatch" ]; then
    pass "sync-help-to-readme --all keeps help/options + one-line contract + test-links + recommended-sequence + sync-line + summary-line + help-examples + optional-order snapshots in sync"
  else
    mismatch=$(printf "%s" "$mismatch" | sed -E 's/^ //')
    fail "sync-help-to-readme --all keeps help/options + one-line contract + test-links + recommended-sequence + sync-line + summary-line + help-examples + optional-order snapshots in sync" "no diff after --all for: help/options, one-line-contract, test-links-line, test-links-snapshot, recommended-sequence-snapshot, sync-line-snapshot, summary-line-snapshot, help-examples-snapshot, optional-order-snapshot" "changed=${mismatch}"
  fi
}

summary_failed_case_name() {
  local text="$1"
  local summary_line
  summary_line=$(printf "%s\n" "$text" | grep '^SELF_CHECK_SUMMARY:' | head -n 1)
  extract_failed_case_from_summary_line "$summary_line"
}

summary_passed_count_from_line() {
  local text="$1"
  printf "%s\n" "$text" | sed -n 's/^SELF_CHECK_SUMMARY: passed=\([0-9][0-9]*\)\/[0-9][0-9]* failed_case=.*/\1/p' | head -n 1
}

summary_total_count_from_line() {
  local text="$1"
  printf "%s\n" "$text" | sed -n 's/^SELF_CHECK_SUMMARY: passed=[0-9][0-9]*\/\([0-9][0-9]*\) failed_case=.*/\1/p' | head -n 1
}

is_numeric() {
  local value="$1"
  echo "$value" | grep -Eq '^[0-9]+$'
}

is_valid_failed_case_name() {
  local value="$1"
  echo "$value" | grep -Eq '^[a-z0-9._-]+$'
}

if [ -n "$FORCE_FAIL_CASE" ] && ! is_valid_failed_case_name "$FORCE_FAIL_CASE"; then
  fail "$INVALID_FORCE_FAIL_CASE_NAME"
fi

multiline_input=$(cat <<'IN'
昨日:
- APIモック作成
- 認可テスト追加
今日:
- ログインUI接続
詰まり:
- stagingの環境変数不足
IN
)

expected_multiline=$(cat <<'OUT'
## Yesterday
- APIモック作成 / 認可テスト追加

## Today
- ログインUI接続

## Blockers
- stagingの環境変数不足
OUT
)

actual_multiline=$(printf "%s\n" "$multiline_input" | "$CLI")
assert_eq "Pattern D multiline bullets are merged" "$expected_multiline" "$actual_multiline"

actual_sample_file=$("$CLI" "$ROOT_DIR/examples/sample.txt")
if echo "$actual_sample_file" | grep -q "APIモック作成" && echo "$actual_sample_file" | grep -q "ログインUIの接続" && echo "$actual_sample_file" | grep -q "stagingの環境変数不足"; then
  pass "sample.txt regression parses 昨日やったこと/今日やること labels"
else
  fail "sample.txt regression parses 昨日やったこと/今日やること labels" "contains parsed values from examples/sample.txt" "$actual_sample_file"
fi

en_input=$(cat <<'IN'
Yesterday: fixed flaky test
Today: implement onboarding banner
Blockers: waiting for copy review
IN
)
actual_en=$(printf "%s\n" "$en_input" | "$CLI")
if echo "$actual_en" | grep -q "fixed flaky test" && echo "$actual_en" | grep -q "implement onboarding banner"; then
  pass "English labels are extracted"
else
  fail "English labels are extracted" "contains extracted values" "$actual_en"
fi

multi_people_input=$(cat <<'IN'
昨日: Aさん昨日
今日: Aさん今日
詰まり: Aさん詰まり

Yesterday: B done
Today: B plan
Blockers: B blocker
IN
)
actual_multi=$(printf "%s\n" "$multi_people_input" | "$CLI" --all)
if echo "$actual_multi" | grep -q "### Entry 2" && echo "$actual_multi" | grep -q "B blocker"; then
  pass "--all splits multi-person paragraphs"
else
  fail "--all splits multi-person paragraphs" "contains Entry 2 and B blocker" "$actual_multi"
fi

actual_multi_no_header=$(printf "%s\n" "$multi_people_input" | "$CLI" --all --no-entry-header)
if ! echo "$actual_multi_no_header" | grep -q "### Entry" && echo "$actual_multi_no_header" | grep -q "## Yesterday"; then
  pass "--no-entry-header omits entry headings in --all markdown"
else
  fail "--no-entry-header omits entry headings in --all markdown" "no Entry headings and contains markdown blocks" "$actual_multi_no_header"
fi

multi_people_named_input=$(cat <<'IN'
Name: Alice
Yesterday: A done
Today: A plan
Blockers: A blocker

名前: ボブ
昨日: B done
今日: B plan
詰まり: B blocker
IN
)
actual_multi_named=$(printf "%s\n" "$multi_people_named_input" | "$CLI" --all)
if echo "$actual_multi_named" | grep -q "### Entry 1 (Alice)" && echo "$actual_multi_named" | grep -q "### Entry 2 (ボブ)"; then
  pass "--all reflects Name/名前 in entry header"
else
  fail "--all reflects Name/名前 in entry header" "contains Entry headers with names" "$actual_multi_named"
fi

header_name_keys_input=$(cat <<'IN'
Owner: Carol
Yesterday: C done
Today: C plan
Blockers: C blocker

担当者: ダン
昨日: D done
今日: D plan
詰まり: D blocker
IN
)
actual_header_name_keys=$(printf "%s\n" "$header_name_keys_input" | "$CLI" --all --header-name-keys 'Owner|担当者')
if echo "$actual_header_name_keys" | grep -q "### Entry 1 (Carol)" && echo "$actual_header_name_keys" | grep -q "### Entry 2 (ダン)"; then
  pass "--header-name-keys supports Owner/担当者 entry names"
else
  fail "--header-name-keys supports Owner/担当者 entry names" "contains Entry headers with Owner/担当者 names" "$actual_header_name_keys"
fi

actual_header_name_keys_spaced=$(printf "%s\n" "$header_name_keys_input" | "$CLI" --all --header-name-keys ' Owner | 担当者 ')
if echo "$actual_header_name_keys_spaced" | grep -q "### Entry 1 (Carol)" && echo "$actual_header_name_keys_spaced" | grep -q "### Entry 2 (ダン)"; then
  pass "--header-name-keys trims delimiter-side spaces"
else
  fail "--header-name-keys trims delimiter-side spaces" "contains Entry headers with Owner/担当者 names" "$actual_header_name_keys_spaced"
fi

header_name_keys_fallback_input=$(cat <<'IN'
Owner: Eve
Yesterday: E done
Today: E plan
Blockers: E blocker

Yesterday: F done
Today: F plan
Blockers: F blocker
IN
)
actual_header_name_keys_fallback=$(printf "%s\n" "$header_name_keys_fallback_input" | "$CLI" --all --header-name-keys 'Owner|担当者')
if echo "$actual_header_name_keys_fallback" | grep -q "### Entry 1 (Eve)" && echo "$actual_header_name_keys_fallback" | grep -q "### Entry 2" && ! echo "$actual_header_name_keys_fallback" | grep -q "### Entry 2 ("; then
  pass "--header-name-keys falls back to ### Entry N when name key is missing"
else
  fail "--header-name-keys falls back to ### Entry N when name key is missing" "contains Entry 1 with Eve and Entry 2 without name suffix" "$actual_header_name_keys_fallback"
fi

actual_json_single=$(printf "%s\n" "$en_input" | "$CLI" --format json)
if echo "$actual_json_single" | grep -q '"yesterday":"fixed flaky test"' && echo "$actual_json_single" | grep -q '"blockers":"waiting for copy review"'; then
  pass "--format json outputs single object"
else
  fail "--format json outputs single object" "contains JSON keys and values" "$actual_json_single"
fi

actual_json_custom_keys=$(printf "%s\n" "$en_input" | "$CLI" --format json --json-keys done,plan,impediments)
if echo "$actual_json_custom_keys" | grep -q '"done":"fixed flaky test"' && echo "$actual_json_custom_keys" | grep -q '"impediments":"waiting for copy review"'; then
  pass "--json-keys customizes output key names"
else
  fail "--json-keys customizes output key names" "contains done/plan/impediments keys" "$actual_json_custom_keys"
fi

actual_json_all=$(printf "%s\n" "$multi_people_input" | "$CLI" --all --format=json)
if printf "%s" "$actual_json_all" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==2 and d[0]["yesterday"]=="Aさん昨日" and d[1]["yesterday"]=="B done"'; then
  pass "--all --format json outputs entry array"
else
  fail "--all --format json outputs entry array" "JSON array with both entries" "$actual_json_all"
fi

actual_json_all_meta=$(printf "%s\n" "$multi_people_named_input" | "$CLI" --all --format=json --json-include-entry-meta)
if printf "%s" "$actual_json_all_meta" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[0]["entryIndex"]==1 and d[0]["entryName"]=="Alice" and d[1]["entryIndex"]==2 and d[1]["entryName"]=="ボブ"'; then
  pass "--json-include-entry-meta adds entryIndex/entryName in all-json mode"
else
  fail "--json-include-entry-meta adds entryIndex/entryName in all-json mode" "entry meta fields present in array items" "$actual_json_all_meta"
fi

actual_json_all_meta_custom=$(printf "%s\n" "$multi_people_named_input" | "$CLI" --all --format=json --json-include-entry-meta --json-entry-meta-keys idx,name)
if printf "%s" "$actual_json_all_meta_custom" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[0]["idx"]==1 and d[0]["name"]=="Alice" and d[1]["idx"]==2 and d[1]["name"]=="ボブ"'; then
  pass "--json-entry-meta-keys customizes entry meta key names"
else
  fail "--json-entry-meta-keys customizes entry meta key names" "custom idx/name keys present" "$actual_json_all_meta_custom"
fi

actual_json_all_meta_custom_no_default=$(printf "%s\n" "$multi_people_named_input" | "$CLI" --all --format=json --json-include-entry-meta --json-entry-meta-keys idx,name)
if printf "%s" "$actual_json_all_meta_custom_no_default" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "entryIndex" not in d[0] and "entryName" not in d[0] and "entryIndex" not in d[1] and "entryName" not in d[1]'; then
  pass "--json-entry-meta-keys suppresses default entryIndex/entryName keys"
else
  fail "--json-entry-meta-keys suppresses default entryIndex/entryName keys" "entryIndex/entryName keys are absent when idx,name is configured" "$actual_json_all_meta_custom_no_default"
fi

actual_json_all_meta_keys_without_include=$(printf "%s\n" "$multi_people_named_input" | "$CLI" --all --format=json --json-entry-meta-keys idx,name)
if printf "%s" "$actual_json_all_meta_keys_without_include" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert all("idx" not in item and "name" not in item and "entryIndex" not in item and "entryName" not in item for item in d)'; then
  pass "--json-entry-meta-keys alone does not emit entry meta keys without --json-include-entry-meta"
else
  fail "--json-entry-meta-keys alone does not emit entry meta keys without --json-include-entry-meta" "idx/name and entryIndex/entryName are absent without --json-include-entry-meta" "$actual_json_all_meta_keys_without_include"
fi

json_meta_fallback_input=$(cat <<'IN'
Owner: Eve
Yesterday: E done
Today: E plan
Blockers: E blocker

Yesterday: F done
Today: F plan
Blockers: F blocker
IN
)
actual_json_meta_fallback=$(printf "%s\n" "$json_meta_fallback_input" | "$CLI" --all --format=json --json-include-entry-meta --json-entry-meta-keys idx,name --header-name-keys 'Owner|担当者')
if printf "%s" "$actual_json_meta_fallback" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[0]["idx"]==1 and d[0]["name"]=="Eve" and d[1]["idx"]==2 and d[1]["name"]==""'; then
  pass "--json-entry-meta-keys keeps name key as empty string when entry name is missing"
else
  fail "--json-entry-meta-keys keeps name key as empty string when entry name is missing" "entry1 has Eve and entry2 has empty name string" "$actual_json_meta_fallback"
fi

json_meta_owner_jp_fallback_input=$(cat <<'IN'
Owner: Carol
Yesterday: C done
Today: C plan
Blockers: C blocker

担当者: 
昨日: D done
今日: D plan
詰まり: D blocker
IN
)
actual_json_meta_owner_jp_fallback=$(printf "%s\n" "$json_meta_owner_jp_fallback_input" | "$CLI" --all --format=json --json-include-entry-meta --json-entry-meta-keys idx,name --header-name-keys 'Owner|担当者')
if printf "%s" "$actual_json_meta_owner_jp_fallback" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[0]["idx"]==1 and d[0]["name"]=="Carol" and d[1]["idx"]==2 and d[1]["name"]=="" and "entryName" not in d[0] and "entryName" not in d[1]'; then
  pass "--json-entry-meta-keys idx,name with --header-name-keys keeps explicit name key as empty string"
else
  fail "--json-entry-meta-keys idx,name with --header-name-keys keeps explicit name key as empty string" "entry1 has Carol, entry2 has empty name string, and no default entryName key" "$actual_json_meta_owner_jp_fallback"
fi

actual_pattern_e_from_file=$("$CLI" --all --format=json --json-include-entry-meta --json-entry-meta-keys idx,name --header-name-keys 'Owner|担当者' "$ROOT_DIR/examples/patterns.txt")
if printf "%s" "$actual_pattern_e_from_file" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[4]["idx"]==5 and d[4]["name"]=="Carol" and d[5]["idx"]==6 and d[5]["name"]==""'; then
  pass "Pattern E in examples/patterns.txt keeps idx/name expectation via README command"
else
  fail "Pattern E in examples/patterns.txt keeps idx/name expectation via README command" "entry5 has Carol and entry6 has empty name" "$actual_pattern_e_from_file"
fi

actual_pattern_e_without_header_keys=$("$CLI" --all --format=json --json-include-entry-meta --json-entry-meta-keys idx,name "$ROOT_DIR/examples/patterns.txt")
if printf "%s" "$actual_pattern_e_without_header_keys" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[4]["idx"]==5 and d[4]["name"]=="" and d[5]["idx"]==6 and d[5]["name"]==""'; then
  pass "Pattern E without --header-name-keys keeps name fallback as empty string"
else
  fail "Pattern E without --header-name-keys keeps name fallback as empty string" "entry5/entry6 keep empty name when Owner/担当者 keys are not configured" "$actual_pattern_e_without_header_keys"
fi

expect_fail_contains \
  "--json-entry-meta-keys rejects 1-key input" \
  "printf '%s\\n' \"$multi_people_named_input\" | \"$CLI\" --all --format=json --json-include-entry-meta --json-entry-meta-keys idx" \
  "invalid --json-entry-meta-keys"

expect_fail_contains \
  "--json-entry-meta-keys rejects 3-key input" \
  "printf '%s\\n' \"$multi_people_named_input\" | \"$CLI\" --all --format=json --json-include-entry-meta --json-entry-meta-keys idx,name,person" \
  "invalid --json-entry-meta-keys"

expect_fail_contains \
  "--json-entry-meta-keys rejects empty input" \
  "printf '%s\\n' \"$multi_people_named_input\" | \"$CLI\" --all --format=json --json-include-entry-meta --json-entry-meta-keys ''" \
  "requires comma-separated keys"

expect_fail_contains \
  "--json-keys and --json-entry-meta-keys reject duplicate key names" \
  "printf '%s\\n' \"$multi_people_named_input\" | \"$CLI\" --all --format=json --json-include-entry-meta --json-keys yesterday,today,name --json-entry-meta-keys idx,name" \
  "json key conflict: duplicate key name(s): name"

imp_input=$(cat <<'IN'
Done: close release checklist
Plan: ship v0.1.0
Impediments: waiting for security approval
IN
)
actual_imp=$(printf "%s\n" "$imp_input" | "$CLI")
if echo "$actual_imp" | grep -q "waiting for security approval"; then
  pass "Impediments synonym is mapped to blockers"
else
  fail "Impediments synonym is mapped to blockers" "contains blockers text" "$actual_imp"
fi

custom_labels_file=$(mktemp)
cat > "$custom_labels_file" <<'JSON'
{
  "yesterday": ["Y"],
  "today": ["T"],
  "blockers": ["B"]
}
JSON
custom_label_input=$(cat <<'IN'
Y: custom done
T: custom plan
B: custom blocker
IN
)
actual_custom_labels=$(printf "%s\n" "$custom_label_input" | "$CLI" --labels "$custom_labels_file")
if echo "$actual_custom_labels" | grep -q "custom done" && echo "$actual_custom_labels" | grep -q "custom blocker"; then
  pass "--labels loads custom synonym file"
else
  rm -f "$custom_labels_file"
  fail "--labels loads custom synonym file" "contains values parsed from custom labels" "$actual_custom_labels"
fi

bad_labels_missing=$(mktemp)
cat > "$bad_labels_missing" <<'JSON'
{
  "yesterday": ["Yesterday"],
  "today": ["Today"]
}
JSON
set +e
bad_missing_out=$(printf "%s\n" "$en_input" | "$CLI" --labels "$bad_labels_missing" 2>&1)
bad_missing_code=$?
set -e
rm -f "$bad_labels_missing"
if [ "$bad_missing_code" -ne 0 ] && echo "$bad_missing_out" | grep -q "missing required keys" && echo "$bad_missing_out" | grep -q "$bad_labels_missing"; then
  pass "--labels rejects missing required keys with file path"
else
  rm -f "$custom_labels_file"
  fail "--labels rejects missing required keys with file path" "non-zero exit with missing keys message including file path" "$bad_missing_out (code=$bad_missing_code)"
fi

bad_labels_type=$(mktemp)
cat > "$bad_labels_type" <<'JSON'
{
  "yesterday": ["Yesterday"],
  "today": "Today",
  "blockers": ["Blockers"]
}
JSON
set +e
bad_type_out=$(printf "%s\n" "$en_input" | "$CLI" --labels "$bad_labels_type" 2>&1)
bad_type_code=$?
set -e
rm -f "$bad_labels_type"
rm -f "$custom_labels_file"
if [ "$bad_type_code" -ne 0 ] && echo "$bad_type_out" | grep -q "must be an array of strings" && echo "$bad_type_out" | grep -q "$bad_labels_type"; then
  pass "--labels rejects non-array/non-string key types with file path"
else
  fail "--labels rejects non-array/non-string key types with file path" "non-zero exit with type validation message including file path" "$bad_type_out (code=$bad_type_code)"
fi

labels_example_input=$(cat <<'IN'
Y: custom done from examples
T: custom plan from examples
B: custom blocker from examples
IN
)
actual_labels_example=$(printf "%s\n" "$labels_example_input" | "$CLI" --labels "$ROOT_DIR/examples/labels.local.json")
if echo "$actual_labels_example" | grep -q "custom done from examples" && echo "$actual_labels_example" | grep -q "custom blocker from examples"; then
  pass "examples/labels.local.json regression works with --labels"
else
  fail "examples/labels.local.json regression works with --labels" "contains values parsed via examples/labels.local.json" "$actual_labels_example"
fi

strict_missing_input=$(cat <<'IN'
Yesterday: fixed flaky test
Today: implement onboarding banner
IN
)
set +e
strict_out=$(printf "%s\n" "$strict_missing_input" | "$CLI" --strict 2>&1)
strict_code=$?
set -e
if [ "$strict_code" -ne 0 ] \
  && echo "$strict_out" | grep -q "^strict mode: missing required fields (" \
  && echo "$strict_out" | grep -q "blockers"; then
  pass "--strict exits non-zero with stable stderr prefix and missing field details"
else
  fail "--strict exits non-zero with stable stderr prefix and missing field details" "non-zero exit with strict mode prefix and blockers" "$strict_out (code=$strict_code)"
fi

set +e
quiet_err=$(printf "%s\n" "$strict_missing_input" | "$CLI" --strict --quiet >/dev/null 2>&1)
quiet_code=$?
set -e
if [ "$quiet_code" -eq 2 ]; then
  pass "--quiet keeps strict exit code 2"
else
  fail "--quiet keeps strict exit code 2" "exit code=2" "code=$quiet_code"
fi

set +e
strict_quiet_err_file=$(new_tmp_file)
strict_stdout=$(printf "%s\n" "$strict_missing_input" | "$CLI" --strict --quiet 2>"$strict_quiet_err_file")
strict_stdout_code=$?
strict_stderr=$(cat "$strict_quiet_err_file")
set -e
if [ "$strict_stdout_code" -eq 2 ] && echo "$strict_stdout" | grep -q "## Yesterday" && ! echo "$strict_stdout" | grep -qi "strict mode" && [ -z "$strict_stderr" ]; then
  pass "--quiet suppresses strict warning message and keeps exit code 2"
else
  fail "--quiet suppresses strict warning message and keeps exit code 2" "exit code=2 + markdown output + empty stderr" "stdout=$strict_stdout | stderr=$strict_stderr | code=$strict_stdout_code"
fi

strict_all_input=$(cat <<'IN'
Yesterday: A done
Today: A plan

Yesterday: B done
Today: B plan
Blockers: B blocker
IN
)

if run_strict_quiet_case "single" "$strict_missing_input" "--strict --quiet" "## Yesterday" \
  && run_strict_quiet_case "all" "$strict_all_input" "--all --strict --quiet" "### Entry 1"; then
  pass "--strict --quiet keeps exit code 2 and empty stderr in single/all markdown modes"
else
  fail "--strict --quiet keeps exit code 2 and empty stderr in single/all markdown modes" "single/all: code=2 + empty stderr + markdown output" "$STRICT_QUIET_DEBUG"
fi

set +e
strict_all_out=$(printf "%s\n" "$strict_all_input" | "$CLI" --all --strict 2>&1)
strict_all_code=$?
set -e
if [ "$strict_all_code" -ne 0 ] \
  && echo "$strict_all_out" | grep -q "^strict mode: missing required fields in one or more entries" \
  && echo "$strict_all_out" | grep -q "entry1:blockers"; then
  pass "--all --strict reports missing fields with stable stderr prefix and entry index"
else
  fail "--all --strict reports missing fields with stable stderr prefix and entry index" "strict message starts with all-mode prefix and includes entry1:blockers" "$strict_all_out (code=$strict_all_code)"
fi

set +e
strict_all_quiet_err_file=$(new_tmp_file)
strict_all_quiet_stdout=$(printf "%s\n" "$strict_all_input" | "$CLI" --all --strict --quiet 2>"$strict_all_quiet_err_file")
strict_all_quiet_code=$?
strict_all_quiet_err=$(cat "$strict_all_quiet_err_file")
set -e
if [ "$strict_all_quiet_code" -eq 2 ] \
  && [ -z "$strict_all_quiet_err" ] \
  && echo "$strict_all_quiet_stdout" | grep -q "### Entry 1" \
  && echo "$strict_all_quiet_stdout" | grep -q "## Blockers"; then
  pass "--all --strict --quiet suppresses stderr, keeps markdown output, and exits 2"
else
  fail "--all --strict --quiet suppresses stderr, keeps markdown output, and exits 2" "exit code=2 + empty stderr + markdown output" "stdout=$strict_all_quiet_stdout | stderr=$strict_all_quiet_err | code=$strict_all_quiet_code"
fi

set +e
strict_all_quiet_no_header_err_file=$(new_tmp_file)
strict_all_quiet_no_header_stdout=$(printf "%s\n" "$strict_all_input" | "$CLI" --all --strict --quiet --no-entry-header 2>"$strict_all_quiet_no_header_err_file")
strict_all_quiet_no_header_code=$?
strict_all_quiet_no_header_err=$(cat "$strict_all_quiet_no_header_err_file")
set -e
if [ "$strict_all_quiet_no_header_code" -ne 0 ] \
  && [ -z "$strict_all_quiet_no_header_err" ] \
  && ! echo "$strict_all_quiet_no_header_stdout" | grep -q "### Entry" \
  && echo "$strict_all_quiet_no_header_stdout" | grep -q "## Yesterday"; then
  pass "--all --strict --quiet --no-entry-header suppresses stderr and omits Entry headings"
else
  fail "--all --strict --quiet --no-entry-header suppresses stderr and omits Entry headings" "non-zero exit + empty stderr + no Entry heading + markdown output" "stdout=$strict_all_quiet_no_header_stdout | stderr=$strict_all_quiet_no_header_err | code=$strict_all_quiet_no_header_code"
fi

set +e
strict_all_json_err_file=$(new_tmp_file)
strict_all_json_stdout=$(printf "%s\n" "$strict_all_input" | "$CLI" --all --strict --format json 2>"$strict_all_json_err_file")
strict_all_json_code=$?
strict_all_json_err=$(cat "$strict_all_json_err_file")
set -e
if [ "$strict_all_json_code" -ne 0 ] \
  && echo "$strict_all_json_err" | grep -q "entry1:blockers" \
  && printf "%s" "$strict_all_json_stdout" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==2'; then
  pass "--all --strict --format json keeps JSON output and reports entry-wise missing fields"
else
  fail "--all --strict --format json keeps JSON output and reports entry-wise missing fields" "non-zero exit + stderr includes entry1:blockers + stdout is valid JSON array" "stdout=$strict_all_json_stdout | stderr=$strict_all_json_err | code=$strict_all_json_code"
fi

set +e
strict_all_json_quiet_err_file=$(new_tmp_file)
strict_all_json_quiet_stdout=$(printf "%s\n" "$strict_all_input" | "$CLI" --all --strict --quiet --format json 2>"$strict_all_json_quiet_err_file")
strict_all_json_quiet_code=$?
strict_all_json_quiet_err=$(cat "$strict_all_json_quiet_err_file")
set -e
if [ "$strict_all_json_quiet_code" -eq 2 ] \
  && [ -z "$strict_all_json_quiet_err" ] \
  && printf "%s" "$strict_all_json_quiet_stdout" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==2'; then
  pass "--all --strict --quiet --format json suppresses stderr, keeps JSON output, and exits 2"
else
  fail "--all --strict --quiet --format json suppresses stderr, keeps JSON output, and exits 2" "exit code=2 + empty stderr + stdout is valid JSON array" "stdout=$strict_all_json_quiet_stdout | stderr=$strict_all_json_quiet_err | code=$strict_all_json_quiet_code"
fi

set +e
strict_all_json_quiet_no_header_err_file=$(new_tmp_file)
strict_all_json_quiet_no_header_stdout=$(printf "%s\n" "$strict_all_input" | "$CLI" --all --strict --quiet --no-entry-header --format json 2>"$strict_all_json_quiet_no_header_err_file")
strict_all_json_quiet_no_header_code=$?
strict_all_json_quiet_no_header_err=$(cat "$strict_all_json_quiet_no_header_err_file")
set -e
if [ "$strict_all_json_quiet_no_header_code" -eq 2 ] \
  && [ -z "$strict_all_json_quiet_no_header_err" ] \
  && printf "%s" "$strict_all_json_quiet_no_header_stdout" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==2 and d[0]["yesterday"]=="A done" and d[1]["today"]=="B plan" and all(set(e.keys())=={"yesterday","today","blockers"} for e in d)'; then
  pass "--all --strict --quiet --no-entry-header --format json keeps JSON array, suppresses stderr, and exits 2"
else
  fail "--all --strict --quiet --no-entry-header --format json keeps JSON array, suppresses stderr, and exits 2" "exit code=2 + empty stderr + stdout is valid JSON array unaffected by --no-entry-header" "stdout=$strict_all_json_quiet_no_header_stdout | stderr=$strict_all_json_quiet_no_header_err | code=$strict_all_json_quiet_no_header_code"
fi

set +e
strict_single_json_quiet_err_file=$(new_tmp_file)
strict_single_json_quiet_stdout=$(printf "%s\n" "$strict_missing_input" | "$CLI" --strict --quiet --format json 2>"$strict_single_json_quiet_err_file")
strict_single_json_quiet_code=$?
strict_single_json_quiet_err=$(cat "$strict_single_json_quiet_err_file")
set -e
if [ "$strict_single_json_quiet_code" -eq 2 ] \
  && [ -z "$strict_single_json_quiet_err" ] \
  && printf "%s" "$strict_single_json_quiet_stdout" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,dict) and set(d.keys())=={"yesterday","today","blockers"} and d["yesterday"]=="fixed flaky test" and d["today"]=="implement onboarding banner"'; then
  pass "--strict --quiet --format json suppresses stderr, keeps single JSON object, and exits 2"
else
  fail "--strict --quiet --format json suppresses stderr, keeps single JSON object, and exits 2" "exit code=2 + empty stderr + stdout is valid JSON object" "stdout=$strict_single_json_quiet_stdout | stderr=$strict_single_json_quiet_err | code=$strict_single_json_quiet_code"
fi

set +e
strict_missing_file_err_file=$(new_tmp_file)
strict_missing_file_stdout=$("$CLI" --all --strict --format json "$ROOT_DIR/examples/strict-missing.txt" 2>"$strict_missing_file_err_file")
strict_missing_file_code=$?
strict_missing_file_err=$(cat "$strict_missing_file_err_file")
set -e
if [ "$strict_missing_file_code" -ne 0 ] \
  && echo "$strict_missing_file_err" | grep -q "^strict mode: missing required fields in one or more entries" \
  && echo "$strict_missing_file_err" | grep -q "entry1:blockers;entry3:today,blockers" \
  && printf "%s" "$strict_missing_file_stdout" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==3'; then
  pass "examples/strict-missing.txt regression keeps strict stderr prefix compatibility and expected entry details"
else
  fail "examples/strict-missing.txt regression keeps strict stderr prefix compatibility and expected entry details" "non-zero exit + stderr starts with strict prefix and includes entry1:blockers;entry3:today,blockers + stdout is valid JSON array" "stdout=$strict_missing_file_stdout | stderr=$strict_missing_file_err | code=$strict_missing_file_code"
fi

strict_single_temp=$(mktemp)
printf "%s\n" "$strict_missing_input" > "$strict_single_temp"
set +e
strict_single_stdin_route_err_file=$(new_tmp_file)
strict_single_stdin_out=$(printf "%s\n" "$strict_missing_input" | "$CLI" --strict --quiet 2>"$strict_single_stdin_route_err_file")
strict_single_stdin_code=$?
strict_single_stdin_err=$(cat "$strict_single_stdin_route_err_file")
strict_single_file_route_err_file=$(new_tmp_file)
strict_single_file_out=$("$CLI" --strict --quiet "$strict_single_temp" 2>"$strict_single_file_route_err_file")
strict_single_file_code=$?
strict_single_file_err=$(cat "$strict_single_file_route_err_file")
set -e
rm -f "$strict_single_temp"
if [ "$strict_single_stdin_code" -eq 2 ] \
  && [ "$strict_single_file_code" -eq 2 ] \
  && [ -z "$strict_single_stdin_err" ] \
  && [ -z "$strict_single_file_err" ] \
  && [ "$strict_single_stdin_out" = "$strict_single_file_out" ]; then
  pass "--strict --quiet single markdown keeps same result on stdin/file routes"
else
  fail "--strict --quiet single markdown keeps same result on stdin/file routes" "stdin/file both code=2 + empty stderr + same markdown" "stdin: code=$strict_single_stdin_code stderr=$strict_single_stdin_err stdout=$strict_single_stdin_out | file: code=$strict_single_file_code stderr=$strict_single_file_err stdout=$strict_single_file_out"
fi

set +e
strict_all_stdin_route_err_file=$(new_tmp_file)
strict_all_stdin_out=$(cat "$ROOT_DIR/examples/strict-missing.txt" | "$CLI" --all --strict --quiet 2>"$strict_all_stdin_route_err_file")
strict_all_stdin_code=$?
strict_all_stdin_err=$(cat "$strict_all_stdin_route_err_file")
strict_all_file_route_err_file=$(new_tmp_file)
strict_all_file_out=$("$CLI" --all --strict --quiet "$ROOT_DIR/examples/strict-missing.txt" 2>"$strict_all_file_route_err_file")
strict_all_file_code=$?
strict_all_file_err=$(cat "$strict_all_file_route_err_file")
set -e
if [ "$strict_all_stdin_code" -eq 2 ] \
  && [ "$strict_all_file_code" -eq 2 ] \
  && [ -z "$strict_all_stdin_err" ] \
  && [ -z "$strict_all_file_err" ] \
  && [ "$strict_all_stdin_out" = "$strict_all_file_out" ]; then
  pass "--all --strict --quiet markdown keeps same result on stdin/file routes"
else
  fail "--all --strict --quiet markdown keeps same result on stdin/file routes" "stdin/file both code=2 + empty stderr + same markdown" "stdin: code=$strict_all_stdin_code stderr=$strict_all_stdin_err stdout=$strict_all_stdin_out | file: code=$strict_all_file_code stderr=$strict_all_file_err stdout=$strict_all_file_out"
fi

set +e
strict_all_json_stdin_route_err_file=$(new_tmp_file)
strict_all_json_stdin_out=$(cat "$ROOT_DIR/examples/strict-missing.txt" | "$CLI" --all --strict --quiet --format json 2>"$strict_all_json_stdin_route_err_file")
strict_all_json_stdin_code=$?
strict_all_json_stdin_err=$(cat "$strict_all_json_stdin_route_err_file")
strict_all_json_file_route_err_file=$(new_tmp_file)
strict_all_json_file_out=$("$CLI" --all --strict --quiet --format json "$ROOT_DIR/examples/strict-missing.txt" 2>"$strict_all_json_file_route_err_file")
strict_all_json_file_code=$?
strict_all_json_file_err=$(cat "$strict_all_json_file_route_err_file")
set -e
if [ "$strict_all_json_stdin_code" -eq 2 ] \
  && [ "$strict_all_json_file_code" -eq 2 ] \
  && [ -z "$strict_all_json_stdin_err" ] \
  && [ -z "$strict_all_json_file_err" ] \
  && [ "$strict_all_json_stdin_out" = "$strict_all_json_file_out" ] \
  && printf "%s" "$strict_all_json_stdin_out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==3'; then
  pass "--all --strict --quiet --format json keeps same result on stdin/file routes"
else
  fail "--all --strict --quiet --format json keeps same result on stdin/file routes" "stdin/file both code=2 + empty stderr + same JSON array" "stdin: code=$strict_all_json_stdin_code stderr=$strict_all_json_stdin_err stdout=$strict_all_json_stdin_out | file: code=$strict_all_json_file_code stderr=$strict_all_json_file_err stdout=$strict_all_json_file_out"
fi

help_text=$("$CLI" --help)
help_strict_line=$(printf "%s\n" "$help_text" | grep -E '^  --strict[[:space:]]+' | sed -E 's/^  --strict[[:space:]]+//')
help_quiet_line=$(printf "%s\n" "$help_text" | grep -E '^  --quiet[[:space:]]+' | sed -E 's/^  --quiet[[:space:]]+//')
readme_strict_line=$(grep -F -- '- `--strict`:' "$ROOT_DIR/README.md" | head -n 1 | sed -E 's/^- `--strict`: //')
readme_quiet_line=$(grep -F -- '- `--quiet`:' "$ROOT_DIR/README.md" | head -n 1 | sed -E 's/^- `--quiet`: //')

sync_help_text=$("$ROOT_DIR/scripts/sync-help-to-readme.sh" --help)
sync_help_examples_actual=$(printf "%s\n" "$sync_help_text" | awk '
  /^Examples:/ { in_examples=1; next }
  in_examples && NF==0 { exit }
  in_examples { print }
')
assert_readme_snapshot \
  "sync-help-to-readme --help Examples snapshot matches expected" \
  "$ROOT_DIR/tests/snapshots/sync-help-examples.md" \
  "$sync_help_examples_actual"
if printf "%s\n" "$sync_help_text" | grep -Fx -- '  ./scripts/sync-help-to-readme.sh --update-recommended-sequence-snapshot' >/dev/null \
  && printf "%s\n" "$sync_help_text" | grep -Fx -- '  ./scripts/sync-help-to-readme.sh --update-sync-line-snapshot' >/dev/null \
  && printf "%s\n" "$sync_help_text" | grep -Fx -- '  ./scripts/selfcheck.sh --summary' >/dev/null \
  && printf "%s\n" "$sync_help_text" | grep -Fx -- '  ./scripts/sync-help-to-readme.sh --update-one-line-contract-test-links' >/dev/null \
  && printf "%s\n" "$sync_help_text" | grep -Fx -- '  ./scripts/sync-help-to-readme.sh --update-help-examples-snapshot' >/dev/null \
  && printf "%s\n" "$sync_help_text" | grep -Fx -- '  ./scripts/sync-help-to-readme.sh --update-sync-help-optional-order-snapshot' >/dev/null \
  && printf "%s\n" "$sync_help_text" | grep -Fx -- '  ./scripts/sync-help-to-readme.sh --all' >/dev/null; then
  pass "sync-help-to-readme --help includes recommended/sync-line/summary/test-links/help-examples/optional-order/--all examples"
else
  fail "sync-help-to-readme --help includes recommended/sync-line/summary/test-links/help-examples/optional-order/--all examples" "--help Examples contain recommended-sequence, sync-line, summary, test-links, help-examples, optional-order, and --all commands" "$sync_help_text"
fi

missing_sync_help_examples_line=""
while IFS= read -r help_example_line; do
  [ -z "$help_example_line" ] && continue
  help_example_line_trimmed=$(printf "%s" "$help_example_line" | sed -E 's/^[[:space:]]+//')
  if ! grep -Fx -- "$help_example_line_trimmed" "$ROOT_DIR/README.md" >/dev/null; then
    if [ -n "$missing_sync_help_examples_line" ]; then
      missing_sync_help_examples_line="$missing_sync_help_examples_line, $help_example_line"
    else
      missing_sync_help_examples_line="$help_example_line"
    fi
  fi
done < "$ROOT_DIR/tests/snapshots/sync-help-examples.md"

if [ -z "$missing_sync_help_examples_line" ]; then
  pass "README Quick check includes all sync-help --help Examples commands"
else
  fail "README Quick check includes all sync-help --help Examples commands" "README contains every command listed in tests/snapshots/sync-help-examples.md" "missing: $missing_sync_help_examples_line"
fi

readme_sync_help_example_count=$(grep -Fxc -- './scripts/sync-help-to-readme.sh --update-one-line-contract-test-links' "$ROOT_DIR/README.md" || true)
if [ "$readme_sync_help_example_count" -ge 1 ]; then
  pass "README Quick check includes sync-help test-links example"
else
  fail "README Quick check includes sync-help test-links example" "README contains ./scripts/sync-help-to-readme.sh --update-one-line-contract-test-links" "count=$readme_sync_help_example_count"
fi

readme_sync_help_optional_header_count=$(grep -Fxc -- '# 必要時のみ: 個別同期（推奨順で実行）' "$ROOT_DIR/README.md" || true)
if [ "$readme_sync_help_optional_header_count" -eq 1 ]; then
  pass "README Quick check marks sync-help individual updates as optional"
else
  fail "README Quick check marks sync-help individual updates as optional" "README contains exactly one optional header line for sync-help individual updates" "count=$readme_sync_help_optional_header_count"
fi

readme_sync_help_optional_total_count=$(grep -E -c '^\./scripts/sync-help-to-readme\.sh --update-(one-line-contract-test-links|recommended-sequence-snapshot|sync-line-snapshot|help-examples-snapshot|summary-line-snapshot)$' "$ROOT_DIR/README.md" || true)
if [ "$readme_sync_help_optional_total_count" -eq 5 ]; then
  pass "README Quick check keeps exactly five sync-help individual update commands"
else
  fail "README Quick check keeps exactly five sync-help individual update commands" "README contains exactly 5 sync-help individual update commands" "count=$readme_sync_help_optional_total_count"
fi

readme_sync_help_optional_order_actual=$(awk '
  /^\.\/scripts\/sync-help-to-readme\.sh --update-(one-line-contract-test-links|recommended-sequence-snapshot|sync-line-snapshot|help-examples-snapshot|summary-line-snapshot)$/ {print}
' "$ROOT_DIR/README.md")
assert_readme_snapshot \
  "README Quick check keeps sync-help optional command order snapshot" \
  "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-help-optional-order.md" \
  "$readme_sync_help_optional_order_actual"

sync_help_optional_order_before=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-help-optional-order.md")
"$ROOT_DIR/scripts/update-sync-help-optional-order-snapshot.sh" >/dev/null
sync_help_optional_order_after=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-help-optional-order.md")
assert_eq "update-sync-help-optional-order-snapshot keeps optional command-order snapshot in sync" "$sync_help_optional_order_before" "$sync_help_optional_order_after"

assert_eq "README strict snapshot matches --help" "$help_strict_line" "$readme_strict_line"
assert_eq "README quiet snapshot matches --help" "$help_quiet_line" "$readme_quiet_line"

readme_quiet_table_actual=$(awk '
  /^\| mode \| 入力経路（file\/stdin） \| stdout \| exit code \| stderr \| 再現コマンド（1行） \| 要約（運用判断） \|$/ {capture=1}
  capture {
    if ($0 ~ /^\|/) {
      print
    } else {
      exit
    }
  }
' "$ROOT_DIR/README.md")
assert_readme_snapshot \
  "README strict/quiet matrix snapshot matches expected markdown table" \
  "$ROOT_DIR/tests/snapshots/readme-strict-quiet-matrix.md" \
  "$readme_quiet_table_actual"

summary_line_leading_dot='SELF_CHECK_SUMMARY: passed=3/7 failed_case=.summary-failcase-contract-sentinel'
summary_line_leading_dash='SELF_CHECK_SUMMARY: passed=3/7 failed_case=-summary-failcase-contract-sentinel'
summary_line_leading_underscore='SELF_CHECK_SUMMARY: passed=3/7 failed_case=_summary-failcase-contract-sentinel'
summary_line_trailing_dot='SELF_CHECK_SUMMARY: passed=3/7 failed_case=summary-failcase-contract-sentinel.'
summary_line_trailing_dash='SELF_CHECK_SUMMARY: passed=3/7 failed_case=summary-failcase-contract-sentinel-'
summary_line_trailing_underscore='SELF_CHECK_SUMMARY: passed=3/7 failed_case=summary-failcase-contract-sentinel_'
summary_line_leading_paren='SELF_CHECK_SUMMARY: passed=3/7 failed_case=)summary-failcase-contract-sentinel'
summary_line_leading_upper='SELF_CHECK_SUMMARY: passed=3/7 failed_case=Foo'
summary_line_leading_digit='SELF_CHECK_SUMMARY: passed=3/7 failed_case=0summary-failcase-contract-sentinel'
summary_line_boundary_accept_0foo='SELF_CHECK_SUMMARY: passed=3/7 failed_case=0foo'
summary_line_boundary_reject_Foo='SELF_CHECK_SUMMARY: passed=3/7 failed_case=Foo'
summary_line_trailing_upper='SELF_CHECK_SUMMARY: passed=3/7 failed_case=fooA'
summary_line_with_slash='SELF_CHECK_SUMMARY: passed=3/7 failed_case=foo/bar'
summary_line_trailing_digit='SELF_CHECK_SUMMARY: passed=3/7 failed_case=summary-failcase-contract-sentinel0'
summary_line_both_edge_digits='SELF_CHECK_SUMMARY: passed=3/7 failed_case=0summary-failcase-contract-sentinel0'
summary_line_single_alpha='SELF_CHECK_SUMMARY: passed=3/7 failed_case=a'
summary_line_single_digit='SELF_CHECK_SUMMARY: passed=3/7 failed_case=0'
summary_line_trailing_paren='SELF_CHECK_SUMMARY: passed=3/7 failed_case=summary-failcase-contract-sentinel)'

assert_eq "extract_failed_case_from_summary_line keeps leading dot" ".summary-failcase-contract-sentinel" "$(extract_failed_case_from_summary_line "$summary_line_leading_dot")"
assert_eq "extract_failed_case_from_summary_line keeps leading dash" "-summary-failcase-contract-sentinel" "$(extract_failed_case_from_summary_line "$summary_line_leading_dash")"
assert_eq "extract_failed_case_from_summary_line keeps leading underscore" "_summary-failcase-contract-sentinel" "$(extract_failed_case_from_summary_line "$summary_line_leading_underscore")"
assert_eq "extract_failed_case_from_summary_line keeps trailing dot" "summary-failcase-contract-sentinel." "$(extract_failed_case_from_summary_line "$summary_line_trailing_dot")"
assert_eq "extract_failed_case_from_summary_line keeps trailing dash" "summary-failcase-contract-sentinel-" "$(extract_failed_case_from_summary_line "$summary_line_trailing_dash")"
assert_eq "extract_failed_case_from_summary_line keeps trailing underscore" "summary-failcase-contract-sentinel_" "$(extract_failed_case_from_summary_line "$summary_line_trailing_underscore")"
assert_eq "extract_failed_case_from_summary_line rejects invalid leading punctuation" "" "$(extract_failed_case_from_summary_line "$summary_line_leading_paren")"
assert_eq "extract_failed_case_from_summary_line rejects uppercase leading character" "" "$(extract_failed_case_from_summary_line "$summary_line_leading_upper")"
assert_failed_case_extraction "accepts 0foo (README one-line acceptance)" "0foo" "$summary_line_boundary_accept_0foo"
for boundary_case in   "rejects Foo (README one-line acceptance)|$summary_line_boundary_reject_Foo"   "rejects fooA (uppercase suffix, README one-line acceptance)|$summary_line_trailing_upper"   "rejects foo/bar (slash delimiter, README one-line acceptance)|$summary_line_with_slash"; do
  case_label=${boundary_case%%|*}
  line_value=${boundary_case#*|}
  assert_failed_case_extraction "${case_label}" "" "$line_value"
done

readme_boundary_link_missing=""
for readme_boundary_link_label in \
  '[`accepts 0foo (README one-line acceptance)`]' \
  '[`rejects Foo (README one-line acceptance)`]' \
  '[`rejects fooA (uppercase suffix, README one-line acceptance)`]' \
  '[`rejects foo/bar (slash delimiter, README one-line acceptance)`]'; do
  if ! grep -F -- "$readme_boundary_link_label" "$ROOT_DIR/README.md" >/dev/null; then
    if [ -n "$readme_boundary_link_missing" ]; then
      readme_boundary_link_missing="$readme_boundary_link_missing, $readme_boundary_link_label"
    else
      readme_boundary_link_missing="$readme_boundary_link_label"
    fi
  fi
done
if [ -z "$readme_boundary_link_missing" ]; then
  pass "README one-line acceptance links include all four failed_case boundary tests"
else
  fail "README one-line acceptance links include all four failed_case boundary tests" "README contains 4 link labels for 0foo/Foo/fooA/foo-bar tests" "missing: $readme_boundary_link_missing"
fi

readme_boundary_link_line=$(grep -F -- '# 対応テスト:' "$ROOT_DIR/README.md" | head -n 1)
readme_boundary_links=$(printf "%s\n" "$readme_boundary_link_line" | grep -oE '\[[^]]+\]\([^)]*\)' | sed '/^$/d')
readme_boundary_link_total_count=$(printf "%s\n" "$readme_boundary_links" | sed '/^$/d' | wc -l | tr -d ' ')
readme_boundary_link_refs=$(printf "%s\n" "$readme_boundary_link_line" | grep -oE '\(\./scripts/selfcheck\.sh#L[0-9]+\)')
readme_boundary_link_ref_count=$(printf "%s\n" "$readme_boundary_link_refs" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "$readme_boundary_link_total_count" -eq 4 ] && [ "$readme_boundary_link_ref_count" -eq 4 ] && [ -n "$readme_boundary_link_refs" ] && ! printf "%s\n" "$readme_boundary_link_refs" | grep -qvE '^\(\./scripts/selfcheck\.sh#L[0-9]+\)$'; then
  pass "README one-line acceptance links keep exactly four links (no extra/missing)"
else
  fail "README one-line acceptance links keep exactly four links (no extra/missing)" "exactly 4 markdown links and all refs use ./scripts/selfcheck.sh#L<line> format" "$readme_boundary_link_line"
fi

readme_boundary_links_normalized=$(printf "%s\n" "$readme_boundary_links" | sed -E 's/#L[0-9]+/#L<line>/g')
readme_boundary_links_unique_count=$(printf "%s\n" "$readme_boundary_links_normalized" | sort | uniq | sed '/^$/d' | wc -l | tr -d ' ')
if [ "$readme_boundary_links_unique_count" -eq 4 ]; then
  pass "README one-line acceptance links are unique across all four markdown links"
else
  fail "README one-line acceptance links are unique across all four markdown links" "4 unique markdown links after #L normalization" "$readme_boundary_links_normalized"
fi
assert_readme_snapshot \
  "README one-line acceptance link-set snapshot matches expected unique 4 links" \
  "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract-links.md" \
  "$readme_boundary_links_normalized"

readme_acceptance_line=$(grep -F -- '# 受け入れ条件（1行）:' "$ROOT_DIR/README.md" | head -n 1)
if echo "$readme_acceptance_line" | grep -F -- '[Strict mode (CI向け)](#strict-mode-ci向け)' >/dev/null \
  && echo "$readme_acceptance_line" | grep -F -- '[Quiet mode](#quiet-mode)' >/dev/null; then
  pass "README one-line acceptance line links to Strict/Quiet contract sections"
else
  fail "README one-line acceptance line links to Strict/Quiet contract sections" "contains [Strict mode (CI向け)](#strict-mode-ci向け) and [Quiet mode](#quiet-mode) links" "$readme_acceptance_line"
fi

readme_sync_all_scope_line=$(grep -F -- '# README/スナップショット同期（' "$ROOT_DIR/README.md" | head -n 1)
readme_sync_all_scope_count=$(grep -Fxc -- '# README/スナップショット同期（help/options + one-line contract + links + recommended + sync-line + summary-line + help-examples + optional-order を1コマンドで揃える）' "$ROOT_DIR/README.md" || true)
if [ "$readme_sync_all_scope_count" -eq 1 ]; then
  pass "README Quick check documents --all sync scope in one line"
else
  fail "README Quick check documents --all sync scope in one line" "README contains exactly one scope line for --all: help/options + one-line contract + links + recommended + sync-line + summary-line + help-examples + optional-order" "count=$readme_sync_all_scope_count line='$readme_sync_all_scope_line'"
fi
assert_readme_snapshot \
  "README Quick check --all sync scope line snapshot matches expected" \
  "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-all-scope.md" \
  "$readme_sync_all_scope_line"

readme_sync_all_line='./scripts/sync-help-to-readme.sh --all'
readme_recommended_sequence_line='./scripts/sync-help-to-readme.sh --all && ./scripts/selfcheck.sh --summary'
readme_local_verify_heading='# ローカル検証ワンライナー（同期→summary、直後のCI向け1行サマリと同順）'
readme_local_verify_heading_count=$(grep -Fxc -- "$readme_local_verify_heading" "$ROOT_DIR/README.md" || true)
if [ "$readme_local_verify_heading_count" -eq 1 ]; then
  pass "README Quick check keeps local verification one-liner heading"
else
  fail "README Quick check keeps local verification one-liner heading" "README contains exactly one heading line: $readme_local_verify_heading" "count=$readme_local_verify_heading_count"
fi
readme_local_verify_pair=$(printf '%s\n%s' "$readme_local_verify_heading" "$readme_recommended_sequence_line")
assert_readme_snapshot \
  "README Quick check local verification heading+command snapshot matches expected" \
  "$ROOT_DIR/tests/snapshots/readme-quick-check-local-verify-one-liner.md" \
  "$readme_local_verify_pair"

readme_recommended_sequence_count=$(grep -Fxc -- "$readme_recommended_sequence_line" "$ROOT_DIR/README.md" || true)
if [ "$readme_recommended_sequence_count" -eq 1 ]; then
  pass "README Quick check keeps recommended sync-then-summary one-liner"
else
  fail "README Quick check keeps recommended sync-then-summary one-liner" "README contains exactly one line: $readme_recommended_sequence_line" "count=$readme_recommended_sequence_count"
fi
assert_readme_snapshot \
  "README Quick check recommended sync-then-summary one-liner snapshot matches expected" \
  "$ROOT_DIR/tests/snapshots/readme-quick-check-recommended-sequence.md" \
  "$readme_recommended_sequence_line"
assert_readme_snapshot \
  "README Quick check sync-help single-line snapshot matches expected" \
  "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-line.md" \
  "$readme_sync_all_line"

readme_sync_all_line_no=$(grep -n -F -- "$readme_sync_all_line" "$ROOT_DIR/README.md" | head -n 1 | cut -d: -f1)
readme_recommended_sequence_line_no=$(grep -n -F -- "$readme_recommended_sequence_line" "$ROOT_DIR/README.md" | head -n 1 | cut -d: -f1)
expected_sync_then_recommended_order=$(printf '%s\n%s' "$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-line.md")" "$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-recommended-sequence.md")")
actual_sync_then_recommended_order=$(printf '%s\n%s' "$readme_sync_all_line" "$readme_recommended_sequence_line")
assert_eq "README Quick check keeps sync-line then recommended-sequence order snapshot" "$expected_sync_then_recommended_order" "$actual_sync_then_recommended_order"
readme_summary_line='./scripts/selfcheck.sh --summary'
readme_summary_line_count=$(grep -Fxc -- "$readme_summary_line" "$ROOT_DIR/README.md" || true)
if [ "$readme_summary_line_count" -eq 1 ]; then
  pass "README Quick check keeps one standalone summary command line"
else
  fail "README Quick check keeps one standalone summary command line" "README contains exactly one line: $readme_summary_line" "count=$readme_summary_line_count"
fi
assert_readme_snapshot \
  "README standalone summary command snapshot matches expected" \
  "$ROOT_DIR/tests/snapshots/readme-sync-help-summary-line.md" \
  "$readme_summary_line"

readme_summary_snapshot_before=$(cat "$ROOT_DIR/tests/snapshots/readme-sync-help-summary-line.md")
"$ROOT_DIR/scripts/sync-help-to-readme.sh" --update-summary-line-snapshot >/dev/null
readme_summary_snapshot_after=$(cat "$ROOT_DIR/tests/snapshots/readme-sync-help-summary-line.md")
assert_eq "sync-help --update-summary-line-snapshot keeps standalone summary snapshot in sync" "$readme_summary_snapshot_before" "$readme_summary_snapshot_after"

sync_help_summary_line=$(printf "%s\n" "$sync_help_examples_actual" | grep -E '^  \./scripts/selfcheck\.sh --summary$' | sed -E 's/^[[:space:]]+//')
if [ "$sync_help_summary_line" = "$readme_summary_line" ]; then
  pass "sync-help Examples keeps standalone summary command aligned with README"
else
  fail "sync-help Examples keeps standalone summary command aligned with README" "sync-help Examples contains '$readme_summary_line'" "actual='${sync_help_summary_line:-<missing>}'"
fi
assert_readme_snapshot \
  "sync-help standalone summary command snapshot matches README snapshot" \
  "$ROOT_DIR/tests/snapshots/readme-sync-help-summary-line.md" \
  "$sync_help_summary_line"

readme_line_after_recommended=''
if [ -n "$readme_recommended_sequence_line_no" ]; then
  readme_line_after_recommended=$(sed -n "$((readme_recommended_sequence_line_no + 1))p" "$ROOT_DIR/README.md")
fi
if [ -n "$readme_sync_all_line_no" ] && [ -n "$readme_recommended_sequence_line_no" ] && [ "$readme_sync_all_line_no" -lt "$readme_recommended_sequence_line_no" ]; then
  pass "README Quick check keeps sync-help single-line command before recommended sequence one-liner"
else
  fail "README Quick check keeps sync-help single-line command before recommended sequence one-liner" "README keeps './scripts/sync-help-to-readme.sh --all' above '$readme_recommended_sequence_line'" "sync_all_line=${readme_sync_all_line_no:-missing} recommended_line=${readme_recommended_sequence_line_no:-missing}"
fi

if [ -n "$readme_recommended_sequence_line_no" ] && [ "$readme_line_after_recommended" = "$readme_summary_line" ]; then
  pass "README Quick check keeps local sync-then-summary one-liner immediately before summary command"
else
  fail "README Quick check keeps local sync-then-summary one-liner immediately before summary command" "README keeps '$readme_recommended_sequence_line' immediately followed by '$readme_summary_line'" "recommended_line=${readme_recommended_sequence_line_no:-missing} line_after='$readme_line_after_recommended'"
fi

readme_backlink_count=$(grep -F -- '[受け入れ条件（1行）](#quick-check-one-line-acceptance)' "$ROOT_DIR/README.md" | wc -l | tr -d ' ')
if [ "$readme_backlink_count" -ge 2 ]; then
  pass "Strict/Quiet sections link back to Quick check one-line acceptance"
else
  fail "Strict/Quiet sections link back to Quick check one-line acceptance" "at least two backlinks to [受け入れ条件（1行）](#quick-check-one-line-acceptance)" "count=$readme_backlink_count"
fi

readme_quick_check_anchor_count=$(grep -E -c '^<a id="quick-check-one-line-acceptance"></a>$' "$ROOT_DIR/README.md")
if [ "$readme_quick_check_anchor_count" -eq 1 ]; then
  pass "README quick-check one-line acceptance anchor is defined exactly once"
else
  fail "README quick-check one-line acceptance anchor is defined exactly once" "exactly one '<a id=\"quick-check-one-line-acceptance\"></a>' line exists" "count=$readme_quick_check_anchor_count"
fi

readme_acceptance_line_no=$(grep -n -F -- '# 受け入れ条件（1行）:' "$ROOT_DIR/README.md" | head -n 1 | cut -d: -f1)
readme_test_line_no=$(grep -n -F -- '# 対応テスト:' "$ROOT_DIR/README.md" | head -n 1 | cut -d: -f1)
if [ -n "$readme_acceptance_line_no" ] && [ -n "$readme_test_line_no" ] && [ $((readme_test_line_no - readme_acceptance_line_no)) -eq 1 ]; then
  pass "README one-line acceptance and test-link lines stay adjacent"
else
  fail "README one-line acceptance and test-link lines stay adjacent" "README keeps '# 受け入れ条件（1行）:' immediately followed by '# 対応テスト:'" "acceptance_line=${readme_acceptance_line_no:-missing} test_line=${readme_test_line_no:-missing}"
fi

readme_acceptance_test_block_count=$(awk '
  /# 受け入れ条件（1行）:/ {
    if (getline nextline > 0 && nextline ~ /^# 対応テスト:/) count++
  }
  END { print count+0 }
' "$ROOT_DIR/README.md")
if [ "$readme_acceptance_test_block_count" -eq 1 ]; then
  pass "README one-line acceptance/test two-line block is defined exactly once"
else
  fail "README one-line acceptance/test two-line block is defined exactly once" "exactly one adjacent '# 受け入れ条件（1行）:' + '# 対応テスト:' block" "count=$readme_acceptance_test_block_count"
fi

readme_one_line_contract_actual=$(awk '
  /# 受け入れ条件（1行）:/ {
    print
    if (getline nextline > 0 && nextline ~ /^# 対応テスト:/) {
      print nextline
      exit
    }
  }
' "$ROOT_DIR/README.md" | sed -E 's/#L[0-9]+/#L<line>/g')
assert_readme_snapshot \
  "README Quick check one-line contract two-line snapshot matches expected" \
  "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract.md" \
  "$readme_one_line_contract_actual"

sync_contract_before=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract.md")
"$ROOT_DIR/scripts/sync-help-to-readme.sh" --update-one-line-contract-snapshot >/dev/null
sync_contract_after=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract.md")
assert_eq "sync-help-to-readme --update-one-line-contract-snapshot keeps one-line contract snapshot in sync" "$sync_contract_before" "$sync_contract_after"

readme_help_block_before=$(awk '
  /<!-- AUTO_SYNC_HELP_OPTIONS:START -->/ {capture=1}
  capture {print}
  /<!-- AUTO_SYNC_HELP_OPTIONS:END -->/ {exit}
' "$ROOT_DIR/README.md")
sync_contract_before_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract.md")
readme_test_links_before_all=$(grep -F -- '# 対応テスト:' "$ROOT_DIR/README.md" | head -n 1)
readme_test_links_snapshot_before_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract-links.md")
readme_recommended_snapshot_before_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-recommended-sequence.md")
readme_sync_line_snapshot_before_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-line.md")
readme_summary_line_snapshot_before_all=$(cat "$ROOT_DIR/tests/snapshots/readme-sync-help-summary-line.md")
readme_help_examples_snapshot_before_all=$(cat "$ROOT_DIR/tests/snapshots/sync-help-examples.md")
readme_optional_order_snapshot_before_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-help-optional-order.md")
"$ROOT_DIR/scripts/sync-help-to-readme.sh" --all >/dev/null
readme_help_block_after=$(awk '
  /<!-- AUTO_SYNC_HELP_OPTIONS:START -->/ {capture=1}
  capture {print}
  /<!-- AUTO_SYNC_HELP_OPTIONS:END -->/ {exit}
' "$ROOT_DIR/README.md")
sync_contract_after_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract.md")
readme_test_links_after_all=$(grep -F -- '# 対応テスト:' "$ROOT_DIR/README.md" | head -n 1)
readme_test_links_snapshot_after_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract-links.md")
readme_recommended_snapshot_after_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-recommended-sequence.md")
readme_sync_line_snapshot_after_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-line.md")
readme_summary_line_snapshot_after_all=$(cat "$ROOT_DIR/tests/snapshots/readme-sync-help-summary-line.md")
readme_help_examples_snapshot_after_all=$(cat "$ROOT_DIR/tests/snapshots/sync-help-examples.md")
readme_optional_order_snapshot_after_all=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-help-optional-order.md")
assert_sync_help_all_invariants \
  "$readme_help_block_before" "$readme_help_block_after" \
  "$sync_contract_before_all" "$sync_contract_after_all" \
  "$readme_test_links_before_all" "$readme_test_links_after_all" \
  "$readme_test_links_snapshot_before_all" "$readme_test_links_snapshot_after_all" \
  "$readme_recommended_snapshot_before_all" "$readme_recommended_snapshot_after_all" \
  "$readme_sync_line_snapshot_before_all" "$readme_sync_line_snapshot_after_all" \
  "$readme_summary_line_snapshot_before_all" "$readme_summary_line_snapshot_after_all" \
  "$readme_help_examples_snapshot_before_all" "$readme_help_examples_snapshot_after_all" \
  "$readme_optional_order_snapshot_before_all" "$readme_optional_order_snapshot_after_all"

readme_test_links_before=$(grep -F -- '# 対応テスト:' "$ROOT_DIR/README.md" | head -n 1)
readme_test_links_snapshot_before=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract-links.md")
"$ROOT_DIR/scripts/sync-help-to-readme.sh" --update-one-line-contract-test-links >/dev/null
readme_test_links_after=$(grep -F -- '# 対応テスト:' "$ROOT_DIR/README.md" | head -n 1)
readme_test_links_snapshot_after=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-one-line-contract-links.md")
assert_eq "sync-help-to-readme --update-one-line-contract-test-links keeps README #対応テスト line in sync" "$readme_test_links_before" "$readme_test_links_after"
assert_eq "sync-help-to-readme --update-one-line-contract-test-links keeps one-line contract link snapshot in sync" "$readme_test_links_snapshot_before" "$readme_test_links_snapshot_after"

readme_recommended_snapshot_before=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-recommended-sequence.md")
"$ROOT_DIR/scripts/sync-help-to-readme.sh" --update-recommended-sequence-snapshot >/dev/null
readme_recommended_snapshot_after=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-recommended-sequence.md")
assert_eq "sync-help-to-readme --update-recommended-sequence-snapshot keeps recommended sequence snapshot in sync" "$readme_recommended_snapshot_before" "$readme_recommended_snapshot_after"

readme_sync_line_snapshot_before=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-line.md")
"$ROOT_DIR/scripts/sync-help-to-readme.sh" --update-sync-line-snapshot >/dev/null
readme_sync_line_snapshot_after=$(cat "$ROOT_DIR/tests/snapshots/readme-quick-check-sync-line.md")
assert_eq "sync-help-to-readme --update-sync-line-snapshot keeps sync-help single-line snapshot in sync" "$readme_sync_line_snapshot_before" "$readme_sync_line_snapshot_after"

if [ -n "$readme_acceptance_line_no" ] && [ -n "$readme_test_line_no" ] \
  && [ $((readme_test_line_no - readme_acceptance_line_no)) -eq 1 ] \
  && echo "$readme_acceptance_line" | grep -F -- '[Strict mode (CI向け)](#strict-mode-ci向け)' >/dev/null \
  && echo "$readme_acceptance_line" | grep -F -- '[Quiet mode](#quiet-mode)' >/dev/null; then
  pass "README one-line acceptance adjacency stays intact after Strict/Quiet mutual links"
else
  fail "README one-line acceptance adjacency stays intact after Strict/Quiet mutual links" "acceptance line keeps Strict/Quiet links and remains immediately followed by '# 対応テスト:'" "acceptance_line=${readme_acceptance_line:-missing} acceptance_line_no=${readme_acceptance_line_no:-missing} test_line_no=${readme_test_line_no:-missing}"
fi

readme_boundary_vocab_line_normalized=$(printf "%s\n" "$readme_boundary_link_line" | sed -E 's/#L[0-9]+/#L<line>/g')
readme_boundary_vocab_expected='# 対応テスト: [`accepts 0foo (README one-line acceptance)`](./scripts/selfcheck.sh#L<line>), [`rejects Foo (README one-line acceptance)`](./scripts/selfcheck.sh#L<line>), [`rejects fooA (uppercase suffix, README one-line acceptance)`](./scripts/selfcheck.sh#L<line>), [`rejects foo/bar (slash delimiter, README one-line acceptance)`](./scripts/selfcheck.sh#L<line>)'
assert_eq "README boundary link labels snapshot keeps accepts/rejects vocabulary mapping" "$readme_boundary_vocab_expected" "$readme_boundary_vocab_line_normalized"
readme_boundary_accepts_count=$(printf "%s\n" "$readme_boundary_vocab_line_normalized" | grep -o 'accepts ' | wc -l | tr -d ' ')
readme_boundary_rejects_count=$(printf "%s\n" "$readme_boundary_vocab_line_normalized" | grep -o 'rejects ' | wc -l | tr -d ' ')
if [ "$readme_boundary_accepts_count" -eq 1 ] && [ "$readme_boundary_rejects_count" -eq 3 ]; then
  pass "README boundary link vocabulary ratio stays accepts=1/rejects=3 after mutual links"
else
  fail "README boundary link vocabulary ratio stays accepts=1/rejects=3 after mutual links" "accepts appears once and rejects appears three times in normalized '# 対応テスト' snapshot" "accepts=$readme_boundary_accepts_count rejects=$readme_boundary_rejects_count line=$readme_boundary_vocab_line_normalized"
fi

assert_eq "extract_failed_case_from_summary_line keeps leading digit" "0summary-failcase-contract-sentinel" "$(extract_failed_case_from_summary_line "$summary_line_leading_digit")"
assert_eq "extract_failed_case_from_summary_line keeps trailing digit" "summary-failcase-contract-sentinel0" "$(extract_failed_case_from_summary_line "$summary_line_trailing_digit")"
assert_eq "extract_failed_case_from_summary_line keeps both-edge digits" "0summary-failcase-contract-sentinel0" "$(extract_failed_case_from_summary_line "$summary_line_both_edge_digits")"
assert_eq "extract_failed_case_from_summary_line keeps single-letter case name" "a" "$(extract_failed_case_from_summary_line "$summary_line_single_alpha")"
assert_eq "extract_failed_case_from_summary_line keeps single-digit case name" "0" "$(extract_failed_case_from_summary_line "$summary_line_single_digit")"
assert_eq "extract_failed_case_from_summary_line rejects invalid trailing punctuation" "" "$(extract_failed_case_from_summary_line "$summary_line_trailing_paren")"

if [ "$SKIP_SUMMARY_FAILCASE_TEST" != "1" ]; then
  summary_fail_case="summary-failcase-contract-sentinel"
  summary_fail_case_with_double_dash="summary--failcase-contract-sentinel"
  summary_fail_case_with_dot_underscore="summary.failcase_contract.sentinel"
  summary_fail_case_with_space="summary failcase contract sentinel"

  run_selfcheck_capture "" summary
  summary_success_out="$RUN_SELF_CHECK_OUT"
  summary_success_code=$RUN_SELF_CHECK_CODE

  run_selfcheck_capture "$summary_fail_case" normal
  normal_out="$RUN_SELF_CHECK_OUT"
  normal_code=$RUN_SELF_CHECK_CODE

  run_selfcheck_capture "$summary_fail_case" summary
  summary_out="$RUN_SELF_CHECK_OUT"
  summary_code=$RUN_SELF_CHECK_CODE

  normal_fail_name=$(printf "%s\n" "$normal_out" | sed -n 's/^FAIL: //p' | head -n 1)
  summary_success_line_count=$(summary_line_count "$summary_success_out")
  summary_success_total_lines=$(printf "%s\n" "$summary_success_out" | sed '/^$/d' | wc -l | tr -d ' ')
  summary_success_detail_lines=$(summary_detail_line_count "$summary_success_out")
  summary_success_first_line=$(summary_first_nonempty_line "$summary_success_out")
  summary_line=$(printf "%s\n" "$summary_out" | grep '^SELF_CHECK_SUMMARY:' | head -n 1)
  summary_failure_line_count=$(summary_line_count "$summary_out")
  summary_failure_detail_lines=$(summary_detail_line_count "$summary_out")
  summary_first_line=$(summary_first_nonempty_line "$summary_out")
  summary_fail_name=$(summary_failed_case_name "$summary_out")
  normal_passed_count=$(printf "%s\n" "$normal_out" | grep -c '^PASS: ' | tr -d ' ')
  normal_total_count=$(printf "%s\n" "$normal_out" | grep -E -c '^(PASS|FAIL): ' | tr -d ' ')
  summary_passed_count=$(summary_passed_count_from_line "$summary_out")
  summary_total_count=$(summary_total_count_from_line "$summary_out")

  if [ "$summary_success_code" -eq 0 ] \
    && [ "$summary_success_line_count" -eq 1 ] \
    && [ "$summary_success_total_lines" -eq 1 ] \
    && [ "$summary_success_detail_lines" -eq 0 ] \
    && [ "$summary_success_first_line" = "$summary_success_out" ]; then
    pass "--summary outputs only one SELF_CHECK_SUMMARY line without PASS/FAIL details"
  else
    fail "--summary outputs only one SELF_CHECK_SUMMARY line without PASS/FAIL details" "single SELF_CHECK_SUMMARY line only (no PASS/FAIL detail lines and summary is first line)" "$(summary_contract_actual "$summary_success_code" "$summary_success_line_count" "$summary_success_first_line")"
  fi

  if printf "%s\n" "$summary_line" | grep -Eq '^SELF_CHECK_SUMMARY: passed=[0-9]+/[0-9]+ failed_case=[^[:space:]]+$'; then
    pass "--summary failure keeps SELF_CHECK_SUMMARY snapshot format"
  else
    fail "--summary failure keeps SELF_CHECK_SUMMARY snapshot format" "SELF_CHECK_SUMMARY: passed=<n>/<m> failed_case=<name>" "$(summary_contract_actual "$summary_code" "$summary_failure_line_count" "$summary_first_line")"
  fi

  if [ "$summary_code" -ne 0 ] && [ "$summary_first_line" = "$summary_line" ]; then
    pass "--summary failure keeps SELF_CHECK_SUMMARY as the first output line"
  else
    fail "--summary failure keeps SELF_CHECK_SUMMARY as the first output line" "first non-empty output line is SELF_CHECK_SUMMARY" "$(summary_contract_actual "$summary_code" "$summary_failure_line_count" "$summary_first_line")"
  fi

  summary_line_trimmed=$(printf "%s" "$summary_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  if [ "$summary_code" -ne 0 ] && [ "$summary_line" = "$summary_line_trimmed" ]; then
    pass "--summary failure SELF_CHECK_SUMMARY line has no leading/trailing spaces"
  else
    fail "--summary failure SELF_CHECK_SUMMARY line has no leading/trailing spaces" "summary line equals its trimmed form" "$(summary_contract_actual "$summary_code" "$summary_failure_line_count" "$summary_first_line")"
  fi

  if is_numeric "$summary_code"; then
    pass "--summary failure contract keeps summary_code as numeric"
  else
    fail "--summary failure contract keeps summary_code as numeric" "summary_code=<number>" "$(summary_contract_actual "$summary_code" "$summary_failure_line_count" "$summary_first_line")"
  fi

  if [ "$summary_code" -ne 0 ] && [ "$summary_failure_line_count" -eq 1 ]; then
    pass "--summary failure emits exactly one SELF_CHECK_SUMMARY line"
  else
    fail "--summary failure emits exactly one SELF_CHECK_SUMMARY line" "summary failure output contains exactly one SELF_CHECK_SUMMARY line" "$(summary_contract_actual "$summary_code" "$summary_failure_line_count" "$summary_first_line")"
  fi

  if [ "$summary_code" -ne 0 ] && [ "$summary_failure_detail_lines" -eq 0 ]; then
    pass "--summary failure output does not include PASS/FAIL detail lines"
  else
    fail "--summary failure output does not include PASS/FAIL detail lines" "summary failure output contains no PASS:/FAIL: detail lines" "$(summary_contract_actual "$summary_code" "$summary_failure_line_count" "$summary_first_line")"
  fi

  if [ "$normal_code" -ne 0 ] \
    && [ "$summary_code" -ne 0 ] \
    && [ "$normal_fail_name" = "$summary_fail_name" ] \
    && [ "$summary_fail_name" = "$summary_fail_case" ]; then
    pass "--summary failure reports failed_case matching normal-mode FAIL name"
  else
    fail "--summary failure reports failed_case matching normal-mode FAIL name" "normal/summary both fail and report identical case name ($summary_fail_case)" "$(summary_contract_actual "$summary_code" "$summary_failure_line_count" "$summary_first_line")"
  fi

  run_selfcheck_capture "$summary_fail_case_with_double_dash" summary
  summary_dd_out="$RUN_SELF_CHECK_OUT"
  summary_dd_code=$RUN_SELF_CHECK_CODE
  summary_dd_fail_name=$(summary_failed_case_name "$summary_dd_out")
  if [ "$summary_dd_code" -ne 0 ] && [ "$summary_dd_fail_name" = "$summary_fail_case_with_double_dash" ]; then
    pass "--summary failure keeps failed_case intact when case name contains double dash"
  else
    fail "--summary failure keeps failed_case intact when case name contains double dash" "failed_case preserves full case name ($summary_fail_case_with_double_dash)" "$(summary_contract_actual "$summary_dd_code" "$(summary_line_count "$summary_dd_out")" "$(summary_first_nonempty_line "$summary_dd_out")")"
  fi

  run_selfcheck_capture "$summary_fail_case_with_dot_underscore" summary
  summary_du_out="$RUN_SELF_CHECK_OUT"
  summary_du_code=$RUN_SELF_CHECK_CODE
  summary_du_fail_name=$(summary_failed_case_name "$summary_du_out")
  if [ "$summary_du_code" -ne 0 ] && [ "$summary_du_fail_name" = "$summary_fail_case_with_dot_underscore" ]; then
    pass "--summary failure keeps failed_case intact when case name contains dot and underscore"
  else
    fail "--summary failure keeps failed_case intact when case name contains dot and underscore" "failed_case preserves full case name ($summary_fail_case_with_dot_underscore)" "$(summary_contract_actual "$summary_du_code" "$(summary_line_count "$summary_du_out")" "$(summary_first_nonempty_line "$summary_du_out")")"
  fi

  run_selfcheck_capture "$summary_fail_case_with_space" summary
  summary_space_out="$RUN_SELF_CHECK_OUT"
  summary_space_code=$RUN_SELF_CHECK_CODE
  summary_space_fail_name=$(summary_failed_case_name "$summary_space_out")
  if [ "$summary_space_code" -ne 0 ] && [ "$summary_space_fail_name" = "$INVALID_FORCE_FAIL_CASE_NAME" ]; then
    pass "--summary rejects FORCE_FAIL_CASE values outside [a-z0-9._-]+"
  else
    fail "--summary rejects FORCE_FAIL_CASE values outside [a-z0-9._-]+" "failed_case becomes $INVALID_FORCE_FAIL_CASE_NAME when FORCE_FAIL_CASE contains spaces" "$(summary_contract_actual "$summary_space_code" "$(summary_line_count "$summary_space_out")" "$(summary_first_nonempty_line "$summary_space_out")")"
  fi

  if [ -n "$summary_passed_count" ] && [ "$normal_passed_count" = "$summary_passed_count" ]; then
    pass "--summary failure passed count matches normal-mode PASS count before failure"
  else
    fail "--summary failure passed count matches normal-mode PASS count before failure" "normal PASS count equals summary passed=<n>/<m> numerator" "$(summary_contract_actual "$summary_code" "$summary_failure_line_count" "$summary_first_line")"
  fi

  if [ -n "$summary_total_count" ] && [ "$normal_total_count" = "$summary_total_count" ]; then
    pass "--summary failure total count denominator matches normal-mode total checks"
  else
    fail "--summary failure total count denominator matches normal-mode total checks" "normal total PASS+FAIL count equals summary passed=<n>/<m> denominator" "$(summary_contract_actual "$summary_code" "$summary_failure_line_count" "$summary_first_line")"
  fi
fi

if [ -n "$FORCE_FAIL_CASE" ]; then
  fail "$FORCE_FAIL_CASE"
fi

if [ "$SUMMARY_MODE" = false ]; then
  echo "All checks passed."
fi
