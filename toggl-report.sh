#!/bin/bash
set -euo pipefail

# ============================================
# Toggl 月次レポート出力スクリプト
#
# 設定は同ディレクトリの .env から読み込みます。
# 初回は .env.example をコピーして値を埋めてください。
#   cp .env.example .env
# ============================================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${TOGGL_REPORT_ENV:-${script_dir}/.env}"

if [[ -f "$env_file" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$env_file"; set +a
fi

# 必須設定のチェック
missing=()
for var in TOGGL_API_TOKEN TOGGL_WORKSPACE_ID TOGGL_PROJECT_ID; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "エラー: 次の設定が未設定です: ${missing[*]}" >&2
  echo "  ${env_file} を作成して値を設定してください（.env.example を参照）。" >&2
  exit 1
fi

# 任意設定
output_prefix="${TOGGL_OUTPUT_PREFIX:-toggl-report}"
output_dir="${TOGGL_OUTPUT_DIR:-$HOME}"
mentions="${TOGGL_REPORT_MENTIONS:-}"

# ============================================
# Slack 連携ヘルパー
# ============================================

# stdin の Slack API レスポンスを検証し、ok なら JSON をそのまま出力する
slack_check() {
  python3 -c "
import sys, json
label = sys.argv[1]
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(f'{label}: レスポンスを解析できませんでした: {raw[:200]}', file=sys.stderr)
    sys.exit(1)
if not d.get('ok'):
    print(f\"{label}: {d.get('error', 'unknown error')}\", file=sys.stderr)
    sys.exit(1)
print(json.dumps(d))
" "$1"
}

# $1: 添付するファイルパス / $2: 本文
# https://docs.slack.dev/messaging/working-with-files/ の3ステップ手順
slack_send() {
  local file="$1" comment="$2"
  local filename length resp upload_url file_id http_code files_json

  filename="$(basename "$file")"
  length="$(wc -c < "$file" | tr -d ' ')"

  # 1. アップロード用の URL と file_id を取得
  resp="$(curl -sS -X POST "https://slack.com/api/files.getUploadURLExternal" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -F "filename=${filename}" \
    -F "length=${length}")" || return 1
  resp="$(printf '%s' "$resp" | slack_check 'アップロードURLの取得に失敗')" || return 1

  upload_url="$(printf '%s' "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['upload_url'])")"
  file_id="$(printf '%s' "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['file_id'])")"

  # 2. ファイル本体を POST
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$upload_url" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${file}")" || return 1
  if [[ "$http_code" -ne 200 ]]; then
    echo "ファイル本体のアップロードに失敗しました (HTTP ${http_code})" >&2
    return 1
  fi

  # 3. アップロードを確定し、本文付きでチャンネルに投稿
  files_json="$(FILE_ID="$file_id" TITLE="$filename" python3 -c "
import json, os
print(json.dumps([{'id': os.environ['FILE_ID'], 'title': os.environ['TITLE']}]))
")"

  resp="$(curl -sS -X POST "https://slack.com/api/files.completeUploadExternal" \
    -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
    -F "files=${files_json}" \
    -F "channel_id=${SLACK_CHANNEL_ID}" \
    -F "initial_comment=${comment}")" || return 1
  printf '%s' "$resp" | slack_check 'Slack への投稿に失敗' >/dev/null || return 1
}

# ============================================

# Base64エンコードした認証トークン
AUTH=$(printf '%s:api_token' "$TOGGL_API_TOKEN" | base64)

# 今月・先月の選択肢
this_month=$(date +%Y-%m)
last_month=$(date -v-1m +%Y-%m)

echo "対象月を選択してください:"
select choice in "$this_month" "$last_month"; do
  if [[ -n "$choice" ]]; then
    selected="$choice"
    break
  fi
  echo "正しい番号を入力してください。"
done

