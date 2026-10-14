import re
import tempfile
import unittest
from pathlib import Path

import pdf_writer
import sheet_design
from pdf_writer import font_substitute, find_font_file, wrap_line, write_pdf


def page_count(path):
    data = Path(path).read_bytes()
    return len(re.findall(rb"/Type\s*/Page(?![a-z])", data))


def chars(text, red=False):
    return [(ch, red) for ch in text]


def plain(line):
    return "".join(ch for ch, _ in line)


class PdfOutputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="syllables-pdf-test-")
        self.output = Path(self.temp.name) / "synthetic.pdf"

    def tearDown(self):
        self.temp.cleanup()

    def test_short_text_is_one_page(self):
        write_pdf("Make a dream!\n\n日本語 123 (OK)\n", str(self.output), title="Synthetic")
        data = self.output.read_bytes()
        self.assertTrue(data.startswith(b"%PDF"))
        self.assertEqual(page_count(self.output), 1)

    def test_long_text_continues_on_more_pages(self):
        text = "\n".join("We can make a dream" for _ in range(20))
        write_pdf(text, str(self.output), font_size=24)
        self.assertGreater(page_count(self.output), 1)
        write_pdf(text, str(self.output), font_size=12)
        self.assertEqual(page_count(self.output), 1)

    def test_wrap_keeps_text_and_drops_break_spaces(self):
        line = chars("aa bb cc dd")
        lines = wrap_line(line, len, 5)
        self.assertEqual([plain(l) for l in lines], ["aa bb", "cc dd"])
        self.assertEqual(wrap_line(chars("   aa"), len, 10)[0], chars("   aa"))  # 行頭の字下げは保持
        self.assertEqual([plain(l) for l in wrap_line(chars("abcdefgh"), len, 3)],
                         ["abc", "def", "gh"])
        self.assertEqual(wrap_line([], len, 5), [[]])

    def test_wrap_keeps_red_flags_and_japanese_punctuation(self):
        line = [("m", False), ("a", True), ("k", False), ("e", False), (" ", False)] + chars("あいう。")
        lines = wrap_line(line, len, 7)
        self.assertEqual(lines[0][1], ("a", True))
        self.assertTrue(all(not l or l[0][0] != "。" for l in lines))
        self.assertEqual("".join(plain(l) for l in lines), "make あいう。")

    def test_stanza_bars_break_at_blank_lines_and_pages(self):
        paragraphs = [(True, [["x"]]), (True, [["x"]]), (False, [[]]), (True, [["x"]] * 3)]
        pages = pdf_writer._paginate(paragraphs, pitch=10, space_after=0, body_top=40, body_bottom=0)
        self.assertEqual([len(p["lines"]) for p in pages], [4, 2])
        self.assertEqual(pages[0]["bars"], [(40, 20), (10, 0)])
        self.assertEqual(pages[1]["bars"], [(40, 20)])

    def test_font_fallback(self):
        fonts = pdf_writer._Fonts("Arial")
        self.assertEqual(fonts.pick("あ", fonts.body, fonts.ja), fonts.ja)
        self.assertEqual(fonts.pick("a", fonts.body, fonts.ja), fonts.body)
        self.assertIn(font_substitute("No Such Synthetic Font"), (sheet_design.UI_LATIN_FONT, "Helvetica"))
        if find_font_file("Arial"):
            self.assertIsNone(font_substitute("arial"))

    def test_missing_font_still_writes(self):
        write_pdf("make", str(self.output), font_name="No Such Synthetic Font")
        self.assertEqual(page_count(self.output), 1)


if __name__ == "__main__":
    unittest.main()
