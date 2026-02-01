#!/bin/bash
set -e

# パス解決
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if ! command -v kubeseal &>/dev/null; then
    echo "❌ Error: kubeseal command not found."
    exit 1
fi

# 対象ディレクトリを apps と system に固定
TARGET_DIRS=("$REPO_ROOT/system" "$REPO_ROOT/apps")

# 除外設定
IGNORE_DIRS=(
    ".git" "node_modules" "vendor" ".terraform"
    ".venv" "venv" "__pycache__"
    ".idea" ".vscode"
    "target" "build" "dist" "tmp"
    ".secrets"
)

echo "🔐 Re-sealing secrets in 'system' and 'apps'..."

count=0

for dir in "${TARGET_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then continue; fi

    # findコマンド構築
    FIND_CMD=(find "$dir")

    # 1. 除外リスト適用
    FIND_CMD+=(\()
    for i in "${!IGNORE_DIRS[@]}"; do
        if [ "$i" -gt 0 ]; then FIND_CMD+=(-o); fi
        FIND_CMD+=(-name "${IGNORE_DIRS[$i]}")
    done
    FIND_CMD+=(\) -prune -o)

    # 2. 検索条件の追加 (★ご指定のルール)
    FIND_CMD+=(-type f -name "*secret*.yaml")
    FIND_CMD+=(-not -name "*.template.yaml")
    FIND_CMD+=(-not -name "*.sealed.yaml")
    FIND_CMD+=(-print0)

    # 3. 実行
    while IFS= read -r -d '' input_file; do

        # 出力ファイル名を作成 (.yaml -> .sealed.yaml)
        # 参考スクリプト準拠: my-secret.yaml -> my-secret.sealed.yaml
        output_file="${input_file%.yaml}.sealed.yaml"

        # スキップ判定 (出力ファイルが存在し、かつ入力ファイルより新しい場合)
        if [ -f "$output_file" ] && [ "$input_file" -ot "$output_file" ]; then
            echo "⏭️  Skipping: ${input_file#"$REPO_ROOT"/} (No changes detected)"
            continue
        fi

        echo "🔒 Encrypting: ${input_file#"$REPO_ROOT"/} -> ${output_file#"$REPO_ROOT"/}"

        # kubeseal 実行
        kubeseal --controller-name=sealed-secrets-controller \
            --controller-namespace=sealed-secrets \
            --format=yaml <"$input_file" >"$output_file"

        ((count++)) || true

    done < <("${FIND_CMD[@]}")
done

echo "✅ Sealed process complete. (Total encrypted: $count)"