# 開始日・終了日を算出
start_date="${selected}-01"
year=${selected%%-*}
month=${selected##*-}
end_date=$(date -j -v+1m -v-1d -f "%Y-%m-%d" "${year}-${month}-01" "+%Y-%m-%d")

output_file="${output_dir}/${output_prefix}-${selected}.csv"

echo "取得中: ${start_date} 〜 ${end_date} ..."

http_code=$(curl -s -o "$output_file" -w "%{http_code}" \
  -X POST \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  -d "{\"start_date\":\"${start_date}\",\"end_date\":\"${end_date}\",\"project_ids\":[${TOGGL_PROJECT_ID}],\"billable\":true}" \
  "https://api.track.toggl.com/reports/api/v3/workspace/${TOGGL_WORKSPACE_ID}/search/time_entries.csv")

if [[ "$http_code" -ne 200 ]]; then
  echo "エラー: API リクエストが失敗しました (HTTP ${http_code})" >&2
  cat "$output_file" >&2
  rm -f "$output_file"
  exit 1
fi

# Currency/Amount/Billable列を除外し、Durationを5分丸めにし、合計行を追加
# （billable=false のエントリは API リクエスト時点で除外済み）
# 合計時間を標準出力に返す
total_duration=$(OUTPUT_FILE="$output_file" python3 -c "
import csv, math, os

path = os.environ['OUTPUT_FILE']

with open(path, encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    rows = list(reader)
    fieldnames = reader.fieldnames

exclude = {'Currency', 'Amount', 'Billable'}
headers = [h for h in fieldnames if h not in exclude]

total_seconds = 0
rounded_rows = []
for row in rows:
    parts = row['Duration'].split(':')
    secs = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    rounded_min = math.ceil(secs / 300) * 5
    total_seconds += rounded_min * 60
    h, m = divmod(rounded_min, 60)
    row['Duration'] = f'{h:02d}:{m:02d}:00'
    rounded_rows.append(row)

th, rem = divmod(total_seconds, 3600)
tm = rem // 60
total_dur = f'{th:02d}:{tm:02d}:00'
total_decimal = round(total_seconds / 3600, 2)
total_row = {h: '' for h in headers}
total_row['Description'] = '合計'
total_row['Duration'] = total_dur

with open(path, 'w', newline='', encoding='utf-8-sig') as f:
    writer = csv.DictWriter(f, fieldnames=headers, extrasaction='ignore')
    writer.writeheader()
    writer.writerows(rounded_rows)
    writer.writerow(total_row)

print(f'{total_dur},{total_decimal}')
") || { echo "CSV加工に失敗しました" >&2; exit 1; }

# Pythonが「HH:MM:SS,十進数」で返すのでカンマで分割
total_decimal="${total_duration##*,}"
total_duration="${total_duration%%,*}"

# 月を数値で取得（先頭0除去）
display_month="${month#0}"

# 報告メッセージを組み立て
message="${display_month}月の稼働時間です！
${total_duration}でした。ご確認よろしくお願いいたします"

if [[ -n "$mentions" ]]; then
  message="${mentions}
${message}"
fi

printf '%s' "$message" | pbcopy

echo "保存しました: ${output_file}"
echo "合計: ${total_duration} (${total_decimal}時間)"
echo "クリップボードにメッセージをコピーしました"

# Slack へ送信（SLACK_BOT_TOKEN と SLACK_CHANNEL_ID が両方設定されている場合のみ）
if [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_CHANNEL_ID:-}" ]]; then
  echo
  echo "─────────── Slack 送信内容 ───────────"
  echo "宛先チャンネル: ${SLACK_CHANNEL_ID}"
  echo "添付ファイル  : $(basename "$output_file")"
  echo "───"
  echo "$message"
  echo "──────────────────────────────────────"
  printf '%s' "この内容で Slack に送信しますか? [y/N]: "
  read -r reply || reply=""
  if [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]; then
    if slack_send "$output_file" "$message"; then
      echo "Slack に送信しました。"
    else
      echo "Slack への送信に失敗しました。CSV は ${output_file} に残っています。" >&2
      exit 1
    fi
  else
    echo "送信を中止しました。"
  fi
fi

open -R "$output_file"
