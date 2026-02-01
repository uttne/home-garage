#!/bin/bash
set -e

# パス解決
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

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

echo "🧹 Cleaning up existing Sealed Secrets (*.sealed.yaml) in 'system' and 'apps'..."

deleted_count=0

for dir in "${TARGET_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then continue; fi

    # findコマンド構築
    FIND_CMD=(find "$dir")

    # 除外リスト
    FIND_CMD+=(\()
    for i in "${!IGNORE_DIRS[@]}"; do
        if [ "$i" -gt 0 ]; then FIND_CMD+=(-o); fi
        FIND_CMD+=(-name "${IGNORE_DIRS[$i]}")
    done
    FIND_CMD+=(\) -prune -o)

    # 検索条件 (削除対象)
    FIND_CMD+=(-type f -name "*.sealed.yaml")
    FIND_CMD+=(-print0)

    # 実行
    while IFS= read -r -d '' file; do
        rm "$file"
        echo "   🗑️  Deleted: ${file#"$REPO_ROOT"/}"
        ((deleted_count++)) || true
    done < <("${FIND_CMD[@]}")
done

if [ "$deleted_count" -eq 0 ]; then
    echo "   (No sealed secrets found to delete.)"
fi

echo "✅ Cleanup complete. (Total deleted: $deleted_count)"
