#!/bin/bash

# 設定ファイルのパス
CONFIG_FILE="/etc/avahi/aliases"

# 1. IPアドレスの取得 (192.で始まるIPを取得)
TARGET_IP=$(hostname -I | xargs -n1 | grep '^192\.' | head -n1)

# IPが見つからない場合のエラー処理
if [ -z "$TARGET_IP" ]; then
    echo "Error: No matching IP address found (starting with 192.)."
    exit 1
fi

echo "Target IP: $TARGET_IP"

# 2. 終了時の処理 (trap)
cleanup() {
    echo "Stopping all avahi-publish processes..."
    # ジョブがある場合のみ kill を実行してエラーメッセージを抑制
    JOBS=$(jobs -p)
    if [ -n "$JOBS" ]; then
        kill $JOBS
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# 3. 設定ファイルを読み込んでループ処理
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file $CONFIG_FILE not found."
    exit 1
fi

# コメント行(#)と空行を除外して読み込む
while read -r ALIAS_NAME; do
    echo "Publishing: $ALIAS_NAME"
    /usr/bin/avahi-publish -v -a -R "$ALIAS_NAME" "$TARGET_IP" &
done < <(grep -vE '^\s*($|#)' "$CONFIG_FILE")

# 4. 待機
echo "All aliases published. Waiting..."
wait