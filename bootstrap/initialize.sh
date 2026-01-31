#!/bin/bash
set -e

# --- パス解決 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# ファイルパス定義
BACKUP_DIR="$REPO_ROOT/.secrets"
BACKUP_KEY_FILE="$BACKUP_DIR/master-key-backup.yaml"
BACKUP_SCRIPT="$SCRIPT_DIR/backup-key.sh"
SEALED_SECRETS_APP_MANIFEST="$REPO_ROOT/system/sealed-sct.yaml"

# ヘルパースクリプト定義
SCRIPT_CLEAN="$REPO_ROOT/scripts/clean-sealed.sh"
SCRIPT_SEAL="$REPO_ROOT/scripts/seal-all.sh"

# --------------------------------------------

echo "🚀 Starting Fresh Initialization (Greenfield Setup)..."

# ==========================================
# 1. 安全確認 (Safety Checks)
# ==========================================

# Check A: ローカルにバックアップファイルがあるか
if [ -f "$BACKUP_KEY_FILE" ]; then
    echo "⚠️  WARNING: A master key backup already exists at:"
    echo "   $BACKUP_KEY_FILE"
    echo "   If you want to restore this environment, please use './bootstrap/setup.sh'."
    echo "   If you truly want to start fresh, delete this backup file first."
    exit 1
fi

# Check B: クラスタ内にすでに鍵があるか (★ここを追加)
echo "🔎 Checking cluster for existing Sealed Secrets keys..."
if kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key >/dev/null 2>&1; then
    echo "⚠️  WARNING: A master key ALREADY EXISTS in the cluster!"
    echo "   Initializing now would overwrite/ignore the existing key, making current secrets undecryptable."
    echo "   If you want to recover using the cluster's key, use './bootstrap/setup.sh'."
    echo "   If you really want to reset, please delete the 'sealed-secrets' namespace manually first."
    exit 1
fi

# ==========================================
# 2. ArgoCD のインストール
# ==========================================
echo "=== 1. Installing ArgoCD via Helm ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
# 最新版のインストール
helm upgrade --install argocd argo/argo-cd --namespace argocd --version 9.3.7

echo "=== 2. Waiting for ArgoCD Server... ==="
kubectl rollout status deployment argocd-server -n argocd --timeout=90s

# ==========================================
# 3. Sealed Secrets のみを先行デプロイ
# ==========================================
echo "=== 3. Deploying Sealed Secrets (Standalone) ==="
# Root App ではなく、Sealed Secrets アプリ単体を適用する
kubectl apply -f "$SEALED_SECRETS_APP_MANIFEST"

echo "⏳ Sealed Secrets App applied. Waiting for Controller..."

# Controller の起動待ち
MAX_RETRIES=30
SLEEP_SEC=5
echo "   (Waiting for namespace 'sealed-secrets' and deployment 'sealed-secrets-controller'...)"

for ((i = 1; i <= MAX_RETRIES; i++)); do
    # Namespace と Deployment が存在し、かつ Available か確認
    if kubectl get deployment -n sealed-secrets sealed-secrets-controller >/dev/null 2>&1; then
        if kubectl rollout status deployment/sealed-secrets-controller -n sealed-secrets --timeout=60s >/dev/null 2>&1; then
            echo "✅ Sealed Secrets Controller is Ready!"
            break
        fi
    fi

    if [ $i -eq $MAX_RETRIES ]; then
        echo "❌ Timeout waiting for Sealed Secrets Controller."
        exit 1
    fi
    echo -n "."
    sleep $SLEEP_SEC
done
echo ""

# ==========================================
# 4. バックアップとシークレット再生成
# ==========================================
echo "=== 4. Backing up the NEWLY GENERATED Master Key ==="
mkdir -p "$BACKUP_DIR"
chmod +x "$BACKUP_SCRIPT"

if "$BACKUP_SCRIPT" "$BACKUP_KEY_FILE"; then
    echo "🎉 New master key backed up to: $BACKUP_KEY_FILE"
else
    echo "❌ Failed to backup the new key."
    exit 1
fi

# ==========================================================
# 6. 既存シークレットの削除と再生成
# ==========================================================
echo ""
echo "=== 5. Refreshing Sealed Secrets ==="
echo "   Since the master key is new, refreshing secrets in 'system' and 'apps'..."

# 6-1. 削除 (引数不要: スクリプト内で system/apps を指定済み)
echo "🧹 Step A: Removing old sealed secrets..."
"$SCRIPT_CLEAN"

# 6-2. 再生成 (引数不要)
echo "🔐 Step B: Generating new sealed secrets..."
"$SCRIPT_SEAL"

echo "✅ Secrets refreshed."
echo "🎉 Initialization phase complete. Returning to setup..."
