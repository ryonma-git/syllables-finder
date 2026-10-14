#!/bin/bash
# Red Vowel Maker ダブルクリック起動用ランチャー
#
# このファイルを Finder でダブルクリックするとアプリが起動します。
#
# 仕組み:
#   プロジェクト内の仮想環境 .venv（Homebrew Python 3 ＝ 新しい Tk 9.0 ベース）を使います。
#   - Apple 標準の /usr/bin/python3 は Tk 8.5 が古く、ダークモードで入力欄が
#     見えなくなる不具合があるため使いません。
#   - .venv が無ければ自動で作成し、python-docx（Word 出力）と reportlab（PDF 出力）も
#     入れてから起動します。

cd "$(dirname "$0")" || exit 1

# .venv が無ければ作る（Homebrew Python から）
if [ ! -x ".venv/bin/python" ]; then
    echo "初回セットアップ: 仮想環境を作成します..."
    if [ -x /opt/homebrew/bin/python3 ]; then
        BASE_PY=/opt/homebrew/bin/python3
    elif [ -x /usr/local/bin/python3 ]; then
        BASE_PY=/usr/local/bin/python3   # Intel Mac の Homebrew
    else
        BASE_PY=python3
    fi
    "$BASE_PY" -m venv .venv || { echo "venv 作成に失敗しました"; exit 1; }
    .venv/bin/python -m pip install --quiet --upgrade pip python-docx reportlab
fi

# python-docx が無ければ入れる（保険）
if ! .venv/bin/python -c "import docx" >/dev/null 2>&1; then
    .venv/bin/python -m pip install --quiet python-docx
fi

# reportlab（PDF 出力）が無ければ入れる（保険）
if ! .venv/bin/python -c "import reportlab" >/dev/null 2>&1; then
    .venv/bin/python -m pip install --quiet reportlab
fi

.venv/bin/python app.py
