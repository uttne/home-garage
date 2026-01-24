#!/bin/bash
set -e

# ==========================================
# 設定
# ==========================================
MANIFEST_DIR="manifests"
IGNORE_FILE=".helmignore"

# ==========================================
# 関数: .helmignore をパースして配列に格納
# ==========================================
IGNORES=()
EXCEPTIONS=()

if [ -f "$IGNORE_FILE" ]; then
    echo "📄 Reading ignore rules from $IGNORE_FILE..."
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメント行と空行をスキップ
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        # '!' で始まる場合は例外リスト（許可リスト）に追加
        if [[ "$line" == !* ]]; then
            EXCEPTIONS+=("${line:1}")
        else
            IGNORES+=("$line")
        fi
    done < "$IGNORE_FILE"
else
    echo "⚠️  $IGNORE_FILE not found. Processing all files."
fi

# ==========================================
# メイン処理: ファイルを選別
# ==========================================
FILES_TO_APPLY=()

echo "🔍 Scanning files in '$MANIFEST_DIR'..."

# manifestsフォルダ内の全YAMLファイルを検索
while IFS= read -r file; do
    filename=$(basename "$file")
    should_ignore=false

    # 1. 除外リスト(IGNORES)にマッチするか確認
    for pattern in "${IGNORES[@]}"; do
        # Bashのパターンマッチ機能を使用
        if [[ "$filename" == $pattern ]]; then
            should_ignore=true
            break
        fi
    done

    # 2. 除外判定された場合でも、例外リスト(EXCEPTIONS)にマッチすれば復活
    if $should_ignore; then
        for pattern in "${EXCEPTIONS[@]}"; do
            if [[ "$filename" == $pattern ]]; then
                should_ignore=false
                # echo "   ! Exception match: $filename matches $pattern"
                break
            fi
        done
    fi

    # 3. リストに追加
    if ! $should_ignore; then
        FILES_TO_APPLY+=("$file")
    else
        echo "   🚫 Ignoring: $file"
    fi

done < <(find "$MANIFEST_DIR" -type f -name "*.yaml" | sort)

# ==========================================
# kubectl apply 実行
# ==========================================
if [ ${#FILES_TO_APPLY[@]} -eq 0 ]; then
    echo "❌ No files to apply."
    exit 0
fi

echo "🚀 Applying the following files:"
# 適用するファイル一覧を表示
for f in "${FILES_TO_APPLY[@]}"; do
    echo "   - $f"
done

# コマンド構築: kubectl apply -f file1 -f file2 ... の形にする
CMD=(kubectl apply)
for f in "${FILES_TO_APPLY[@]}"; do
    CMD+=(-f "$f")
done

echo "---------------------------------------------------"
# 実際の実行
"${CMD[@]}"