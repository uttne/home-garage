#!/bin/bash
set -e

# --- パス解決 (どこから実行しても動くようにする) ---
# このスクリプトがあるディレクトリ (bootstrap/) の絶対パスを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# リポジトリのルートディレクトリ (bootstrap/ の一つ上) を取得
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# ファイルパスの定義
BACKUP_DIR="$REPO_ROOT/.secrets"
BACKUP_KEY_FILE="$BACKUP_DIR/master-key-backup.yaml"
BACKUP_SCRIPT="$SCRIPT_DIR/backup-key.sh"
INITIALIZE_SCRIPT="$SCRIPT_DIR/initialize.sh"
ROOT_APP_MANIFEST="$SCRIPT_DIR/root-app.yaml"

# --------------------------------------------

echo "=== 1. Restoring Sealed Secrets Master Key (If exists) ==="
# 保存先ディレクトリがない場合は作成 (絶対パスで指定)
mkdir -p "$BACKUP_DIR"
# バックアップスクリプトに実行権限を付与
chmod +x "$BACKUP_SCRIPT"

# フラグ: 初期化を行ったかどうか
INITIALIZED=false

if [ -f "$BACKUP_KEY_FILE" ]; then
    echo "🔑 Found master key backup at $BACKUP_KEY_FILE! Restoring..."

    # 1. 先に Namespace を作成
    kubectl create namespace sealed-secrets --dry-run=client -o yaml | kubectl apply -f -

    # 2. マスターキーを Secret として復元
    kubectl apply -f "$BACKUP_KEY_FILE"

    echo "✅ Master key restored successfully."
else
    # Case B: 手元にファイルがない場合 -> クラスタを確認 (バックアップスクリプトに委譲)
    echo "⚠️  No local master key backup found."
    echo "🔎 Attempting to fetch key from the cluster..."

    # バックアップスクリプトを実行
    # if文で実行することで、exit code が 0 (成功) かそれ以外かを判定する
    if "$BACKUP_SCRIPT" "$BACKUP_KEY_FILE"; then

        # 成功した場合 (exit 0)
        echo "💡 Master key found in cluster and backed up!"
        echo "✅ Proceeding..."

    else
        # Case C: どっちにもない -> 完全新規インストール (Initialize実行)
        echo "❌ Master key not found locally AND not found in the cluster."
        echo "🆕 It seems like a FRESH install."
        echo "🚀 Calling initialization script..."
        echo ""

        # initialize.sh を実行 (サブルーチンとして呼び出し)
        chmod +x "$INITIALIZE_SCRIPT"
        "$INITIALIZE_SCRIPT"

        echo "✅ Initialization finished. Resuming setup..."
        INITIALIZED=true
    fi
fi

# ArgoCD をインストール
echo "=== 2. Installing ArgoCD via Helm ==="
# namespace が存在していてもエラーにならないように --dry-run を使う
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
# 初回インストール
helm upgrade --install argocd argo/argo-cd --namespace argocd --version 9.3.7

echo "=== 3. Waiting for ArgoCD Server to start... ==="
kubectl rollout status deployment argocd-server -n argocd --timeout=90s

echo "✅ ArgoCD Server is up and running."

echo "=== 4. Applying Root App (Bootstrap) ==="
# システム用のツールをデプロイ
kubectl apply -f "$ROOT_APP_MANIFEST"

echo "=== 5. Getting Initial Admin Password ==="
# 終わったらパスワードを表示（便利機能）
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo

echo ""
if [ "$INITIALIZED" = true ]; then
    echo "🎉 Fresh setup completed successfully!"
else
    echo "🎉 Restore setup completed successfully!"
fi
