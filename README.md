# daily-standup-shaper

会議メモの箇条書きを、朝会共有用の3ブロック（Yesterday / Today / Blockers）に整形するミニCLI。

## Why now (2026-02-23)
既存テーマが「会議クローズ後の整理」中心だったため、**朝会の直前整形**に特化した当日新規テーマとして開始。

## MVP
- 入力: プレーンテキスト（複数行）
- 出力: Markdownで以下3見出しを生成
  - Yesterday
  - Today
  - Blockers

## Demo video
`nano-banana-pro` で生成したデモフレームをもとに作成した簡易デモ動画です。

![daily-standup-shaper demo](./assets/demo/daily-standup-shaper-demo.gif)

- MP4: `./assets/demo/daily-standup-shaper-demo.mp4`
- GIF: `./assets/demo/daily-standup-shaper-demo.gif`

## Implemented
- 入力パターンを3系統追加（日本語ラベル / Englishラベル / Done-Plan-Risk）
- 抽出失敗時のフォールバック文言を実装
- `examples/patterns.txt` に Pattern D（ラベル直下の複数箇条書き）を追加
- 箇条書き連結の自動テスト `scripts/selfcheck.sh` を追加
- `--format json` を追加（singleはオブジェクト、`--all` は配列）
- `--strict` を追加（未抽出項目がある場合に非0終了）
- `--quiet` を追加（strict失敗時の警告を抑制して出力のみ保持）
- `--json-keys` を追加（json出力キー名を `done,plan,impediments` などに変更可能）
- `--no-entry-header` を追加（`--all` のMarkdown出力で `### Entry N` 見出しを省略可能）
- `Name:` / `名前:` がある段落では `### Entry N (名前)` として見出しに反映
- `scripts/selfcheck.sh` に `--labels` カスタムファイル読み込みテストを追加
- `--labels` のJSON検証を追加（必須キー欠落・型不正を明示エラー化）
- `--json-include-entry-meta` を追加（`--all --format json` で `entryIndex` / `entryName` を付与可能）
- selfcheck PASS を確認（`./scripts/selfcheck.sh`）
- `./scripts/selfcheck.sh --summary` を追加（CI向け1行サマリ: passed/failed_case）

## Pattern D (multiline bullets)
以下のような入力を 1 項目に連結して出力します。

```text
昨日:
- APIモック作成
- 認可テスト追加
```

出力（Yesterday）:

```text
- APIモック作成 / 認可テスト追加
```

## Quick check
```bash
./scripts/selfcheck.sh

# CI向け1行サマリ
./scripts/selfcheck.sh --summary

# --summary 失敗例（期待: 先頭1行が SUMMARY / 終了コードは非0）
set +e
SELF_CHECK_FORCE_FAIL_CASE=summary-failcase-contract-sentinel \
SELF_CHECK_SKIP_SUMMARY_FAILCASE_TEST=1 \
./scripts/selfcheck.sh --summary > /tmp/dss-summary-fail.out
code=$?
set -e
head -n 1 /tmp/dss-summary-fail.out  # SELF_CHECK_SUMMARY: passed=<n>/<m> failed_case=summary-failcase-contract-sentinel
[ "$code" -ne 0 ] && echo "PASS: summary failure contract"
```

補足: `scripts/selfcheck.sh` は失敗系検証を `expect_fail_contains` ヘルパーで共通化しており、
不正引数ケースの追加時に重複を減らせる構成です。

## Multi-person input
空行区切りで複数人分が入っている場合は `--all` を使うと、段落ごとに `Entry N` として整形します。

```bash
./bin/shape-standup --all ./examples/patterns.txt
```

各段落に `Name:` / `名前:` がある場合、Entry見出しに名前を表示します（例: `### Entry 1 (Alice)`）。

名前が見つからない段落は `### Entry N`（括弧なし）で出力されます。

`--header-name-keys` を指定した場合も、指定キーで値を抽出できなかった段落は同様に `### Entry N` になります。

名前ラベルが `Owner:` など独自形式の場合は `--header-name-keys` で判定キーを指定できます。

