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
readme_quiet_table_expected=$(cat "$ROOT_DIR/tests/snapshots/readme-strict-quiet-matrix.md")
assert_eq "README strict/quiet matrix snapshot matches expected markdown table" "$readme_quiet_table_expected" "$readme_quiet_table_actual"

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
assert_eq "failed_case boundary contrast accepts 0foo (README one-line acceptance)" "0foo" "$(extract_failed_case_from_summary_line "$summary_line_boundary_accept_0foo")"
assert_eq "failed_case boundary contrast rejects Foo (README one-line acceptance)" "" "$(extract_failed_case_from_summary_line "$summary_line_boundary_reject_Foo")"
for rejected_boundary_case in "$summary_line_trailing_upper|fooA (uppercase suffix)" "$summary_line_with_slash|foo/bar (slash delimiter)"; do
  line_value=${rejected_boundary_case%%|*}
  case_label=${rejected_boundary_case#*|}
  assert_eq "failed_case boundary contrast rejects ${case_label} (README one-line acceptance)" "" "$(extract_failed_case_from_summary_line "$line_value")"
done
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
