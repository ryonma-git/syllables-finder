# -*- coding: utf-8 -*-
"""
pdf_writer.py

docx_writer.py と同じデザイン（sheet_design.py）で、母音核だけ赤字にした PDF を書き出す。
reportlab で直接描くので、Word や LibreOffice が無くても作成できる。

- 各行を1段落として扱う（空行も保持）。長い行は用紙の幅で折り返す
- 赤字 = FF0000 / 黒字 = 000000。フォント名・サイズは Word 出力と同じ指定を使う
- A4 縦。各ページに紺の帯（タイトル）、凡例・なまえ欄、連ごとの縦線、「n / 総ページ数」

フォント:
- 欧文は、指定フォント名（既定 Arial）の TrueType ファイルを macOS のフォントフォルダ
  から探して埋め込む。見つからないときは Arial で代用する（font_substitute() で確認可）
- 日本語は Word 出力と同じ游ゴシック（Microsoft Word 付属）→ Arial Unicode MS の順に探す。
  ヒラギノは reportlab が扱えない形式（PostScript アウトライン）のため使わない
- 1文字ずつ、欧文フォントに字形が無い文字（日本語・記号）は日本語フォントで描く
"""

import os
import unicodedata

from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

import sheet_design as D
from vowel_marker import mark_line

WORD_FONT_DIR = "/Applications/Microsoft Word.app/Contents/Resources/DFonts"
FONT_DIRS = (
    os.path.expanduser("~/Library/Fonts"),
    "/Library/Fonts",
    "/System/Library/Fonts/Supplemental",
    "/System/Library/Fonts",
    WORD_FONT_DIR,
)
# (標準, 太字) の組。上から順に、存在して読めるものを使う
JAPANESE_FONT_FILES = (
    (os.path.join(WORD_FONT_DIR, "YuGothR.ttc"), os.path.join(WORD_FONT_DIR, "YuGothB.ttc")),
    ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", None),
    ("/Library/Fonts/Arial Unicode.ttf", None),
)
CID_FALLBACK = "HeiseiKakuGo-W5"   # どれも無いときの最終手段（埋め込みなし）

# 行頭に来ないよう前の文字にくっつける記号（簡易の禁則）
_NO_LINE_START = set("、。，．・：；？！ー）］｝〕〉》」』】ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ")

_registered = {}        # (path, index) -> reportlab のフォント名（読めなければ None）
_font_file_cache = {}   # (正規化したフォント名, bold) -> path


def _mm(value):
    return D.mm_to_pt(value)


def _color(hex_color):
    return HexColor("#" + hex_color)


# ------------------------------------------------------------ フォント
def _norm(name):
    name = unicodedata.normalize("NFC", name).lower()
    return "".join(ch for ch in name if ch.isalnum())


def _register(path, index=0):
    """TrueType を登録して reportlab 上の名前を返す。使えないファイルなら None。"""
    key = (path, index)
    if key not in _registered:
        name = "RVM{}".format(len(_registered))
        try:
            pdfmetrics.registerFont(TTFont(name, path, subfontIndex=index))
        except Exception:  # noqa: BLE001  壊れた/非対応の形式は候補から外す
            name = None
        _registered[key] = name
    return _registered[key]


def find_font_file(font_name, bold=False):
    """フォント名（例 "Arial"）に合う、埋め込み可能なフォントファイルを探す。無ければ None。"""
    base = _norm(font_name or "")
    key = (base, bold)
    if key in _font_file_cache:
        return _font_file_cache[key]
    found = None
    if base:
        if bold:
            wanted = {base + "bold", base + "bd", base + "b"}
        else:
            wanted = {base, base + "regular", base + "r"}
        for folder in FONT_DIRS:
            try:
                filenames = sorted(os.listdir(folder))
            except OSError:
                continue
            for filename in filenames:
                stem, ext = os.path.splitext(filename)
                if ext.lower() not in (".ttf", ".ttc", ".otf") or _norm(stem) not in wanted:
                    continue
                path = os.path.join(folder, filename)
                if _register(path):
                    found = path
                    break
            if found:
                break
    _font_file_cache[key] = found
    return found


def font_substitute(font_name):
    """PDF で指定フォントが見つからず代わりのフォントを使う場合、その名前を返す（問題なければ None）。"""
    if find_font_file(font_name):
        return None
    return D.UI_LATIN_FONT if find_font_file(D.UI_LATIN_FONT) else "Helvetica"


def _japanese_fonts():
    for regular, bold in JAPANESE_FONT_FILES:
        if os.path.exists(regular) and _register(regular):
            bold_name = _register(bold) if bold and os.path.exists(bold) else None
            return _register(regular), bold_name or _register(regular)
    if CID_FALLBACK not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(UnicodeCIDFont(CID_FALLBACK))
    return CID_FALLBACK, CID_FALLBACK


