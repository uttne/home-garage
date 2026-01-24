#!/bin/bash

# エラーが発生したら即座に停止
set -e

# ==========================================
# 1. パス解決
# ==========================================
# このスクリプト(setup/install.sh)があるディレクトリの絶対パス
MASTER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# ==========================================
# 2. インストール対象のモジュール定義
# ==========================================
# 今後フォルダが増えた場合は、ここに追記するだけで実行されます
MODULES=(
    "avahi-publish-aliases"
    # "another-module"
)

# ==========================================
# 3. 前提チェック
# ==========================================
if [ "$(id -u)" -ne 0 ]; then
    echo "エラー: このスクリプトは root 権限(sudo)で実行してください。"
    exit 1
fi

echo "=== マスターセットアップを開始します ==="
echo "Base Directory: $MASTER_DIR"
echo ""

# ==========================================
# 4. モジュールの実行ループ
# ==========================================
for module in "${MODULES[@]}"; do
    INSTALLER_PATH="${MASTER_DIR}/${module}/install.sh"
    
    echo "--------------------------------------------------"
    echo "Processing Module: ${module}"
    echo "--------------------------------------------------"

    if [ -f "$INSTALLER_PATH" ]; then
        # 実行権限を念のため付与
        chmod +x "$INSTALLER_PATH"
        
        # 子スクリプトを実行
        # 子スクリプト側でパス解決しているため、単純呼び出しでOK
        "$INSTALLER_PATH"
        
        echo "-> [OK] ${module} のセットアップ完了"
    else
        echo "警告: インストーラーが見つかりません: $INSTALLER_PATH"
        echo "スキップします。"
    fi
    echo ""
done