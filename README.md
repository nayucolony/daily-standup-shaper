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

## Strict mode (CI向け)
必須3項目（Yesterday / Today / Blockers）のいずれかが未抽出なら、出力後に非0で終了します。

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
```

## Quiet mode
`--strict` と併用して、警告メッセージ（stderr）を抑制したい時に使います。

```bash
./bin/shape-standup --strict --quiet ./examples/sample.txt
```

`--all --strict --quiet --format json` でも契約は同じです。

- 非0終了は維持
- stdout は JSON 配列を維持
- stderr は空（完全無出力）

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

## Update Plan (watchdog 2026-02-24 07:00 JST)
反復判定（直近5サイクル: P22→P26）では同一作業ファミリ比率は 3/5 = 0.60 で閾値到達のため、同系ループ回避として計画上位のP27（`--all --strict --quiet --format json` のstderr完全無出力契約）を実行しました。

優先度は Impact(高) / Effort(低) / Evidence readiness(可) で並べています。

- [x] P14: `--json-entry-meta-keys idx,name` を指定しても `--json-include-entry-meta` なしでは metaキー自体が出力されないことを `scripts/selfcheck.sh` に追加（Impact: 4, Effort: 2, Evidence: yes）
- [x] P15: `--header-name-keys` の区切り文字前後スペース（例: `'Owner | 担当者'`）を正規化し、READMEとselfcheckで保証する（Impact: 4, Effort: 2, Evidence: yes）
- [x] P16: `--json-keys` と `--json-entry-meta-keys` のキー重複（例: `yesterday,name`）を検出して明示エラー化（Impact: 5, Effort: 3, Evidence: yes）
- [x] P17: `--all --strict --format json` の失敗時メッセージに entry index と不足キーをJSON側仕様でも明記する回帰テストを追加（Impact: 3, Effort: 2, Evidence: yes）
- [x] P18: `examples/patterns.txt` に `Owner/担当者` 混在＋空値ケースを追加し、READMEから1コマンド再現できるようにする（Impact: 3, Effort: 2, Evidence: yes）
- [x] P19: Pattern E（`examples/patterns.txt`）の README記載コマンド期待値（idx/name）を `scripts/selfcheck.sh` で固定（Impact: 4, Effort: 2, Evidence: yes）
- [x] P20: README `Usage` に Pattern E の検証ワンライナーを追記し、手動再現性をCLIヘルプ導線からも辿れるようにする（Impact: 3, Effort: 1, Evidence: yes）
- [x] P21: `--header-name-keys` 未指定時の Pattern E（Owner/担当者混在）挙動を `scripts/selfcheck.sh` へ追加し、name空文字フォールバックを明示化（Impact: 4, Effort: 2, Evidence: yes）
- [x] P22: README `JSON output` に `--json-entry-meta-keys idx,name` の最小/推奨テンプレを追加し誤設定率を低減（Impact: 2, Effort: 1, Evidence: yes）
- [x] P23: `--all --strict --format json` の stderr 実例（entry単位）を `examples/` 入力付きでREADMEに追記し、運用者の再現手順を1コマンド化（Impact: 2, Effort: 1, Evidence: yes）
- [x] P24: `examples/strict-missing.txt` を使った strict stderr 期待値を `scripts/selfcheck.sh` に追加し、README記載コマンドの回帰を自動検証化（Impact: 4, Effort: 2, Evidence: yes）
- [x] P25: strictエラー文言の先頭プレフィックス（`strict mode: missing required fields in one or more entries`）まで selfcheck で固定し、stderr互換性を明示保証（Impact: 3, Effort: 2, Evidence: yes）
- [x] P26: strict single/all のエラーメッセージ冒頭一致を `scripts/selfcheck.sh` で回帰化し、READMEへsingle/all両方の固定サンプルを追記（Impact: 2, Effort: 2, Evidence: yes）
- [x] P27: `--all --strict --quiet --format json` の stderr 完全無出力（空）を `scripts/selfcheck.sh` で回帰固定し、README Quiet mode に契約を追記（Impact: 3, Effort: 2, Evidence: yes）

## Next
- P28候補: `--all --strict --quiet`（markdown出力）でも stderr 完全無出力かつ非0終了を `scripts/selfcheck.sh` で固定し、Quiet mode 節へ single/json との対応表を追記（Impact: 3, Effort: 2, Evidence: yes）
