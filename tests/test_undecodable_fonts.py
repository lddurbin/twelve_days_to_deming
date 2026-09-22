"""Tests for scripts/lib/undecodable_fonts.py — text poppler cannot decode (#852).

The source PDFs are gitignored and local-only (#734), so everything here is
driven from hand-written `pdftohtml -xml` fixtures, the same constraint
tests/test_emphasis.py works under.

What these pin, in order of what would hurt most if it broke:

  1. Real text is never judged undecodable. Every bound in the classifier
     exists to keep one kind of real font in — prose, figure numerals, a
     bracket-and-label font, a contents page — and each gets a test that it
     stays in. A classifier that silently widens deletes source text from
     both checkers.
  2. strip() only ever removes what was read as ciphertext, on the page it
     was read from.
  3. The page-marker contract with paragraphs.py, which this module
     duplicates rather than imports.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

import emphasis  # noqa: E402
import paragraphs  # noqa: E402
import undecodable_fonts as uf  # noqa: E402

# Day 7's running banner, exactly as poppler returns it.
BANNER = ('1"20,+*3$4552".*"6*3$7,2\'&2-"/8,$9/:.8"+&2*3$;<&+"*3$'
          '=5,8.\'.8"+.&/*3$7"#$\'&2$7,2\'&2-"/8,3$>./"/8."6$9/8,/+.?,*3$')
FOOTER = '!"#$%$$&$$\'"()$'


def xml(fonts, pages):
    """A `pdftohtml -xml` document.

    `fonts` maps a font id to its family; `pages` is a list of pages, each a
    list of (font id, text) elements, laid out one per line.
    """
    out = ['<?xml version="1.0" encoding="UTF-8"?>', "<pdf2xml>"]
    for number, elements in enumerate(pages, start=1):
        out.append(f'<page number="{number}" position="absolute" '
                   f'top="0" left="0" height="1188" width="918">')
        if number == 1:
            for font_id, family in fonts.items():
                out.append(f'\t<fontspec id="{font_id}" size="15" '
                           f'family="{family}" color="#000000"/>')
        for line, (font_id, text) in enumerate(elements):
            escaped = (text.replace("&", "&amp;").replace("<", "&lt;")
                       .replace(">", "&gt;").replace('"', "&#34;"))
            out.append(f'<text top="{100 + 20 * line}" left="98" width="700" '
                       f'height="17" font="{font_id}">{escaped}</text>')
        out.append("</page>")
    out.append("</pdf2xml>")
    return "\n".join(out)


class ClassifierTests(unittest.TestCase):

    def judged(self, family_texts):
        """The families judged undecodable, given {family: [texts]}."""
        fonts = {str(i): family for i, family in enumerate(family_texts)}
        page = [(str(i), text)
                for i, texts in enumerate(family_texts.values())
                for text in texts]
        ids = uf.undecodable_fonts(xml(fonts, [page]))
        return {fonts[i] for i in ids}

    def test_the_banner_cipher_is_undecodable(self):
        self.assertEqual(self.judged({"ROSMJU+Cambria": [BANNER]}),
                         {"ROSMJU+Cambria"})

    def test_prose_is_not(self):
        self.assertEqual(self.judged({"IOCKFT+HelveticaNeue": [
            "Let's spend a little time revisiting those massive issues."]}),
            set())

    def test_workbook_citations_are_not(self):
        """The lowest-letter real text in the corpus (0.34, Day 11)."""
        self.assertEqual(self.judged({"GBFUXH+HelveticaNeue": [
            "[WB 186]", "[WB 189]", "[WB 190]", "DemDim"]}), set())

    def test_punctuation_heavy_prose_is_not(self):
        """Shaped on Day 5's schedule font (ZHGJOX): page pointers and
        workbook citations, over the punctuation bound with plenty of
        variety, so only the letter bound keeps it."""
        self.assertEqual(self.judged({"ZHGJOX+HelveticaNeue": [
            "Introduction (p 1)", "[WB 49]: ...!", "&c.", "\"Point 7\"",
            "(p 3); (p 9); (p 11)", "(p 14); (p 17): (p 21)",
            "(p 25); (p 28)", "(p 30)? [p 31]"]}), set())

    def test_a_numeric_table_is_not(self):
        """Letter-free and punctuated in six different ways, but mostly
        digits — only the punctuation share keeps it."""
        self.assertEqual(self.judged({"KHITHG+Helvetica": [
            "(0.986)", "1,000", "2/3", "-4", "+5", "25%", "1024", "999"]}),
            set())

    def test_figure_numerals_are_not(self):
        """Letter-free, but digits rather than punctuation."""
        self.assertEqual(self.judged({"XKIPUB+Helvetica": [
            "0.10", "0.10", "6", "10", "6", "10", "(0", "0.986)"]}), set())

    def test_a_bracket_and_label_font_is_not(self):
        """Optional Extras' MIEUDQ: under the letter bound and over the
        punctuation one, and kept only because it uses three different
        characters."""
        self.assertEqual(self.judged({"MIEUDQ+HelveticaNeue": [
            "(", ")", "  ...  ", " (", ")", "UCL"] + ["(", ")"] * 10}), set())

    def test_a_contents_page_is_not(self):
        """Dot leaders are one repeated character, counted once. Without that
        the main Appendix's contents font passes every other bound: it has
        punctuation to spare, and its entries are short."""
        self.assertEqual(self.judged({"OQKTTN+HelveticaNeue": [
            "Day 1: (A) ................................. 3",
            "Day 2 & 3, 'B' ............................. 9",
            "Day 4/5 - C? ............................... 17",
            "Day 6; D! .................................. 25"]}), set())

    def test_bullets_are_not(self):
        """Non-ASCII glyphs never count as punctuation."""
        self.assertEqual(self.judged({"NDFKIV+Symbol": ["•", "•", "•"]}),
                         set())

    def test_the_judgement_is_per_family_not_per_id(self):
        """A subset used at two sizes gets two ids. A two-character use of it
        read alone would pass every bound; read with its family it doesn't
        need to."""
        fonts = {"0": "EGWCTJ+Cambria", "1": "EGWCTJ+Cambria",
                 "2": "IOCKFT+HelveticaNeue"}
        page = [("0", FOOTER), ("1", "#$"), ("2", "Some ordinary prose.")]
        self.assertEqual(uf.undecodable_fonts(xml(fonts, [page])), {"0", "1"})

    def test_the_bounds_are_where_the_docstring_says(self):
        """The docstring's measurements are stated against these values."""
        self.assertEqual(uf.MAX_LETTER_SHARE, 0.25)
        self.assertEqual(uf.MIN_PUNCT_SHARE, 0.4)
        self.assertEqual(uf.MIN_DISTINCT_PUNCT, 6)
        self.assertEqual(uf.MIN_STRIP_LEN, 3)


