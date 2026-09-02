# toggl-report

Toggl Track から指定した月の作業時間を CSV で書き出し、報告用メッセージをクリップボードにコピーする macOS 向けシェルスクリプト。

## できること

- 今月・先月から対象月を選んで [Toggl Reports API v3](https://engineering.toggl.com/docs/reports_start) の詳細レポートを CSV で取得
- **billable なエントリのみ**を対象（billable off のエントリは取得時点で除外）
- 各エントリの Duration を **5 分単位で切り上げ**
- `Currency` / `Amount` / `Billable` 列を除外（`Tags` 列はそのまま残ります）
- 末尾に合計行を追加
- 合計時間を入れた報告メッセージをクリップボードへコピー
- Finder で出力ファイルを表示

## 必要なもの

- macOS（`date -v` / `pbcopy` / `open` を利用）
- `bash`, `curl`, `python3`

## セットアップ

```bash
git clone <このリポジトリ> ~/Code/toggl-report
cd ~/Code/toggl-report
cp .env.example .env
$EDITOR .env   # API トークンなどを設定
```

`.env` は `.gitignore` 済みです。コミットしないでください。

### 設定項目

| 変数 | 必須 | 説明 |
|---|---|---|
| `TOGGL_API_TOKEN` | ✅ | Toggl Track の API トークン |
| `TOGGL_WORKSPACE_ID` | ✅ | 対象ワークスペース ID |
| `TOGGL_PROJECT_ID` | ✅ | 対象プロジェクト ID |
| `TOGGL_OUTPUT_PREFIX` | | CSV ファイル名のプレフィックス（既定: `toggl-report`） |
| `TOGGL_OUTPUT_DIR` | | CSV の出力先ディレクトリ（既定: `$HOME`） |
| `TOGGL_REPORT_MENTIONS` | | 報告メッセージ先頭に差し込むメンション |

`.env` の場所は環境変数 `TOGGL_REPORT_ENV` で上書きできます。

## 使い方

```bash
./toggl-report.sh
```

エイリアスを張っておくと便利です。

```bash
alias toggl-report='~/Code/toggl-report/toggl-report.sh'
```

実行すると対象月の選択を求められ、`<プレフィックス>-YYYY-MM.csv` が出力されます。

## ライセンス

MIT
