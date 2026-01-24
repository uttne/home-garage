#!/bin/bash

# エラーが発生したら即座に停止
set -e

# ==========================================
# パス解決と変数定義
# ==========================================

# 1. このスクリプトが存在するディレクトリの絶対パスを取得
#    これにより、どこからコマンドを叩いても相対パスズレが起きなくなります
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 2. コピー元ディレクトリ (スクリプトと同じ場所にある systemd フォルダ)
SRC_DIR="${SCRIPT_DIR}/systemd"

# ファイル名定義
FILE_SCRIPT="avahi-publish-aliases.sh"
FILE_SERVICE="avahi-publish-aliases.service"
FILE_CONFIG="aliases"

# インストール先パス
DIR_BIN="/usr/local/bin"
DIR_CONF="/etc/avahi"
DIR_SYSTEMD="/etc/systemd/system"

# ==========================================
# 前提チェック
# ==========================================

# Root権限チェック
if [ "$(id -u)" -ne 0 ]; then
    echo "エラー: このスクリプトは root 権限(sudo)で実行してください。"
    exit 1
fi

# ソースディレクトリの存在確認
if [ ! -d "$SRC_DIR" ]; then
    echo "エラー: コピー元のディレクトリが見つかりません: $SRC_DIR"
    echo "スクリプトと同じ階層に 'systemd' フォルダがあるか確認してください。"
    exit 1
fi

echo "=== Avahi Alias セットアップを開始します ==="
echo "作業ディレクトリ: $SCRIPT_DIR"

# ==========================================
# メイン処理
# ==========================================

# 1. 依存パッケージの確認 (avahi-utils)
if ! command -v avahi-publish &> /dev/null; then
    echo "avahi-utils が見つかりません。インストールを試みます..."
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y avahi-utils
    elif command -v yum &> /dev/null; then
        yum install -y avahi-tools
    else
        echo "警告: パッケージマネージャが見つかりません。手動で avahi-utils を入れてください。"
    fi
fi

# 2. 実行スクリプトの配置 (強制上書き)
echo "-> [スクリプト] $DIR_BIN/$FILE_SCRIPT を配置します..."
cp -f "$SRC_DIR/$FILE_SCRIPT" "$DIR_BIN/$FILE_SCRIPT"
chmod +x "$DIR_BIN/$FILE_SCRIPT"

# 3. 設定ファイルの配置 (バックアップ＆上書き)
echo "-> [設定ファイル] $DIR_CONF/$FILE_CONFIG を確認中..."
if [ ! -d "$DIR_CONF" ]; then
    mkdir -p "$DIR_CONF"
fi

TARGET_CONF="$DIR_CONF/$FILE_CONFIG"

if [ -f "$TARGET_CONF" ]; then
    # 既存の設定がある場合はバックアップを作成
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_NAME="${TARGET_CONF}.bak_${TIMESTAMP}"
    echo "   既存の設定ファイルが見つかりました。バックアップを作成します: $BACKUP_NAME"
    cp "$TARGET_CONF" "$BACKUP_NAME"
    
    echo "   新しい設定ファイルで上書きします。"
    cp -f "$SRC_DIR/$FILE_CONFIG" "$TARGET_CONF"
else
    # 新規配置
    echo "   新規に配置します。"
    cp "$SRC_DIR/$FILE_CONFIG" "$TARGET_CONF"
    
    # 空の場合はサンプルを追記
    if [ ! -s "$TARGET_CONF" ]; then
        echo "# 以下に広報したいホスト名を1行ずつ記述してください" > "$TARGET_CONF"
        echo "# example.local" >> "$TARGET_CONF"
    fi
fi

# 4. Systemd サービスファイルの配置 (強制上書き)
echo "-> [サービス定義] $DIR_SYSTEMD/$FILE_SERVICE を配置します..."
cp -f "$SRC_DIR/$FILE_SERVICE" "$DIR_SYSTEMD/$FILE_SERVICE"

# 5. 反映と再起動
echo "-> 設定を反映してサービスを再起動しています..."
systemctl daemon-reload
systemctl enable "$FILE_SERVICE"
systemctl restart "$FILE_SERVICE"

echo "=== セットアップが完了しました ==="
echo "設定ファイル: $TARGET_CONF"
if [ -n "$BACKUP_NAME" ]; then
    echo "※ 注意: 設定ファイルを上書きしました。以前の設定は $BACKUP_NAME に保存されています。"
fi
echo "ステータス確認: sudo systemctl status $FILE_SERVICE"