class StripTests(unittest.TestCase):

    def marked(self, *pages):
        return paragraphs.mark_pages("\f".join(pages))

    def test_removes_the_banner_and_keeps_the_prose(self):
        text = self.marked(f"   {BANNER}\nTHREE KINDS OF NUMERICAL TARGETS\n")
        out, removed = uf.strip(text, {1: {BANNER}})
        self.assertNotIn(BANNER, out)
        self.assertIn("THREE KINDS OF NUMERICAL TARGETS", out)
        self.assertEqual(removed, len(BANNER))

    def test_removes_a_token_glued_to_its_neighbour(self):
        """`pdftotext -layout` joins adjacent elements: Day 7's footer comes
        out with another subset's `#$` stuck to its end."""
        out, _ = uf.strip(self.marked(f"{FOOTER}#$\n"), {1: {FOOTER}})
        self.assertNotIn(FOOTER, out)

    def test_only_on_the_page_it_was_read_from(self):
        text = self.marked("one\n", f"{FOOTER}\n", f"{FOOTER}\n")
        out, removed = uf.strip(text, {2: {FOOTER}})
        self.assertEqual(out.count(FOOTER), 1)
        self.assertEqual(removed, len(FOOTER))
        # And it is page 3's copy that survives.
        self.assertTrue(out.rstrip().endswith(FOOTER))

    def test_short_tokens_are_left_alone(self):
        """Removal is by substring, so `!` would take every real `!` on the
        page with it."""
        text = self.marked("What a surprise! Really!\n")
        out, removed = uf.strip(text, {1: {"!", "#$"}})
        self.assertEqual(out, text)
        self.assertEqual(removed, 0)

    def test_longest_first(self):
        text = self.marked('X!"#$%&Y\n')
        out, _ = uf.strip(text, {1: {'!"#', '!"#$%&'}})
        self.assertIn("X Y", out)

    def test_markers_pass_through(self):
        text = self.marked("a\n", "b\n")
        out, _ = uf.strip(text, {})
        self.assertEqual(out, text)

    def test_the_page_marker_is_the_one_paragraphs_writes(self):
        """Duplicated rather than imported; this is what keeps them one."""
        self.assertEqual(uf._PAGE_MARKER.pattern,
                         paragraphs._PAGE_MARKER.pattern)
        self.assertEqual(uf.FIRST_PAGE, paragraphs.FIRST_PAGE)


class EmphasisStreamTests(unittest.TestCase):
    """pdf_words() is the emphasis-side consumer."""

    FONTS = {"0": "ROSMJU+Cambria", "1": "IOCKFT+HelveticaNeue"}

    def test_undecodable_text_never_enters_the_stream(self):
        words = emphasis.pdf_words(None, xml=xml(self.FONTS, [[
            ("0", BANNER), ("1", "Let's spend a little time")]]))
        self.assertEqual([w["raw"] for w in words],
                         ["Let's", "spend", "a", "little", "time"])

    def test_the_words_either_side_do_not_run_together(self):
        """An undecodable element on the same line leaves a gap, not a join."""
        doc = xml(self.FONTS, [[("1", "before")]]).replace(
            "</page>",
            '<text top="100" left="200" width="50" height="17" font="0">'
            + FOOTER.replace("&", "&amp;").replace('"', "&#34;")
            + '</text>\n<text top="100" left="251" width="50" height="17" '
            'font="1">after</text>\n</page>')
        words = emphasis.pdf_words(None, xml=doc)
        self.assertEqual([w["raw"] for w in words], ["before", "after"])


if __name__ == "__main__":
    unittest.main()
