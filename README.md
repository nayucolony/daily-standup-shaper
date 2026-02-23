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

## Implemented (watchdog 2026-02-23 19:52 JST)
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
- selfcheck PASS を確認（2026-02-23 19:52 JST, `./scripts/selfcheck.sh`）

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

名前ラベルが `Owner:` など独自形式の場合は `--header-name-keys` で判定キーを指定できます。

```bash
./bin/shape-standup --all --header-name-keys 'Owner|担当者' ./examples/patterns.txt
```

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

# custom key names
./bin/shape-standup --format json --json-keys done,plan,impediments ./examples/sample.txt

# custom entry meta key names
./bin/shape-standup --all --format json --json-include-entry-meta --json-entry-meta-keys idx,name ./examples/patterns.txt
```

`--json-entry-meta-keys` は **2つのキーをカンマ区切りで必須指定**します。

- 形式: `<indexKey>,<nameKey>`
- 例: `idx,name`
- 不正時: 非0終了 + `invalid --json-entry-meta-keys: use exactly 2 comma-separated keys`

不正値の例:
- 1キー: `--json-entry-meta-keys idx`
- 3キー: `--json-entry-meta-keys idx,name,person`
- 空値: `--json-entry-meta-keys ''`

`--json-include-entry-meta` は **`--all --format json` のときだけ有効**です。

- `single + json` で指定した場合は無視され、通常のsingle JSON（yesterday/today/blockersのみ）を返します。

## Strict mode (CI向け)
必須3項目（Yesterday / Today / Blockers）のいずれかが未抽出なら、出力後に非0で終了します。

- 終了コード: `2`
- stderrフォーマット:
  - single: `strict mode: missing required fields (<csv>)`
  - all: `strict mode: missing required fields in one or more entries (entryN:<csv>;...)`
- `<csv>` は `yesterday,today,blockers` の不足項目

例:
- `strict mode: missing required fields (blockers)`
- `strict mode: missing required fields in one or more entries (entry1:blockers;entry3:today,blockers)`

```bash
./bin/shape-standup --strict ./examples/sample.txt
```

## Quiet mode
`--strict` と併用して、警告メッセージ（stderr）を抑制したい時に使います。

```bash
./bin/shape-standup --strict --quiet ./examples/sample.txt
```

## Label synonyms config
`config/labels.json` でラベル同義語を拡張できます。必要なら `--labels` で別ファイルを指定可能です。

最小テンプレートは `config/labels.example.json` を利用できます。

```bash
cp ./config/labels.example.json ./config/labels.local.json
./bin/shape-standup --labels ./config/labels.local.json ./examples/sample.txt
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

## Next
- `README` の Implemented タイムスタンプを最新watchdog時刻へ更新する