```bash
./bin/shape-standup --all --header-name-keys 'Owner|担当者' ./examples/patterns.txt
```

`--header-name-keys` は区切り文字 `|` の前後スペースを自動で無視します（例: `' Owner | 担当者 '` でも同じ結果）。

`Owner/担当者` が混在し、かつ値が空の段落を1コマンドで再現する場合は次を実行します（Pattern E）。

```bash
./bin/shape-standup --all --format json --json-include-entry-meta --json-entry-meta-keys idx,name --header-name-keys 'Owner|担当者' ./examples/patterns.txt
```

期待値: `Owner: Carol` の段落は `"name":"Carol"`、`担当者:` が空の段落は `"name":""` になります。

Entry見出しが不要な場合は `--no-entry-header` を併用できます。

```bash
./bin/shape-standup --all --no-entry-header ./examples/patterns.txt
```

## JSON output
他ツール連携向けに `--format json` が使えます。

> Note: JSON entry meta 系オプション（`--json-include-entry-meta` / `--json-entry-meta-keys`）は `--all --format json` の組み合わせでのみ有効です（`--help` と同一表現）。

CLIヘルプと同じ注意書き（再掲）:
- `JSON entry meta options are effective only with: --all --format json`

```bash
# single
./bin/shape-standup --format json ./examples/sample.txt

# all entries
./bin/shape-standup --all --format json ./examples/patterns.txt

# all entries with meta
./bin/shape-standup --all --format json --json-include-entry-meta ./examples/patterns.txt

# all entries with meta + custom header name keys
./bin/shape-standup --all --format json --json-include-entry-meta --header-name-keys 'Owner|担当者' ./examples/patterns.txt

# custom key names
./bin/shape-standup --format json --json-keys done,plan,impediments ./examples/sample.txt

# custom entry meta key names
./bin/shape-standup --all --format json --json-include-entry-meta --json-entry-meta-keys idx,name ./examples/patterns.txt

# reproduce "name becomes empty when no header name is found"
./bin/shape-standup --all --format json --json-include-entry-meta --json-entry-meta-keys idx,name --header-name-keys 'Owner|担当者' ./examples/patterns.txt
```

実出力例（上記コマンド、先頭2エントリのみ）:

```json
[
  {
    "idx": 1,
    "name": "",
    "yesterday": "APIモック作成",
    "today": "ログインUI接続",
    "blockers": "stagingの環境変数不足"
  },
  {
    "idx": 2,
    "name": "",
    "yesterday": "fixed flaky test in auth module",
    "today": "implement onboarding banner",
    "blockers": "waiting for copy review"
  }
]
```

`--json-entry-meta-keys` は **2つのキーをカンマ区切りで必須指定**します。

- 形式: `<indexKey>,<nameKey>`
- 最小テンプレ: `idx,name`
- 推奨テンプレ: `entryIndex,entryName`（既定キー名と同じで可読性を保ちやすい）
- 不正時: 非0終了 + `invalid --json-entry-meta-keys: use exactly 2 comma-separated keys`

```bash
# 最小（短いキー）
./bin/shape-standup --all --format json --json-include-entry-meta --json-entry-meta-keys idx,name ./examples/patterns.txt

# 推奨（意味が伝わるキー）
./bin/shape-standup --all --format json --json-include-entry-meta --json-entry-meta-keys entryIndex,entryName ./examples/patterns.txt
```

`--all --format json --json-include-entry-meta` で meta を有効化した場合、
`--json-keys` と `--json-entry-meta-keys` のキー名重複は明示エラーで停止します。

- 例: `--json-keys yesterday,today,name --json-entry-meta-keys idx,name`
- エラー: `json key conflict: duplicate key name(s): name`

不正値の例:
- 1キー: `--json-entry-meta-keys idx`
- 3キー: `--json-entry-meta-keys idx,name,person`
- 空値: `--json-entry-meta-keys ''`

`--json-include-entry-meta` は **`--all --format json` のときだけ有効**です。

- `single + json` で指定した場合は無視され、通常のsingle JSON（yesterday/today/blockersのみ）を返します。
- `--header-name-keys` 併用時に名前抽出できなかった段落は、entry meta の名前キー（既定では `entryName`、`--json-entry-meta-keys` 指定時は第2キー）が空文字 `""` になります。

