#!/bin/bash

# エラー発生時に即停止
set -e

# kubeseal コマンドの存在確認
if ! command -v kubeseal &> /dev/null; then
    echo "❌ Error: kubeseal command not found."
    exit 1
fi

# -----------------------------------------------------------
# 📁 対象ディレクトリの設定
# 引数($1)があればそれを使い、なければカレントディレクトリ(.)を使う
# -----------------------------------------------------------
TARGET_DIR="${1:-.}"

if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

# ==========================================
# 🚫 除外したいフォルダのリスト (設定エリア)
# ==========================================
IGNORE_DIRS=(
    ".git"          # Git管理ディレクトリ
    "node_modules"  # Node.js パッケージ
    "vendor"        # Go / PHP / Ruby などのライブラリ
    ".terraform"    # Terraform キャッシュ
    ".venv"         # Python 仮想環境
    "venv"          # Python 仮想環境
    "__pycache__"   # Python キャッシュ
    ".idea"         # IntelliJ / WebStorm 設定
    ".vscode"       # VS Code 設定
    "target"        # Java / Rust ビルド成果物
    "build"         # 一般的なビルド成果物
    "dist"          # 一般的なビルド成果物
    "tmp"           # 一時フォルダ
)

echo "🔍 Scanning recursively for secret files..."
echo "   (Ignoring: ${IGNORE_DIRS[*]})"

# findコマンドの除外引数を動的に構築する
# 結果として: \( -name ".git" -o -name "node_modules" ... \) -prune -o という形を作る
FIND_CMD=(find "$TARGET_DIR")

# 1. 除外リストの構築開始
FIND_CMD+=( \( )
for i in "${!IGNORE_DIRS[@]}"; do
    # 2つ目以降の要素の前には -o (OR) をつける
    if [ $i -gt 0 ]; then
        FIND_CMD+=(-o)
    fi
    FIND_CMD+=(-name "${IGNORE_DIRS[$i]}")
done
FIND_CMD+=( \) -prune -o )

# 2. 検索条件の追加
# -type f : ファイルのみ
# -name "*secret*.yaml" : 対象ファイル名
# -not -name ... : 除外ファイル名
FIND_CMD+=( -type f -name "*secret*.yaml" )
FIND_CMD+=( -not -name "*.template.yaml" )
FIND_CMD+=( -not -name "*.sealed.yaml" )
FIND_CMD+=( -print0 )

# 3. コマンドを実行して処理
"${FIND_CMD[@]}" | while IFS= read -r -d '' input_file; do

    # 出力ファイル名を作成 (.yaml -> .sealed.yaml)
    output_file="${input_file%.yaml}.sealed.yaml"

    # 1. 出力ファイルが既に存在し、かつ
    # 2. 入力ファイル(template)が出力ファイル(sealed)よりも「古ければ」(= 変更がなければ)
    # スキップする
    if [ -f "$output_file" ] && [ "$input_file" -ot "$output_file" ]; then
        echo "⏭️  Skipping: $input_file (No changes detected)"
        continue
    fi

    echo "🔒 Encrypting: $input_file -> $output_file"

    # kubeseal 実行
    kubeseal --format=yaml < "$input_file" > "$output_file"

done

echo "✅ Done!"