def _has_glyph(font_name, ch):
    face = getattr(pdfmetrics.getFont(font_name), "face", None)
    cmap = getattr(face, "charToGlyph", None)
    if cmap is not None:
        return ord(ch) in cmap
    try:                        # reportlab 内蔵の Helvetica など
        ch.encode("cp1252")
        return True
    except UnicodeEncodeError:
        return False


class _Fonts:
    """本文・見出しの欧文フォントと日本語フォント。1文字ずつ字形の有無で使い分ける。"""

    def __init__(self, body_font_name):
        ui = find_font_file(D.UI_LATIN_FONT)
        ui_bold = find_font_file(D.UI_LATIN_FONT, bold=True)
        self.ui = _register(ui) if ui else "Helvetica"
        self.ui_bold = _register(ui_bold) if ui_bold else "Helvetica-Bold"
        body = find_font_file(body_font_name)
        self.body = _register(body) if body else self.ui
        self.ja, self.ja_bold = _japanese_fonts()
        self._glyph_cache = {}
        self._width_cache = {}

    def pick(self, ch, latin, ja):
        if ch == " ":
            return latin
        key = (latin, ch)
        if key not in self._glyph_cache:
            self._glyph_cache[key] = _has_glyph(latin, ch)
        return latin if self._glyph_cache[key] else ja

    def runs(self, items, latin, ja):
        """[(文字, 色)] → 同じフォント・色の文字をまとめた [(文字列, フォント, 色)]"""
        out = []
        for ch, color in items:
            font = self.pick(ch, latin, ja)
            if out and out[-1][1] == font and out[-1][2] == color:
                out[-1] = (out[-1][0] + ch, font, color)
            else:
                out.append((ch, font, color))
        return out

    def ui_runs(self, text, color, bold=False, symbol=False):
        """見出し用。symbol=True は ♪ ● などを Word 出力と同じく日本語フォントで描く。"""
        latin, ja = (self.ui_bold, self.ja_bold) if bold else (self.ui, self.ja)
        return self.runs([(ch, color) for ch in text], ja if symbol else latin, ja)

    def char_width(self, ch, font, size):
        key = (ch, font, size)
        if key not in self._width_cache:
            self._width_cache[key] = pdfmetrics.stringWidth(ch, font, size)
        return self._width_cache[key]


def _runs_width(runs, size, char_space=0.0):
    return sum(pdfmetrics.stringWidth(text, font, size) + char_space * len(text)
               for text, font, _ in runs)


def _draw_runs(c, x, y, runs, size, char_space=0.0):
    text = c.beginText(x, y)
    text.setCharSpace(char_space)
    for chunk, font, color in runs:
        text.setFont(font, size)
        text.setFillColor(_color(color))
        text.textOut(chunk)
    c.drawText(text)


# ------------------------------------------------------------ 折り返し・ページ割り
def _is_wide(ch):
    return unicodedata.east_asian_width(ch) in ("W", "F")


def _atoms(items):
    """折り返しの単位に分ける: 英単語（空白まで）/ 空白 / 全角1文字（閉じ括弧などは前にくっつける）。"""
    atoms, word = [], []
    for item in items:
        ch = item[0]
        if ch == " " or _is_wide(ch):
            if word:
                atoms.append(word)
                word = []
            if ch in _NO_LINE_START and atoms and atoms[-1][0][0] != " ":
                atoms[-1] = atoms[-1] + [item]
            else:
                atoms.append([item])
        else:
            word.append(item)
    if word:
        atoms.append(word)
    return atoms


def wrap_line(items, measure, max_width):
    """[(文字, 赤字bool)] を max_width で折り返し、行ごとのリストにする。
    折り返し位置の空白は落とす。1語だけで幅を超えるときは文字単位で折る。"""
    lines, cur, cur_w = [], [], 0.0

    def push():
        while cur and cur[-1][0] == " ":
            cur.pop()
        lines.append(list(cur))

    for atom in _atoms(items):
        is_space = atom[0][0] == " "
        if is_space and not cur and lines:
            continue                    # 折り返した行の先頭に空白を残さない
        w = measure(atom)
        if cur and cur_w + w > max_width:
            push()
            cur, cur_w = [], 0.0
            if is_space:
                continue
        if w > max_width:
            for item in atom:
                cw = measure([item])
                if cur and cur_w + cw > max_width:
                    push()
                    cur, cur_w = [], 0.0
                cur.append(item)
                cur_w += cw
            continue
        cur.extend(atom)
        cur_w += w
    push()
    return lines


