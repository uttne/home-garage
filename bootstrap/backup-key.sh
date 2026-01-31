#!/bin/bash
# bootstrap/backup-key.sh
set -e

OUTPUT_FILE="$1"

# 引数チェック
if [ -z "$OUTPUT_FILE" ]; then
    echo "Error: Output file path is required."
    echo "Usage: $0 <output-file-path>"
    exit 1
fi

# クラスタ内に Sealed Secrets のキーがあるか確認
# 存在確認だけなので標準出力は捨てる
if kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key >/dev/null 2>&1; then

    # 鍵が見つかった場合: 出力先に書き出す
    kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml >"$OUTPUT_FILE"
    echo "Successfully backed up the master key to $OUTPUT_FILE"
    exit 0

else
    # 鍵が見つからない場合: エラー終了
    echo "Error: Sealed Secrets master key not found in the cluster."
    exit 1
fi
