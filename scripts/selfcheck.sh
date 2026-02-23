#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT_DIR/bin/shape-standup"

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1" >&2
  if [ "${2:-}" != "" ]; then
    echo "--- expected ---" >&2
    echo "$2" >&2
    echo "--- actual ---" >&2
    echo "$3" >&2
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
if [ "$quiet_code" -ne 0 ]; then
  pass "--quiet keeps strict non-zero exit"
else
  fail "--quiet keeps strict non-zero exit" "non-zero exit" "code=$quiet_code"
fi

set +e
strict_stdout=$(printf "%s\n" "$strict_missing_input" | "$CLI" --strict --quiet 2>/tmp/shape_quiet_err.txt)
strict_stdout_code=$?
strict_stderr=$(cat /tmp/shape_quiet_err.txt)
set -e
if [ "$strict_stdout_code" -ne 0 ] && echo "$strict_stdout" | grep -q "## Yesterday" && ! echo "$strict_stdout" | grep -qi "strict mode" && [ -z "$strict_stderr" ]; then
  pass "--quiet suppresses strict warning message"
else
  fail "--quiet suppresses strict warning message" "non-zero exit + markdown output + empty stderr" "stdout=$strict_stdout | stderr=$strict_stderr | code=$strict_stdout_code"
fi

strict_all_input=$(cat <<'IN'
Yesterday: A done
Today: A plan

Yesterday: B done
Today: B plan
Blockers: B blocker
IN
)
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
strict_all_quiet_stdout=$(printf "%s\n" "$strict_all_input" | "$CLI" --all --strict --quiet 2>/tmp/shape_strict_all_quiet_err.txt)
strict_all_quiet_code=$?
strict_all_quiet_err=$(cat /tmp/shape_strict_all_quiet_err.txt)
set -e
if [ "$strict_all_quiet_code" -ne 0 ] \
  && [ -z "$strict_all_quiet_err" ] \
  && echo "$strict_all_quiet_stdout" | grep -q "### Entry 1" \
  && echo "$strict_all_quiet_stdout" | grep -q "## Blockers"; then
  pass "--all --strict --quiet suppresses stderr and keeps markdown output"
else
  fail "--all --strict --quiet suppresses stderr and keeps markdown output" "non-zero exit + empty stderr + markdown output" "stdout=$strict_all_quiet_stdout | stderr=$strict_all_quiet_err | code=$strict_all_quiet_code"
fi

set +e
strict_all_json_stdout=$(printf "%s\n" "$strict_all_input" | "$CLI" --all --strict --format json 2>/tmp/shape_strict_all_json_err.txt)
strict_all_json_code=$?
strict_all_json_err=$(cat /tmp/shape_strict_all_json_err.txt)
set -e
if [ "$strict_all_json_code" -ne 0 ] \
  && echo "$strict_all_json_err" | grep -q "entry1:blockers" \
  && printf "%s" "$strict_all_json_stdout" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==2'; then
  pass "--all --strict --format json keeps JSON output and reports entry-wise missing fields"
else
  fail "--all --strict --format json keeps JSON output and reports entry-wise missing fields" "non-zero exit + stderr includes entry1:blockers + stdout is valid JSON array" "stdout=$strict_all_json_stdout | stderr=$strict_all_json_err | code=$strict_all_json_code"
fi

set +e
strict_all_json_quiet_stdout=$(printf "%s\n" "$strict_all_input" | "$CLI" --all --strict --quiet --format json 2>/tmp/shape_strict_all_json_quiet_err.txt)
strict_all_json_quiet_code=$?
strict_all_json_quiet_err=$(cat /tmp/shape_strict_all_json_quiet_err.txt)
set -e
if [ "$strict_all_json_quiet_code" -ne 0 ] \
  && [ -z "$strict_all_json_quiet_err" ] \
  && printf "%s" "$strict_all_json_quiet_stdout" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==2'; then
  pass "--all --strict --quiet --format json suppresses stderr and keeps JSON output"
else
  fail "--all --strict --quiet --format json suppresses stderr and keeps JSON output" "non-zero exit + empty stderr + stdout is valid JSON array" "stdout=$strict_all_json_quiet_stdout | stderr=$strict_all_json_quiet_err | code=$strict_all_json_quiet_code"
fi

set +e
strict_missing_file_stdout=$("$CLI" --all --strict --format json "$ROOT_DIR/examples/strict-missing.txt" 2>/tmp/shape_strict_missing_file_err.txt)
strict_missing_file_code=$?
strict_missing_file_err=$(cat /tmp/shape_strict_missing_file_err.txt)
set -e
if [ "$strict_missing_file_code" -ne 0 ] \
  && echo "$strict_missing_file_err" | grep -q "^strict mode: missing required fields in one or more entries" \
  && echo "$strict_missing_file_err" | grep -q "entry1:blockers;entry3:today,blockers" \
  && printf "%s" "$strict_missing_file_stdout" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)==3'; then
  pass "examples/strict-missing.txt regression keeps strict stderr prefix compatibility and expected entry details"
else
  fail "examples/strict-missing.txt regression keeps strict stderr prefix compatibility and expected entry details" "non-zero exit + stderr starts with strict prefix and includes entry1:blockers;entry3:today,blockers + stdout is valid JSON array" "stdout=$strict_missing_file_stdout | stderr=$strict_missing_file_err | code=$strict_missing_file_code"
fi

echo "All checks passed."