def _paginate(paragraphs, pitch, space_after, body_top, body_bottom):
    """paragraphs = [(連の行か, [行...])] → ページごとの {"lines": [(上端y, 行)], "bars": [(上端y, 下端y)]}"""
    pages = [{"lines": [], "bars": []}]
    y = body_top
    bar = None                          # [上端, 下端]

    def close_bar():
        nonlocal bar
        if bar is not None:
            pages[-1]["bars"].append(tuple(bar))
            bar = None

    for in_stanza, lines in paragraphs:
        if not in_stanza:
            close_bar()
        for line in lines:
            if y - pitch < body_bottom - 0.01 and pages[-1]["lines"]:
                close_bar()
                pages.append({"lines": [], "bars": []})
                y = body_top
            if in_stanza and bar is None:
                bar = [y, y]
            pages[-1]["lines"].append((y, line))
            y -= pitch
            if in_stanza:
                bar[1] = y
        y -= space_after
    close_bar()
    return pages


# ------------------------------------------------------------ ヘッダー・フッター
def _fit_title(fonts, title, max_width):
    """Word 出力と同じ文字サイズのまま帯の幅で折り返す（最大2行。入りきらない分は … で省略）。"""
    size = D.title_size_pt(title)

    def measure(items):
        return sum(fonts.char_width(ch, fonts.pick(ch, fonts.ui_bold, fonts.ja_bold), size)
                   for ch, _ in items)

    lines = wrap_line([(ch, D.WHITE) for ch in title], measure, max_width)
    if len(lines) > 2:
        ellipsis = [("…", D.WHITE)]
        second = list(lines[1])
        while second and measure(second + ellipsis) > max_width:
            second.pop()
        lines = [lines[0], second + ellipsis]
    return [fonts.runs(line, fonts.ui_bold, fonts.ja_bold) for line in lines], size


def _draw_header(c, fonts, title, page_h):
    x0 = _mm(D.MARGIN_LEFT_MM)
    width = _mm(D.TEXT_WIDTH_MM)
    top = page_h - _mm(D.HEADER_DISTANCE_MM)
    band_h = _mm(D.BAND_HEIGHT_MM)

    # 紺の帯: 小見出し + タイトル（帯の中で上下中央）、右端に音符、下に黄色の線
    c.setFillColor(_color(D.NAVY))
    c.rect(x0, top - band_h, width, band_h, stroke=0, fill=1)
    c.setFillColor(_color(D.ACCENT))
    c.rect(x0, top - band_h - D.ACCENT_WIDTH_PT, width, D.ACCENT_WIDTH_PT, stroke=0, fill=1)
    pad_x = _mm(D.BAND_PAD_X_MM)
    title_width = _mm(D.TEXT_WIDTH_MM - D.NOTES_WIDTH_MM - D.BAND_PAD_X_MM - 2.0)
    title_lines, title_size = _fit_title(fonts, D.display_title(title), title_width)
    block = D.BRAND_SIZE_PT * 1.15 + 1 + title_size * 1.15 * len(title_lines)
    pad_y = (band_h - block) / 2
    brand_y = top - pad_y - 0.92 * D.BRAND_SIZE_PT
    brand = (fonts.ui_runs(D.BRAND_MARK, D.SKY, symbol=True)
             + fonts.ui_runs(" " + D.BRAND_TEXT, D.SKY, bold=True))
    _draw_runs(c, x0 + pad_x, brand_y, brand, D.BRAND_SIZE_PT, D.BRAND_CHAR_SPACING_PT)
    title_y = top - pad_y - D.BRAND_SIZE_PT * 1.15 - 1 - 0.92 * title_size
    for runs in title_lines:
        _draw_runs(c, x0 + pad_x, title_y, runs, title_size)
        title_y -= title_size * 1.15
    notes = fonts.ui_runs(D.NOTES_MARK, D.NOTES, symbol=True)
    notes_x = x0 + width - pad_x - _runs_width(notes, D.NOTES_SIZE_PT)
    _draw_runs(c, notes_x, top - band_h / 2 - 0.36 * D.NOTES_SIZE_PT, notes, D.NOTES_SIZE_PT)

    # 黄色の線の下: 凡例（左）・なまえ欄（右）
    center = top - band_h - D.ACCENT_WIDTH_PT - _mm(D.INFO_HEIGHT_MM) / 2
    size = D.INFO_SIZE_PT
    example_size = size + 1.5
    legend_y = center + 0.575 * example_size - 0.92 * example_size
    x = x0 + _mm(1.0)
    for runs, run_size in (
        (fonts.ui_runs("●", D.RED, symbol=True), D.LEGEND_DOT_SIZE_PT),
        (fonts.ui_runs(" " + D.LEGEND_TEXT, D.NAVY, bold=True), size),
        (fonts.ui_runs("　　" + D.LEGEND_EXAMPLE_LABEL + " ", D.MUTED), size),
        ([r for frag, red in D.LEGEND_EXAMPLE
          for r in fonts.ui_runs(frag, D.RED if red else D.BLACK, bold=True)], example_size),
    ):
        _draw_runs(c, x, legend_y, runs, run_size)
        x += _runs_width(runs, run_size)

    name_x = x0 + width - _mm(D.NAME_FIELD_WIDTH_MM)
    name_h = size * 1.15 + 2 + 0.75
    name_y = center + name_h / 2 - 0.92 * size
    _draw_runs(c, name_x, name_y, fonts.ui_runs(D.NAME_LABEL, D.NAVY, bold=True), size)
    line_y = name_y - 0.23 * size - 2 - 0.375
    c.setStrokeColor(_color(D.MUTED))
    c.setLineWidth(0.75)
    c.line(name_x, line_y, x0 + width, line_y)


