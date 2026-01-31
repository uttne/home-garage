#!/bin/bash
set -e

# ArgoCD をインストール
echo "=== 1. Installing ArgoCD via Helm ==="
# namespace が存在していてもエラーにならないように --dry-run を使う
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
# 初回インストール
helm upgrade --install argocd argo/argo-cd --namespace argocd --version 9.3.7

echo "=== 2. Waiting for ArgoCD Server to start... ==="
kubectl rollout status deployment argocd-server -n argocd --timeout=90s

echo "=== 3. Applying Root App (Bootstrap) ==="
# システム用のツールをデプロイ
kubectl apply -f bootstrap/root-app.yaml

echo "=== 4. Getting Initial Admin Password ==="
# 終わったらパスワードを表示（便利機能）
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

echo "" # 改行
echo "=== Done! ==="