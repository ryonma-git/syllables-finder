# -*- coding: utf-8 -*-
"""
sheet_design.py

Word（docx_writer.py）と PDF（pdf_writer.py）で共通に使う、プリントのデザイン定義。
両方の見た目をそろえるため、用紙・余白・色・文言はここでまとめて管理する。

レイアウト（A4 縦・各ページ共通）:
    ┌──────────────────────────────────────────┐
    │ ♪ RED VOWEL READING                    ♫ │ ← 紺の帯（ヘッダー）
    │ 曲のタイトル                               │
    └══════════════════════════════════════════┘ ← 黄色のアクセント線
      ● 赤い文字に声をのせて読もう  例 make     なまえ
                                               ______________
    ┃ 本文（1行＝1段落。連ごとに左へ淡い縦線）
    ┃ ...
    ─────────────────────────────────────────────
      Red Vowel Maker                          1 / 2   ← フッター

装飾には赤系の色を使わない（赤＝「声をのせる母音」という意味を保つため）。
本文の文字色は従来どおり 赤 FF0000 / 黒 000000。
"""

# ---------------------------------------------------------------- 用紙・余白（mm）
PAGE_WIDTH_MM = 210.0          # A4
PAGE_HEIGHT_MM = 297.0
MARGIN_LEFT_MM = 18.0
MARGIN_RIGHT_MM = 18.0
MARGIN_TOP_MM = 45.0           # ヘッダー（帯＋凡例）を含む本文開始位置
MARGIN_BOTTOM_MM = 22.0
HEADER_DISTANCE_MM = 10.0      # 用紙上端 → 帯の上端
FOOTER_DISTANCE_MM = 10.0      # 用紙下端 → フッター文字の下端

TEXT_WIDTH_MM = PAGE_WIDTH_MM - MARGIN_LEFT_MM - MARGIN_RIGHT_MM

# ヘッダー各部の高さ（mm）
BAND_HEIGHT_MM = 19.0          # 紺の帯
BAND_PAD_X_MM = 6.0            # 帯の左右の内側余白
INFO_HEIGHT_MM = 10.0          # 帯の下の凡例・なまえ欄の行
NAME_FIELD_WIDTH_MM = 68.0     # なまえ欄（右寄せ）の幅
NOTES_WIDTH_MM = 24.0          # 帯の右端の音符飾りの幅（なまえ欄の幅に含まれる）
ACCENT_WIDTH_PT = 3.0          # 帯の下の黄色い線の太さ

# ---------------------------------------------------------------- 色（16進 RGB）
NAVY = "1E3A5F"                # 帯・見出し
SKY = "A9CBEB"                 # 帯の中の小見出し
NOTES = "3E6290"               # 帯の右端の音符飾り（帯より少し明るい紺）
ACCENT = "F2C14E"              # 帯の下のアクセント線（黄色）
STANZA_BAR = "C9DCF0"          # 連ごとの左の縦線
RULE = "C3CDD9"                # フッターの区切り線
MUTED = "6B7A8F"               # 補足の文字・なまえ欄の記入線
WHITE = "FFFFFF"
RED = "FF0000"                 # 母音核（本文）
BLACK = "000000"               # 本文

# ---------------------------------------------------------------- フォント
UI_LATIN_FONT = "Arial"        # ヘッダー・フッターの欧文
JAPANESE_FONT = "游ゴシック"   # 日本語（Word 既定の明朝ではなくゴシックで統一）

BRAND_SIZE_PT = 8.0
BRAND_CHAR_SPACING_PT = 1.6
TITLE_SIZE_PT = 20.0
NOTES_SIZE_PT = 30.0
INFO_SIZE_PT = 10.5
LEGEND_DOT_SIZE_PT = 8.0
FOOTER_SIZE_PT = 8.0

# ---------------------------------------------------------------- 本文
LINE_SPACING = 1.3             # 行間（倍数）
SPACE_AFTER_PT = 6.0           # 段落の後の余白
BODY_INDENT_MM = 5.0           # 本文の左インデント（縦線の分）
STANZA_BAR_WIDTH_PT = 2.25     # 縦線の太さ
STANZA_BAR_GAP_PT = 9.0        # 縦線と本文のすき間

# ---------------------------------------------------------------- 文言
BRAND_TEXT = "RED VOWEL READING"
BRAND_MARK = "♪"
NOTES_MARK = "♫"
DEFAULT_TITLE = "Let's Read & Sing!"
LEGEND_TEXT = "赤い文字に声をのせて読もう"
LEGEND_EXAMPLE_LABEL = "例"
LEGEND_EXAMPLE = [("m", False), ("a", True), ("ke", False)]   # make
NAME_LABEL = "なまえ"
FOOTER_TEXT = "Red Vowel Maker"


def display_title(title) -> str:
    """ヘッダーに出すタイトル。空なら既定の見出しを使う。改行は空白にまとめる。"""
    title = " ".join((title or "").split())
    return title or DEFAULT_TITLE


def title_size_pt(title: str) -> float:
    """長いタイトルほど小さくして、帯の1行に収まりやすくする（Word/PDF 共通）。"""
    n = len(title)
    if n <= 32:
        return TITLE_SIZE_PT
    if n <= 44:
        return 16.0
    return 13.0


def mm_to_pt(mm: float) -> float:
    return mm * 72.0 / 25.4