## CLI help snapshot (strict/quiet consistency)
`./bin/shape-standup --help` の strict/quiet 説明と README 文言の差分を検知するため、
README側にもヘルプ文言をそのまま保持します（selfcheck で照合）。

- `--strict`: Exit non-zero when any of Yesterday/Today/Blockers is missing
- `--quiet`: Suppress strict warning messages on stderr

## Strict mode (CI向け)
必須3項目（Yesterday / Today / Blockers）のいずれかが未抽出なら、出力後に非0で終了します。

> Quiet運用時のstderr抑制と終了コード維持については [Quiet mode](#quiet-mode) を参照してください。

- 終了コード: `2`
- stderrフォーマット:
  - single: `strict mode: missing required fields (<csv>)`
  - all: `strict mode: missing required fields in one or more entries (entryN:<csv>;...)`
- `<csv>` は `yesterday,today,blockers` の不足項目
- `--all --strict --format json` でも同じ entry単位エラー（例: `entry1:blockers`）を stderr に出しつつ、stdout には JSON 配列を維持します

例:
- `strict mode: missing required fields (blockers)`
- `strict mode: missing required fields in one or more entries (entry1:blockers;entry3:today,blockers)`

```bash
./bin/shape-standup --strict ./examples/sample.txt

# single の stderr 先頭プレフィックス確認（missing blockers）
printf 'Yesterday: done\nToday: plan\n' | ./bin/shape-standup --strict
# stderr: strict mode: missing required fields (blockers)

# --all + jsonでも、entry単位エラーをstderrに出しつつstdout JSON配列は維持
./bin/shape-standup --all --strict --format json ./examples/strict-missing.txt
# stderr: strict mode: missing required fields in one or more entries (entry1:blockers;entry3:today,blockers)

# strict失敗時の終了コード契約（2）を examples/strict-missing.txt で再現
set +e
./bin/shape-standup --all --strict --format json ./examples/strict-missing.txt >/tmp/dss-strict-out.json
code=$?
set -e
echo "$code"  # 2
```

再確認チェックリスト（quiet併用時）:
- [ ] `--strict --quiet` 実行時に stderr が空でも、終了コード `2` を維持している
- [ ] `--all --strict --quiet --format json` 実行時に stdout JSON を維持したまま、終了コード `2` を維持している

## Quiet mode
`--strict` と併用して、警告メッセージ（stderr）を抑制したい時に使います。

> `--quiet` は stderr のみを抑制し、strictの失敗契約（終了コード `2`）は維持されます。strictの契約全体は [Strict mode (CI向け)](#strict-mode-ci向け) を参照してください。

```bash
./bin/shape-standup --strict --quiet ./examples/sample.txt
```

`--all --strict --quiet --format json` でも契約は同じです。

- 終了コード `2` は維持（strict契約を継承）
- stdout は JSON 配列を維持
- stderr は空（完全無出力）

受け入れ条件（P34, single/markdown）:
- `--strict --quiet` で **stdout=Markdown維持 / stderr=空 / exit code=2** を同時に満たすこと

運用確認ワンライナー（P38）:
```bash
for mode in single all; do
  err=$(mktemp)
  if [ "$mode" = "single" ]; then
    printf 'Yesterday: done\nToday: do\n' | \
      ./bin/shape-standup --strict --quiet /dev/stdin >/dev/null 2>"$err"; code=$?
  else
    ./bin/shape-standup --all --strict --quiet ./examples/strict-missing.txt >/dev/null 2>"$err"; code=$?
  fi
  [ "$code" -eq 2 ] && [ ! -s "$err" ] && echo "PASS $mode" || echo "FAIL $mode code=$code stderr=$(cat "$err")"
  rm -f "$err"
done
```

対応表:

| mode | 入力経路（file/stdin） | stdout | exit code | stderr | 再現コマンド（1行） | 要約（運用判断） |
|---|---|---|---|---|---|---|
| `--strict --quiet` (single/markdown) | stdin | Markdown (`## Yesterday` など) | 2（strict失敗契約を維持） | 空 | `printf 'Yesterday: done\nToday: do\n' \| ./bin/shape-standup --strict --quiet /dev/stdin >/tmp/dss-single-md.out 2>/tmp/dss-single-md.err; echo $?` | Markdown維持 + stderr空 + exit 2 |
| `--strict --quiet --format json` (single/json) | stdin | JSONオブジェクト | 2 | 空 | `printf 'Yesterday: done\nToday: do\n' \| ./bin/shape-standup --strict --quiet --format json /dev/stdin >/tmp/dss-single-json.out 2>/tmp/dss-single-json.err; echo $?` | JSON維持 + stderr空 + exit 2 |
| `--all --strict --quiet` (all/markdown) | file | Markdown（`### Entry N` を含む） | 2 | 空 | `./bin/shape-standup --all --strict --quiet ./examples/strict-missing.txt >/tmp/dss-all-md.out 2>/tmp/dss-all-md.err; echo $?` | Markdown維持 + stderr空 + exit 2 |
| `--all --strict --quiet --format json` (all/json) | file | JSON配列 | 2 | 空 | `./bin/shape-standup --all --strict --quiet --format json ./examples/strict-missing.txt >/tmp/dss-all-json.out 2>/tmp/dss-all-json.err; echo $?` | JSON維持 + stderr空 + exit 2 |

## Label synonyms config
`config/labels.json` でラベル同義語を拡張できます。必要なら `--labels` で別ファイルを指定可能です。

最小テンプレートは `config/labels.example.json` を利用できます。

```bash
cp ./config/labels.example.json ./config/labels.local.json
./bin/shape-standup --labels ./config/labels.local.json ./examples/sample.txt

# examples 付属のサンプルを使う場合
./bin/shape-standup --labels ./examples/labels.local.json ./examples/sample.txt
```

### labels JSON schema (minimum)
- ルートはオブジェクト
- 必須キー: `yesterday`, `today`, `blockers`
- 各キーは文字列配列（同義語の候補）
- 不正時はエラーメッセージに対象ファイルパスを含めて表示
- 不正時は非0終了し、stderrに理由を表示
  - 例: `invalid labels JSON (./config/labels.local.json): missing required keys: blockers`
  - 例: `invalid labels JSON (./config/labels.local.json): key 'today' must be an array of strings`

```json
{
  "yesterday": ["Yesterday", "Done"],
  "today": ["Today", "Plan"],
  "blockers": ["Blockers", "Impediments"]
}
```

## Update Plan (watchdog 2026-02-24 12:20 JST)
反復判定（直近5サイクル）: summary契約回帰系 5/5 で閾値到達。P55で失敗メッセージ形式を固定化したため、次は同系の重複検証を減らしつつ契約差分検知力を上げる候補へ再優先付け。

優先度は Impact(高) / Effort(低) / Evidence readiness(可) で並べています。

- [x] P39: `scripts/selfcheck.sh` に Quiet mode 契約ワンライナー相当（single/all の exit=2 + stderr空）を `for mode in ...` で1ブロック検証する節を追加し、README手順との同型性を高める（Impact: 2, Effort: 2, Evidence: yes）
- [x] P40: `scripts/selfcheck.sh` の Quiet/Strict検証ブロックを関数化して重複を削減し、失敗時ログ（mode/code/stderr）を1形式に統一する（Impact: 4, Effort: 2, Evidence: yes）
- [x] P41: `--strict --quiet` の single/all/json を `examples/strict-missing.txt` と標準入力の両系統で再検証し、入力経路差分がないことを回帰化する（Impact: 4, Effort: 3, Evidence: yes）
- [x] P42: README Quiet mode 対応表に「入力経路（file/stdin）」列を追加し、運用時の再現コマンドを各行へ1つずつ明示する（Impact: 3, Effort: 1, Evidence: yes）
- [x] P43: `./bin/shape-standup --help` の quiet/strict説明と README 文言の差分を selfcheck で検知する簡易スナップショット比較を追加（Impact: 3, Effort: 3, Evidence: yes）
- [x] P44: CI向けに `./scripts/selfcheck.sh` 実行結果の要約（checks passed / failed case）を1行出力するオプションを追加（Impact: 2, Effort: 3, Evidence: yes）
- [x] P45: `scripts/selfcheck.sh` の strict/quiet 回帰で使用する一時stderrファイル（`/tmp/shape_*`）を `trap` で自動削除し、CI環境での残骸をなくす（Impact: 2, Effort: 2, Evidence: yes）
- [x] P46: `scripts/selfcheck.sh --summary` 失敗時に `failed_case` と同じ名前の `FAIL:` 行が通常モード出力に存在することを検証し、CIログ突合を簡単にする（Impact: 2, Effort: 2, Evidence: yes）
- [x] P47: `scripts/selfcheck.sh --summary` の失敗例で `passed=<n>/<m>` が通常モードの失敗直前までの PASS 件数と一致することを検証し、進捗率の信頼性を固定する（Impact: 2, Effort: 2, Evidence: yes）
- [x] P48: `scripts/selfcheck.sh --summary` の失敗例で `<m>`（総チェック数）が通常モード実行時の総チェック数（FAILケース含む）と一致することを検証し、分母の信頼性を固定する（Impact: 2, Effort: 2, Evidence: yes）
- [x] P49: `scripts/selfcheck.sh --summary` の失敗系回帰ブロック（P46-P48）に対し、`SELF_CHECK_SUMMARY` 行のフォーマット変化（`passed=<n>/<m> failed_case=<name>`）を1回で検知する単一スナップショット検証を追加する（Impact: 2, Effort: 2, Evidence: yes）
- [x] P50: `scripts/selfcheck.sh --summary` 実行時に `SELF_CHECK_SUMMARY` 行が1行のみで、`PASS:` / `FAIL:` の詳細行が混在しないことを検証し、CIの行パース前提を固定する（Impact: 2, Effort: 2, Evidence: yes）
- [x] P51: `scripts/selfcheck.sh --summary` の成功時/失敗時で `SELF_CHECK_SUMMARY` 接頭辞が常に先頭行に出ること（余分な前置ログなし）を回帰追加し、ログ収集の先頭行パース互換を固定する（Impact: 2, Effort: 2, Evidence: yes）
- [x] P52: `scripts/selfcheck.sh --summary` の失敗時に `SELF_CHECK_SUMMARY` 行が **ちょうど1行のみ**（重複なし）であることを回帰追加し、ログ収集の重複行パース揺れを防ぐ（Impact: 2, Effort: 2, Evidence: yes）
- [x] P53: `scripts/selfcheck.sh --summary` の失敗時に `PASS:` / `FAIL:` 詳細行が混在しないことを失敗系専用で回帰追加し、CIの単一行パーサ互換をさらに固定する（Impact: 3, Effort: 2, Evidence: yes）
- [x] P54: README Quick check に `--summary` 失敗例（期待: 先頭1行が SUMMARY、終了コード非0）を追記し、運用者向けの受け入れ条件を明示する（Impact: 2, Effort: 1, Evidence: yes）
- [x] P55: `scripts/selfcheck.sh` の summary契約回帰ブロックを関数化し、失敗時メッセージを `summary_code/summary_lines/first_line` の固定形式に統一する（Impact: 2, Effort: 2, Evidence: yes）
- [ ] P56: summary失敗時の固定形式（`summary_code/summary_lines/first_line`）を README Quick check に追記し、運用者が失敗ログを即読できる受け入れ条件を追加する（Impact: 3, Effort: 1, Evidence: yes）
- [ ] P57: `scripts/selfcheck.sh` に summary契約テスト用のヘルパー関数（成功/失敗ケース実行と項目抽出）を追加し、重複コマンド列を削減する（Impact: 3, Effort: 2, Evidence: yes）
- [ ] P58: `scripts/selfcheck.sh --summary` の出力を `grep -E` 1本で検証できる最小CI例を README に追加し、外部CIへの移植性を上げる（Impact: 2, Effort: 1, Evidence: yes）

## Next
- P56実施: README Quick check に `summary_code/summary_lines/first_line` 固定形式の失敗時ログ受け入れ条件を追記する
