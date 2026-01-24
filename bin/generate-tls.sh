#!/bin/bash

# エラーが発生したら即停止
set -e

# ==========================================
# 設定
# ==========================================
# 第1引数があればそれをドメイン名として使い、なければデフォルトを使う
DOMAIN="${1:-my-home-n8n.local}"

# 出力先設定
NAMESPACE="n8n"
SECRET_NAME="n8n-tls-secret"
OUTPUT_DIR="manifests/n8n"

# ファイル名設定
TEMP_DIR=".tmp"
KEY_FILE="${TEMP_DIR}/tls.key"
CERT_FILE="${TEMP_DIR}/tls.crt"
TEMPLATE_FILE="${OUTPUT_DIR}/tls-secret.yaml"

# 最終成果物
SEALED_FILE="${OUTPUT_DIR}/tls-secret.sealed.yaml"

# ==========================================
# 0. 事前チェック (追加機能)
# ==========================================
# 最終成果物が既に存在すれば、何もせずに終了する
if [ -f "$SEALED_FILE" ]; then
    echo "⏭️  Sealed secret already exists: $SEALED_FILE"
    echo "   Skipping generation to prevent overwriting."
    echo "   (If you want to regenerate, please delete this file manually.)"
    exit 0
fi

# ==========================================
# 1. コマンド存在確認
# ==========================================
if ! command -v openssl &> /dev/null; then
    echo "❌ Error: openssl command not found."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl command not found."
    exit 1
fi

if ! command -v kubeseal &> /dev/null; then
    echo "❌ Error: kubeseal command not found."
    exit 1
fi

# 出力ディレクトリの作成
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEMP_DIR"

echo "🔐 Generating Self-Signed Certificate for: $DOMAIN"

# ==========================================
# 2. 証明書と秘密鍵の作成 (OpenSSL)
# ==========================================
# -nodes: パスフレーズなし (自動起動するため)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" \
  -subj "/CN=${DOMAIN}/O=MyLocalK3s/C=JP" \
  2>/dev/null

echo "✅ Created $KEY_FILE and $CERT_FILE"

# ==========================================
# 3. Kubernetes Secret テンプレートの生成
# ==========================================
echo "📄 Generating Kubernetes Secret Template..."

kubectl create secret tls "$SECRET_NAME" \
  --cert="$CERT_FILE" \
  --key="$KEY_FILE" \
  --namespace "$NAMESPACE" \
  --dry-run=client -o yaml > "$TEMPLATE_FILE"

echo "✅ Created $TEMPLATE_FILE"

# ==========================================
# 4. SealedSecret への暗号化
# ==========================================
echo "🔒 Sealing the secret..."

kubeseal --format=yaml < "$TEMPLATE_FILE" > "$SEALED_FILE"

echo "✅ Created $SEALED_FILE"

# ==========================================
# 5. クリーンアップ (重要: 生の鍵を削除)
# ==========================================
echo "🧹 Cleaning up raw keys and templates..."

# rm "$KEY_FILE" "$CERT_FILE" "$TEMPLATE_FILE"

echo "=========================================="
echo "🎉 Done!"
echo "   Generated: $SEALED_FILE"
echo "   Raw keys and templates have been deleted for security."
echo "=========================================="