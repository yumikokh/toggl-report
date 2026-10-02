# toggl-report

Toggl Track から指定した月の作業時間を CSV で書き出し、報告用メッセージをクリップボードにコピーする macOS 向けシェルスクリプト。

## できること

- 今月・先月から対象月を選んで [Toggl Reports API v3](https://engineering.toggl.com/docs/reports_start) の詳細レポートを CSV で取得
- **billable なエントリのみ**を対象（billable off のエントリは取得時点で除外）
- 各エントリの Duration を **5 分単位で切り上げ**
- `Currency` / `Amount` / `Billable` 列を除外（`Tags` 列はそのまま残ります）
- 末尾に合計行を追加
- 合計時間を入れた報告メッセージをクリップボードへコピー
- **Slack へ CSV 添付付きで投稿**（任意・送信前に y/N の確認あり）
- **Misoca に請求書を作成**（任意・作成前に y/N の確認あり。送付はしない）
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
| `SLACK_BOT_TOKEN` | | Slack Bot User OAuth Token（`xoxb-`） |
| `SLACK_CHANNEL_ID` | | 投稿先チャンネル ID（`C…`） |
| `MISOCA_INVOICE_ENDPOINT` | | 請求書作成 API の URL（notion-update-trigger の `/api/misoca/invoice`） |
| `MISOCA_INVOICE_BASIC_AUTH` | | 上記 API の Basic 認証（`user:password`） |

`.env` の場所は環境変数 `TOGGL_REPORT_ENV` で上書きできます。

## Slack 送信（任意）

`SLACK_BOT_TOKEN` と `SLACK_CHANNEL_ID` の**両方**を設定すると、CSV 生成後に送信確認のプロンプトが出ます。どちらか欠けている場合は従来どおりクリップボードへのコピーのみで終了します。

### Slack app の準備

1. https://api.slack.com/apps → **Create New App** → *From scratch* でアプリを作成し、対象ワークスペースを選択
2. **OAuth & Permissions** → *Scopes* → *Bot Token Scopes* に **`files:write`** を追加
3. 同じページの **Install to Workspace** でインストールし、**Bot User OAuth Token**（`xoxb-` で始まる）をコピーして `.env` の `SLACK_BOT_TOKEN` に設定
4. 投稿したいチャンネルで `/invite @<アプリ名>` を実行して bot を招待
5. チャンネル ID（`C` で始まる）を `.env` の `SLACK_CHANNEL_ID` に設定
   （チャンネル名を右クリック → *リンクをコピー* すると URL 末尾に含まれています）

### メンションについて

`TOGGL_REPORT_MENTIONS` に平文で `@name` と書いても、Slack API 経由の投稿では**ただの文字列として表示され、通知は飛びません**。実際にメンションさせるには `<@U01ABCDEFGH>` 形式のユーザー ID を指定してください。

投稿は [files.getUploadURLExternal → ファイル本体の POST → files.completeUploadExternal](https://docs.slack.dev/messaging/working-with-files/) の 3 ステップで行っています。

## Misoca 請求書作成（任意）

`MISOCA_INVOICE_ENDPOINT` と `MISOCA_INVOICE_BASIC_AUTH` の**両方**を設定すると、最後に請求書を作成するか確認されます。`y` で、表示した合計時間（小数第2位まで）を数量にした請求書が Misoca に作成されます。作成されるだけで、取引先への送付はされません。

Misoca API の OAuth トークンは 1 日で失効し、更新のたびに入れ替わるため、トークン管理は [notion-update-trigger](https://github.com/yumikokh/notion-update-trigger) の `/api/misoca/invoice` に任せています。取引先・単価・件名などの設定と初回の認可手順は notion-update-trigger の README を参照してください。同じ API を AI 秘書などからリモートで呼び出すこともできます。

- 発行日は対象月の末日、支払期限は翌月末
- 同じ月の請求書が作成済みの場合は、もう 1 件作るか確認されます（不要な方は Misoca 上で削除してください）

## 使い方

```bash
./toggl-report.sh
```

エイリアスを張っておくと便利です。

```bash
alias toggl-report='~/Code/toggl-report/toggl-report.sh'
```

実行すると対象月の選択を求められ、`<プレフィックス>-YYYY-MM.csv` が出力されます。

Slack 設定済みの場合は、続けて送信内容と宛先が表示され `y` を入力すると投稿されます。`y` 以外はすべて中止扱いです。

Misoca 設定済みの場合は、その後に請求書を作成するか確認されます（こちらも `y` 以外は中止）。

## ライセンス

MIT
