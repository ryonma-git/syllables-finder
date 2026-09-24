# -*- coding: utf-8 -*-
"""
vowel_marker.py

英単語を受け取り、「声を乗せるべき母音核」だけを赤字対象として返す中心ロジック。

中心関数:
    mark_vowel_nuclei(word) -> list[tuple[str, bool]]
        文字列断片と「その断片を赤字にするか」の bool のリストを返す。

        例)
        mark_vowel_nuclei("make")    -> [("m", False), ("a", True), ("ke", False)]
        mark_vowel_nuclei("bloom")   -> [("bl", False), ("oo", True), ("m", False)]
        mark_vowel_nuclei("through") -> [("thr", False), ("ou", True), ("gh", False)]

        ※ 連続する同じ状態の文字はまとめて1断片にしています
          (例: "ke" は黒のまま1つにまとまる)。
          赤字／黒字の見た目は仕様通りです。

行・テキスト全体の処理:
    mark_line(line)  -> list[tuple[str, bool]]
    preview_text(text) -> str   （赤字対象を [ ] で囲んだ簡易表示）

トークン処理:
    - 英単語・アポストロフィを含む語・ハイフン語だけを mark_vowel_nuclei に渡す
    - 空白・句読点・括弧・数字・日本語・カタカナ・記号はそのまま黒字で出力
    - 音節区切り記号「•」は最終出力に含めない（入力に混じっていても除去）
"""

import re

from exception_dictionary import EXCEPTIONS

# 英単語トークン: アルファベット列。内部にアポストロフィ('  ’)やハイフン(-)を含む語も1語として扱う。
# 例) don't, we'll, I'll, ice-cream, let's
WORD_RE = re.compile(r"[A-Za-z]+(?:['’\-][A-Za-z]+)*")

# 基本母音
BASE_VOWELS = set("aeiou")

# 入力に紛れ込んだ音節区切り記号（最終出力には入れない）
SYLLABLE_MARKS = "•·‧・"


def _is_vowel_char(ch: str, idx: int, y_as_vowel: bool) -> bool:
    """その位置の文字を母音候補とみなすか。

    - a, e, i, o, u は常に母音候補。
    - y は y_as_vowel=True かつ語頭以外のときだけ母音候補
      （語頭の y は子音: yes, yellow など）。
    """
    c = ch.lower()
    if c in BASE_VOWELS:
        return True
    if y_as_vowel and c == "y" and idx > 0:
        return True
    return False


def _group_by_flag(word: str, red_flags: list) -> list:
    """文字ごとの赤字フラグを、連続する同じフラグごとにまとめて
    (断片, 赤字かどうか) のリストにする。元の大文字小文字は保持。"""
    result = []
    n = len(word)
    i = 0
    while i < n:
        cur = red_flags[i]
        j = i
        while j < n and red_flags[j] == cur:
            j += 1
        result.append((word[i:j], cur))
        i = j
    return result


def mark_vowel_nuclei(word: str,
                      use_exceptions: bool = True,
                      silent_e: bool = True,
                      y_as_vowel: bool = True) -> list:
    """1単語の母音核を判定し、(断片, 赤字bool) のリストを返す。

    オプション:
        use_exceptions: 例外辞書を使う（デフォルト True）
        silent_e:       語末の silent e を赤字にしない（デフォルト True）
        y_as_vowel:     y を母音として扱う（デフォルト True）
    """
    if not word:
        return []

    n = len(word)
    red = [False] * n
    lower = word.lower()

    # 1) 例外辞書を最優先
    if use_exceptions and lower in EXCEPTIONS:
        for start, stop in EXCEPTIONS[lower]:
            for k in range(start, stop):
                if 0 <= k < n:
                    red[k] = True
        return _group_by_flag(word, red)

    # 2) ルールによる母音グループ判定
    i = 0
    while i < n:
        if _is_vowel_char(word[i], i, y_as_vowel):
            # 連続母音は一まとまり（ee, ea, ai, ay, oa, oo, ou, oi, oy, ie, ei, ue, ui ...）
            j = i
            while j < n and _is_vowel_char(word[j], j, y_as_vowel):
                j += 1
            # 母音直後の w は二重母音(ow, ew, aw)として母音グループに含める
            if j < n and word[j].lower() == "w":
                j += 1
            for k in range(i, j):
                red[k] = True
            i = j
        else:
            i += 1

    # 3) 語末 silent e（magic e）: 直前が子音の単独 'e' は読まない → 赤字にしない
    #    （bee/see のように 'ee' の一部なら読むので対象外）
    if silent_e and lower.endswith("e"):
        last = n - 1
        if red[last] and (last == 0 or not _is_vowel_char(word[last - 1], last - 1, y_as_vowel)):
            red[last] = False

    return _group_by_flag(word, red)


def _strip_syllable_marks(text: str) -> str:
    """音節区切り記号を除去（最終出力には入れない仕様）。"""
    for m in SYLLABLE_MARKS:
        text = text.replace(m, "")
    return text


def mark_line(line: str,
              use_exceptions: bool = True,
              silent_e: bool = True,
              y_as_vowel: bool = True) -> list:
    """1行を処理して (断片, 赤字bool) のリストを返す。
    英単語以外（空白・記号・日本語・数字など）はそのまま黒字で保持する。"""
    line = _strip_syllable_marks(line)
    fragments = []
    pos = 0
    for m in WORD_RE.finditer(line):
        # 単語の前にある非単語部分（空白・記号・日本語など）はそのまま
        if m.start() > pos:
            fragments.append((line[pos:m.start()], False))
        fragments.extend(
            mark_vowel_nuclei(
                m.group(),
                use_exceptions=use_exceptions,
                silent_e=silent_e,
                y_as_vowel=y_as_vowel,
            )
        )
        pos = m.end()
    # 末尾の非単語部分
    if pos < len(line):
        fragments.append((line[pos:], False))
    return fragments


def preview_line(line: str, **opts) -> str:
    """1行の簡易プレビュー。赤字対象を [ ] で囲んだ文字列を返す。"""
    parts = []
    for text, red in mark_line(line, **opts):
        parts.append("[" + text + "]" if red else text)
    return "".join(parts)


def preview_text(text: str, **opts) -> str:
    """テキスト全体（複数行）の簡易プレビュー。改行は保持する。"""
    return "\n".join(preview_line(line, **opts) for line in text.split("\n"))
