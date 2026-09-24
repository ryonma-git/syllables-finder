# -*- coding: utf-8 -*-
"""
docx_writer.py

mark_line() の判定結果をもとに、母音核だけ赤字にした .docx を書き出す。

- 各行を1段落として追加（空行も保持）
- 1段落の中に黒字 run と赤字 run を混在させる
- 赤字 = RGBColor(255, 0, 0) / 黒字 = RGBColor(0, 0, 0)
- フォント・サイズは指定可能（デフォルト Arial / 24pt）
- 行間は読みやすさのため 1.3、段落後に少し余白
"""

from docx import Document
from docx.shared import Pt, RGBColor

from vowel_marker import mark_line

RED = RGBColor(0xFF, 0x00, 0x00)
BLACK = RGBColor(0x00, 0x00, 0x00)


def _apply_run_font(run, font_name: str, size_pt: float, red: bool):
    run.font.name = font_name           # 欧文(ascii/hAnsi)に適用。日本語はWord既定フォントで表示される
    run.font.size = Pt(size_pt)
    run.font.color.rgb = RED if red else BLACK


def write_docx(text: str,
               filepath: str,
               font_name: str = "Arial",
               font_size: float = 24,
               use_exceptions: bool = True,
               silent_e: bool = True,
               y_as_vowel: bool = True):
    """text を処理して filepath に .docx を保存する。"""
    doc = Document()

    # 既定スタイル（Normal）にもフォントを設定しておく（空行・日本語のフォールバック用）
    normal = doc.styles["Normal"]
    normal.font.name = font_name
    normal.font.size = Pt(font_size)

    opts = dict(
        use_exceptions=use_exceptions,
        silent_e=silent_e,
        y_as_vowel=y_as_vowel,
    )

    for line in text.split("\n"):
        paragraph = doc.add_paragraph()
        pf = paragraph.paragraph_format
        pf.line_spacing = 1.3           # 教材として読みやすい行間
        pf.space_after = Pt(6)          # 段落間を詰めすぎない

        for fragment, red in mark_line(line, **opts):
            run = paragraph.add_run(fragment)
            _apply_run_font(run, font_name, font_size, red)

    doc.save(filepath)
    return filepath
