# -*- coding: utf-8 -*-
"""品質確認テスト。実行: python3 test_vowel_marker.py"""

from vowel_marker import mark_vowel_nuclei, preview_line


def red_text(word):
    """赤字対象の文字列だけを連結して返す（検証用）。"""
    return "".join(t for t, red in mark_vowel_nuclei(word) if red)


CASES = [
    # (単語, 期待する赤字部分の連結)
    ("make", "a"),
    ("name", "a"),
    ("alive", "ai"),       # a と i（連結すると "ai"）
    ("bloom", "oo"),
    ("through", "ou"),
    ("flowers", "owe"),    # ow と e（隣接して "owe"）
    ("journey", "ouey"),   # ou と ey
    ("galaxy", "aay"),     # a, a, y
    ("express", "ee"),     # e と e
    ("999", ""),           # 数字はそのまま（赤字なし）
    ("こんにちは", ""),      # 日本語はそのまま
    ("カタカナ", ""),        # カタカナはそのまま
]


def main():
    ok = True
    print("=== 赤字対象の検証 ===")
    for word, expected in CASES:
        got = red_text(word)
        status = "OK " if got == expected else "NG "
        if got != expected:
            ok = False
        print(f"  [{status}] {word:>10} -> red={got!r:8}  (expected {expected!r})")

    print("\n=== プレビュー表示の例 ===")
    for line in [
        "I will go to the stars",
        "We can make a dream",
        "The train runs through the night",
        "999 と 日本語 カタカナ はそのまま",
    ]:
        print(f"  {line}")
        print(f"    -> {preview_line(line)}")

    print("\n結果:", "全て合格 ✅" if ok else "不一致あり ❌")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