def _draw_footer(c, fonts, page_no, total):
    x0 = _mm(D.MARGIN_LEFT_MM)
    width = _mm(D.TEXT_WIDTH_MM)
    size = D.FOOTER_SIZE_PT
    base_y = _mm(D.FOOTER_DISTANCE_MM) + 0.23 * size
    rule_y = base_y + 0.92 * size + 4 + 0.375
    c.setStrokeColor(_color(D.RULE))
    c.setLineWidth(0.75)
    c.line(x0, rule_y, x0 + width, rule_y)
    _draw_runs(c, x0, base_y, fonts.ui_runs(D.FOOTER_TEXT, D.MUTED), size, 0.4)
    numbers = (fonts.ui_runs(str(page_no), D.NAVY)
               + fonts.ui_runs(" / {}".format(total), D.MUTED))
    _draw_runs(c, x0 + width - _runs_width(numbers, size), base_y, numbers, size)


# ------------------------------------------------------------ 本体
def write_pdf(text: str,
              filepath: str,
              font_name: str = "Arial",
              font_size: float = 24,
              use_exceptions: bool = True,
              silent_e: bool = True,
              y_as_vowel: bool = True,
              title: str = ""):
    """text を処理して filepath に PDF を保存する。引数は write_docx と同じ。"""
    fonts = _Fonts(font_name)
    opts = dict(
        use_exceptions=use_exceptions,
        silent_e=silent_e,
        y_as_vowel=y_as_vowel,
    )
    page_w, page_h = _mm(D.PAGE_WIDTH_MM), _mm(D.PAGE_HEIGHT_MM)
    x0 = _mm(D.MARGIN_LEFT_MM)
    text_x = x0 + _mm(D.BODY_INDENT_MM)
    max_width = _mm(D.TEXT_WIDTH_MM - D.BODY_INDENT_MM)

    def measure(items):
        return sum(fonts.char_width(ch, fonts.pick(ch, fonts.body, fonts.ja), font_size)
                   for ch, _ in items)

    paragraphs = []
    for line in text.split("\n"):
        items = [(ch, red)
                 for fragment, red in mark_line(line.replace("\t", "    "), **opts)
                 for ch in fragment]
        in_stanza = "".join(ch for ch, _ in items).strip() != ""
        paragraphs.append((in_stanza, wrap_line(items, measure, max_width)))

    natural = font_size * 1.15
    pitch = natural * D.LINE_SPACING
    pages = _paginate(paragraphs, pitch, D.SPACE_AFTER_PT,
                      page_h - _mm(D.MARGIN_TOP_MM), _mm(D.MARGIN_BOTTOM_MM))

    c = canvas.Canvas(filepath, pagesize=(page_w, page_h), pageCompression=1)
    c.setTitle(D.display_title(title))
    c.setCreator(D.FOOTER_TEXT)
    bar_x = text_x - D.STANZA_BAR_GAP_PT - D.STANZA_BAR_WIDTH_PT
    for number, page in enumerate(pages, start=1):
        _draw_header(c, fonts, title, page_h)
        c.setFillColor(_color(D.STANZA_BAR))
        for top, bottom in page["bars"]:
            c.rect(bar_x, bottom, D.STANZA_BAR_WIDTH_PT, top - bottom, stroke=0, fill=1)
        for top, items in page["lines"]:
            baseline = top - (pitch - natural) / 2 - 0.92 * font_size
            colored = [(ch, D.RED if red else D.BLACK) for ch, red in items]
            _draw_runs(c, text_x, baseline, fonts.runs(colored, fonts.body, fonts.ja), font_size)
        _draw_footer(c, fonts, number, len(pages))
        c.showPage()
    c.save()
    return filepath
