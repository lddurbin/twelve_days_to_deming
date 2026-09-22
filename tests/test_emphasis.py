"""Tests for scripts/lib/emphasis.py — the emphasis checker (#846).

The source PDFs are gitignored and local-only (#734), so nothing here may run
poppler over a real one and nothing may need `quarto`. Both sides are driven
from fixtures instead: `pdftohtml -xml` output as a string, and hand-written
pandoc ASTs. That is a constraint worth stating rather than working around —
it is the same reason check-validation-staleness.sh compares recorded hashes
instead of re-running the comparison.

What these pin, in order of what would hurt most if it broke:

  1. The convention allowlist. Every entry suppresses findings, so a rule that
     silently widens is how real lost emphasis stops being reported. Each rule
     gets a test that it fires, and the broad ones get a test that they do NOT
     fire on the neighbouring case.
  2. Colour's direction. #846 decided colour is never emphasis. It may only
     ever explain away an `added` run; it must never create a finding, and it
     must never explain a `lost` one.
  3. The per-character style read. Poppler nests <b>/<i> inside an element, so
     a per-element shortcut mis-attributes mixed runs — the one parsing trap
     #825 calls out.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import json
import os
import re
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

import emphasis  # noqa: E402


def pdf_word(n, bold=False, italic=False, page=1, coloured=False, raw=None):
    return dict(n=n, raw=raw or n, page=page, styles=((bold, italic),) * len(n),
                font="1", size=10, coloured=coloured, large=False)


def qmd_word(n, bold=False, italic=False, ctx=(), raw=None):
    return dict(n=n, raw=raw or n, styles=((bold, italic),) * len(n),
                ctx=tuple(ctx), file="01-test.qmd")


def mixed(n, styles, raw=None, page=1, ctx=()):
    """A word whose letters do not all agree, which is what #850 is about.

    `styles` is one character per letter of `n`: `b` bold, `i` italic, `.`
    plain. `outcomes` with `outcome` bold is `mixed("outcomes", "bbbbbbb.")`.
    The dict carries both sides' keys so one helper serves both streams.
    """
    code = {"b": (True, False), "i": (False, True), ".": (False, False)}
    assert len(styles) == len(n), (n, styles)
    return dict(n=n, raw=raw or n, page=page,
                styles=tuple(code[s] for s in styles),
                font="1", size=10, coloured=False, large=False,
                ctx=tuple(ctx), file="01-test.qmd")


def walk_qmd(blocks):
    stream = emphasis.WordStream()
    emphasis.walk_blocks(blocks, dict(bold=False, italic=False, ctx=()),
                         stream, "01-test.qmd")
    return stream.words


def style_of(word):
    """The one (bold, italic) every letter of `word` carries.

    A convenience for the fixtures above and for tests about something other
    than partial emphasis; it deliberately refuses a mixed word, so a test
    that means to build one has to say so.
    """
    distinct = set(word["styles"])
    assert len(distinct) == 1, f"{word['n']} is mixed: {word['styles']}"
    return distinct.pop()


class NormaliseTests(unittest.TestCase):
    def test_folds_case_accents_and_punctuation(self):
        self.assertEqual(emphasis.norm("Ne’er"), "neer")
        self.assertEqual(emphasis.norm("SYSTEM,"), "system")
        self.assertEqual(emphasis.norm("café"), "cafe")

    def test_punctuation_only_folds_to_nothing(self):
        """Words that fold away are dropped, not aligned as empty matches."""
        self.assertEqual(emphasis.norm("—"), "")


class StyledSegmentTests(unittest.TestCase):
    """The parsing trap: one <text> element, two styles."""

    def test_mixed_styles_inside_one_element(self):
        segments = emphasis._styled_segments(
            "<i>DemDim</i> Chapter 18 provides")
        self.assertEqual(segments[0], ("DemDim", False, True))
        self.assertEqual(segments[1], (" Chapter 18 provides", False, False))

    def test_bold_and_italic_together(self):
        self.assertEqual(
            emphasis._styled_segments("<b><i>both</i></b>"),
            [("both", True, True)])

    def test_entities_are_unescaped(self):
        self.assertEqual(
            emphasis._styled_segments("Deming&#8217;s"), [("Deming’s", False, False)])

    def test_non_style_tags_are_dropped_without_affecting_style(self):
        segments = emphasis._styled_segments("<a href='x'>plain</a>")
        self.assertEqual(segments, [("plain", False, False)])


# A minimal but structurally real `pdftohtml -xml` document: two lines, an
# italic run split across an element boundary, and an end-of-line hyphen.
PDF_XML = """<?xml version="1.0" encoding="UTF-8"?>
<pdf2xml>
<page number="7" position="absolute" top="0" left="0" height="1188" width="918">
<fontspec id="0" size="11" family="Cambria" color="#000000"/>
<fontspec id="1" size="11" family="Cambria-Italic" color="#000000"/>
<fontspec id="2" size="11" family="Cambria" color="#0000ff"/>
<text top="100" left="50" width="60" height="14" font="0">The crippling </text>
<text top="100" left="112" width="70" height="14" font="1"><i>disease</i></text>
<text top="120" left="50" width="90" height="14" font="0">in compari- </text>
<text top="140" left="50" width="40" height="14" font="0">son now</text>
<text top="160" left="50" width="50" height="14" font="2">Deming said</text>
</page>
</pdf2xml>
"""


class PdfWordTests(unittest.TestCase):
    def setUp(self):
        self.words = emphasis.pdf_words(None, xml=PDF_XML)
        self.by_name = {w["n"]: w for w in self.words}

    def test_italic_font_marks_its_word(self):
        self.assertEqual(style_of(self.by_name["disease"]), (False, True))
        self.assertEqual(style_of(self.by_name["the"]), (False, False))

    def test_end_of_line_hyphenation_is_joined(self):
        """`compari- son` across a line break is one word, as #740 made it on
        the similarity side. Without this it aligns against nothing and every
        word near it reads as a style disagreement."""
        self.assertIn("comparison", self.by_name)
        self.assertNotIn("compari", self.by_name)

    def test_page_number_is_carried(self):
        self.assertEqual(self.by_name["disease"]["page"], 7)

    def test_colour_is_recorded_but_is_not_emphasis(self):
        said = self.by_name["said"]
        self.assertTrue(said["coloured"])
        self.assertEqual(style_of(said), (False, False))


class PandocWalkTests(unittest.TestCase):
    """The QMD side, driven from hand-written ASTs so `quarto` is not needed."""

    walk = staticmethod(walk_qmd)

    def test_emph_and_strong(self):
        words = self.walk([{"t": "Para", "c": [
            {"t": "Str", "c": "plain"},
            {"t": "Space"},
            {"t": "Emph", "c": [{"t": "Str", "c": "italic"}]},
            {"t": "Space"},
            {"t": "Strong", "c": [{"t": "Str", "c": "bold"}]},
        ]}])
        self.assertEqual([(w["n"],) + style_of(w) for w in words],
                         [("plain", False, False), ("italic", False, True),
                          ("bold", True, False)])

    def test_div_class_becomes_context(self):
        words = self.walk([{"t": "Div", "c": [
            ["", ["deming_quote"], []],
            [{"t": "Para", "c": [{"t": "Str", "c": "quoted"}]}]]}])
        self.assertIn("deming_quote", words[0]["ctx"])

    def test_header_is_marked(self):
        words = self.walk([{"t": "Header", "c": [
            1, ["id", [], []], [{"t": "Str", "c": "Title"}]]}])
        self.assertIn("header", words[0]["ctx"])

    def test_raw_inline_html_emphasis_is_tracked(self):
        """Day 11 sets emphasis with literal <em>; pandoc keeps it raw, and
        without this every word inside reads as plain and flags as lost."""
        words = self.walk([{"t": "Para", "c": [
            {"t": "RawInline", "c": ["html", "<em>"]},
            {"t": "Str", "c": "stressed"},
            {"t": "RawInline", "c": ["html", "</em>"]},
            {"t": "Space"},
            {"t": "Str", "c": "after"},
        ]}])
        self.assertEqual(style_of(words[0]), (False, True))
        self.assertEqual(style_of(words[1]), (False, False))

    def test_an_unclosed_raw_tag_does_not_bleed_past_its_paragraph(self):
        """An unclosed <em> runs to the end of its inline list and no further.

        The RawInline branch has to carry state between sibling nodes, since
        `<em>` and `</em>` are separate nodes. That makes an unclosed tag
        bleed — but only within one paragraph, because walk_blocks hands each
        block the caller's state rather than the previous block's. Pinned so
        a refactor that shared state between blocks fails here instead of
        silently italicising the rest of a chapter.
        """
        words = self.walk([
            {"t": "Para", "c": [
                {"t": "RawInline", "c": ["html", "<em>"]},
                {"t": "Str", "c": "unclosed"},
                {"t": "Space"},
                {"t": "Str", "c": "sibling"},
            ]},
            {"t": "Para", "c": [{"t": "Str", "c": "after"}]},
        ])
        by_name = {w["n"]: w for w in words}
        self.assertEqual(style_of(by_name["unclosed"]), (False, True))
        self.assertEqual(style_of(by_name["sibling"]), (False, True),
                         "an open tag must carry to later siblings — that is "
                         "how <em>…</em> works at all")
        self.assertEqual(style_of(by_name["after"]), (False, False),
                         "but it must not escape the paragraph")

    def test_math_is_marked_as_math(self):
        words = self.walk([{"t": "Para", "c": [
            {"t": "Math", "c": [{"t": "InlineMath"}, "n"]}]}])
        self.assertIn("math", words[0]["ctx"])

    def test_table_header_cells_are_distinguished_from_body_cells(self):
        def cell(text):
            return [["", [], []], {"t": "AlignDefault"}, 1, 1,
                    [{"t": "Plain", "c": [{"t": "Str", "c": text}]}]]
        row = lambda text: [["", [], []], [cell(text)]]
        table = {"t": "Table", "c": [
            ["", [], []], [None, []], [],
            [["", [], []], [row("Head")]],
            [[["", [], []], 0, [row("Body")], []]],
            [["", [], []], []]]}
        words = {w["n"]: w for w in self.walk([table])}
        self.assertIn("th", words["head"]["ctx"])
        self.assertNotIn("th", words["body"]["ctx"])

    def test_code_blocks_contribute_no_words(self):
        self.assertEqual(self.walk([{"t": "CodeBlock",
                                     "c": [["", [], []], "viewof x = 1"]}]), [])


class AlignAndGroupTests(unittest.TestCase):
    def test_contiguous_disagreements_become_one_run(self):
        pdf = [pdf_word("in", italic=True), pdf_word("america", italic=True)]
        qmd = [qmd_word("in"), qmd_word("america")]
        runs = emphasis.group_runs(emphasis.align(pdf, qmd), pdf, qmd)
        self.assertEqual(len(runs), 1)
        self.assertEqual(len(runs[0]["pdf"]), 2)

    def test_a_matching_word_between_two_breaks_the_run(self):
        pdf = [pdf_word("a", italic=True), pdf_word("b"), pdf_word("c", italic=True)]
        qmd = [qmd_word("a"), qmd_word("b"), qmd_word("c")]
        runs = emphasis.group_runs(emphasis.align(pdf, qmd), pdf, qmd)
        self.assertEqual(len(runs), 2)

    def test_a_context_change_breaks_a_run(self):
        """Without this, a lost italic ending a paragraph merges with the
        bold heading after it and `header` explains both away."""
        pdf = [pdf_word("lost", italic=True), pdf_word("title", bold=True)]
        qmd = [qmd_word("lost"), qmd_word("title", ctx=["header"])]
        runs = emphasis.group_runs(emphasis.align(pdf, qmd), pdf, qmd)
        self.assertEqual(len(runs), 2)

    def test_kinds(self):
        def kind(pdf, qmd):
            found = emphasis._disagreement(pdf, qmd)
            return found[0] if found else None

        self.assertEqual(kind(pdf_word("x", italic=True), qmd_word("x")), "lost")
        self.assertEqual(kind(pdf_word("x"), qmd_word("x", italic=True)), "added")
        self.assertEqual(
            kind(pdf_word("x", italic=True), qmd_word("x", bold=True)), "swapped")
        self.assertIsNone(
            kind(pdf_word("x", italic=True), qmd_word("x", italic=True)))

    def test_unaligned_words_produce_no_runs(self):
        """8% of PDF words don't align corpus-wide. They are a blind spot, not
        a finding — emphasis in them is simply not checked."""
        pdf = [pdf_word("orphan", italic=True)]
        qmd = [qmd_word("different")]
        self.assertEqual(emphasis.group_runs(emphasis.align(pdf, qmd), pdf, qmd), [])


class ExplainTests(unittest.TestCase):
    """The allowlist. Every rule here suppresses findings, so each gets a test
    that it fires and the broad ones a test that they stop where they should."""

    def test_unexplained_run_is_a_finding(self):
        self.assertEqual(
            emphasis.explain("lost", [pdf_word("help", italic=True)],
                             [qmd_word("help")]),
            [])

    def test_styled_class_explains_a_lost_run(self):
        self.assertIn(
            "css:deming_quote",
            emphasis.explain("lost", [pdf_word("x", italic=True)],
                             [qmd_word("x", ctx=["deming_quote"])]))

    def test_unlisted_class_does_not_explain(self):
        self.assertEqual(
            emphasis.explain("lost", [pdf_word("x", italic=True)],
                             [qmd_word("x", ctx=["some_new_class"])]),
            [])

    def test_header_and_table_header_explain(self):
        self.assertIn("header", emphasis.explain(
            "lost", [pdf_word("x", bold=True)], [qmd_word("x", ctx=["header"])]))
        self.assertIn("table-header", emphasis.explain(
            "lost", [pdf_word("x", bold=True)], [qmd_word("x", ctx=["th"])]))

    def test_math_explains_both_directions(self):
        """MathJax italicises `$n$` without the .qmd saying so, and Neave's
        source sets the same variable in an italic font. 285 of Optional
        Extras' 379 raw lost runs were this."""
        self.assertIn("math", emphasis.explain(
            "lost", [pdf_word("n", italic=True)], [qmd_word("n", ctx=["math"])]))
        self.assertIn("math", emphasis.explain(
            "added", [pdf_word("n")], [qmd_word("n", ctx=["math"], italic=True)]))

    def test_neave_note_rule_needs_a_long_run(self):
        """Neave's long asides are carried by the class; short emphasis
        *inside* one is still real and must survive."""
        long_run = [qmd_word("w", ctx=["neave_note"])] * emphasis.NEAVE_NOTE_MIN_WORDS
        self.assertIn("neave-note-aside", emphasis.explain(
            "lost", [pdf_word("w", italic=True)] * len(long_run), long_run))
        short_run = [qmd_word("w", ctx=["neave_note"])]
        self.assertEqual(
            emphasis.explain("lost", [pdf_word("w", italic=True)], short_run), [])

    def test_checklist_labels_explain_an_added_run(self):
        self.assertIn("checklist-label", emphasis.explain(
            "added", [pdf_word("point", raw="POINT")],
            [qmd_word("point", raw="POINT", bold=True)]))

    def test_checklist_rule_does_not_reach_ordinary_words(self):
        self.assertNotIn("checklist-label", emphasis.explain(
            "added", [pdf_word("system", raw="system")],
            [qmd_word("system", raw="system", bold=True)]))

    # ── colour's direction (#846) ──

    def test_colour_explains_an_added_run(self):
        """Deming's quotations are blue and upright in the source, italic on
        the site. That is the site's convention, not an addition."""
        self.assertIn("deming-quote-colour", emphasis.explain(
            "added", [pdf_word("x", coloured=True)], [qmd_word("x", italic=True)]))

    def test_colour_never_explains_a_lost_run(self):
        """A coloured word whose italics the site dropped is still a defect —
        #823's `in America` is both blue and bold, and a genuine loss."""
        self.assertEqual(
            emphasis.explain("lost", [pdf_word("x", italic=True, coloured=True)],
                             [qmd_word("x")]),
            [])

    def test_colour_alone_creates_no_finding(self):
        """Colour-only emphasis is out of scope and stays a human-auditor
        blind spot: a coloured but unstyled word matching an unstyled word is
        not a disagreement at all."""
        self.assertIsNone(emphasis._disagreement(
            pdf_word("results", coloured=True), qmd_word("results")))


class CompareTests(unittest.TestCase):
    def test_counts_exclude_explained_runs(self):
        pdf = [pdf_word("lost", italic=True), pdf_word("heading", bold=True)]
        qmd = [qmd_word("lost"), qmd_word("heading", ctx=["header"])]
        # These are adjacent, but their contexts differ, so they are two runs:
        # see test_a_context_change_breaks_a_run.
        record = emphasis.Record("test", "/nonexistent.pdf", "/tmp", [])
        stats, findings = emphasis.compare(record, pdf_stream=pdf, qmd_stream=qmd)
        self.assertEqual(stats["lost"], 1)
        self.assertEqual(stats["runs_total"], 2)
        self.assertEqual(stats["runs_explained"], 1)
        self.assertEqual(len(findings), 2)

    def test_swapped_is_counted_apart_from_lost(self):
        """#846 decided swapped gets its own class: the 29 corpus-wide runs
        have never been sampled systematically and must not inflate `lost`,
        whose precision was measured at 40/40."""
        pdf = [pdf_word("yes", italic=True)]
        qmd = [qmd_word("yes", bold=True)]
        record = emphasis.Record("test", "/nonexistent.pdf", "/tmp", [])
        stats, _ = emphasis.compare(record, pdf_stream=pdf, qmd_stream=qmd)
        self.assertEqual((stats["swapped"], stats["lost"], stats["added"]),
                         (1, 0, 0))


MIXED_XML = """<?xml version="1.0" encoding="UTF-8"?>
<pdf2xml>
<page number="1" position="absolute" top="0" left="0" height="1188" width="918">
<fontspec id="0" size="11" family="Cambria" color="#000000"/>
<text top="100" left="50" width="60" height="14" font="0"><b>outcome</b>s,</text>
<text top="130" left="50" width="60" height="14" font="0"><i>two</i>-minute</text>
<text top="160" left="50" width="60" height="14" font="0">plain<i>,</i></text>
</page>
</pdf2xml>
"""


class ProfileTests(unittest.TestCase):
    """The per-letter profile, which replaced the majority-of-letters rule.

    The old rule styled a whole word by whichever style most of its letters
    carried, so a word Neave emphasised only part of was reported as whatever
    the longer half was — #850. A profile has no majority to take.
    """

    def test_the_folded_form_is_the_one_the_streams_align_on(self):
        """profile() has to fold exactly as norm() does, letter for letter,
        or a profile would not line up with the word it describes and the
        position-by-position comparison in _disagreement would be nonsense."""
        for word in ("Deming", "na\u00efve", "\u201cif\u201d", "Rule-4", "\ufb01nish",
                     "\u2026", "H2O", "don\u2019t"):
            folded, styles = emphasis.profile((c, False, False) for c in word)
            self.assertEqual(folded, emphasis.norm(word), word)
            self.assertEqual(len(styles), len(folded), word)

    def test_punctuation_carries_no_position(self):
        """The case the majority rule existed to handle — "a trailing italic
        comma should not make the word italic" — now needs no rule: the comma
        folds away and never enters the profile at all."""
        folded, styles = emphasis.profile(
            [("h", False, False), ("i", False, False), (",", False, True)])
        self.assertEqual(folded, "hi")
        self.assertEqual(styles, ((False, False), (False, False)))


class MixedStyleWordTests(unittest.TestCase):
    """#850: a word whose letters do not agree, on either side of the compare.

    These are the cases that made the two streams disagree about what a word
    *was*. Each one is a shape measured in the corpus, not a hypothetical.
    """

    def setUp(self):
        self.by_name = {w["n"]: w for w in emphasis.pdf_words(None, xml=MIXED_XML)}

    # ── the PDF side keeps the printed word whole ──

    def test_a_mixed_style_word_stays_one_token(self):
        """Splitting it — #850's option 1 — was built and measured: it moves
        `outcomes,` from reported to unaligned, because the site has one word
        there and difflib then matches neither half."""
        self.assertIn("outcomes", self.by_name)
        self.assertNotIn("outcome", self.by_name)

    def test_the_profile_says_which_letters_are_emphasised(self):
        bold, plain = (True, False), (False, False)
        self.assertEqual(self.by_name["outcomes"]["styles"],
                         (bold,) * 7 + (plain,))

    def test_a_trailing_italic_comma_still_does_not_italicise_the_word(self):
        self.assertEqual(set(self.by_name["plain"]["styles"]), {(False, False)})

    # ── the .qmd side joins what has no space between it ──

    def test_adjacent_inlines_with_no_space_are_one_word(self):
        """`*two*-minute` is Emph + Str with nothing between them. Emitting
        per node gave two tokens against the PDF's one, so the site's own
        *correct* markup was what broke the alignment."""
        words = walk_qmd([{"t": "Para", "c": [
            {"t": "Emph", "c": [{"t": "Str", "c": "two"}]},
            {"t": "Str", "c": "-minute"}]}])
        self.assertEqual([w["n"] for w in words], ["twominute"])
        self.assertEqual(words[0]["styles"],
                         ((False, True),) * 3 + ((False, False),) * 6)

    def test_the_two_sides_now_produce_the_same_token(self):
        """The whole refactor in one assertion: the printed word and the
        marked-up word are the same alignment unit, whatever the markup."""
        from_pdf = self.by_name["twominute"]
        from_qmd = walk_qmd([{"t": "Para", "c": [
            {"t": "Emph", "c": [{"t": "Str", "c": "two"}]},
            {"t": "Str", "c": "-minute"}]}])[0]
        self.assertEqual(from_pdf["n"], from_qmd["n"])
        self.assertEqual(from_pdf["styles"], from_qmd["styles"])

    def test_a_space_node_still_ends_a_word(self):
        words = walk_qmd([{"t": "Para", "c": [
            {"t": "Str", "c": "two"}, {"t": "Space"},
            {"t": "Str", "c": "minute"}]}])
        self.assertEqual([w["n"] for w in words], ["two", "minute"])

    def test_a_word_cannot_span_two_blocks(self):
        """Nothing separates the last Str of one paragraph from the first of
        the next, so without a flush at the block boundary they would join."""
        words = walk_qmd([
            {"t": "Para", "c": [{"t": "Str", "c": "end"}]},
            {"t": "Para", "c": [{"t": "Str", "c": "start"}]}])
        self.assertEqual([w["n"] for w in words], ["end", "start"])

    def test_a_footnote_does_not_glue_to_the_word_it_hangs_off(self):
        words = walk_qmd([{"t": "Para", "c": [
            {"t": "Str", "c": "word"},
            {"t": "Note", "c": [{"t": "Para", "c": [{"t": "Str", "c": "aside"}]}]},
            {"t": "Space"},
            {"t": "Str", "c": "next"}]}])
        self.assertEqual([w["n"] for w in words], ["word", "aside", "next"])


class PartialFindingTests(unittest.TestCase):
    """What a partial disagreement reports, end to end."""

    @staticmethod
    def run_compare(pdf, qmd):
        record = emphasis.Record("test", "/nonexistent.pdf", "/tmp", [])
        return emphasis.compare(record, pdf_stream=pdf, qmd_stream=qmd)

    def test_a_partial_emphasis_the_site_dropped_is_still_reported(self):
        """Day 3 printed page 53 (PDF p57): `outcome` is bold and `s,` roman
        inside one printed word, and the site has it plain. That is card
        E3-F19 from #849 — adjudicated by hand, kept deliberately, and
        written up as item 2 of
        docs/deviations/2026-09-22-day-03-emphasis-differences-kept.md.

        It is the measurement that ruled out splitting the PDF word, so it is
        the one case this refactor is not allowed to lose.
        """
        stats, findings = self.run_compare(
            [mixed("outcomes", "bbbbbbb.", raw="outcomes,")],
            [qmd_word("outcomes")])
        self.assertEqual(stats["lost"], 1)
        self.assertEqual(findings[0]["kind"], "lost")
        self.assertEqual(findings[0]["marked"], "\u00aboutcome\u00bbs,")
        self.assertTrue(findings[0]["partial"])

    def test_a_partial_emphasis_the_site_kept_is_not_a_finding(self):
        """`*two*-minute`: the site has exactly what Neave set. Before #850
        this was a false `lost` on the whole compound, and the mechanical
        proposal would have italicised the hyphen and `minute` too."""
        stats, findings = self.run_compare(
            [mixed("twominute", "iii......", raw="two-minute")],
            [mixed("twominute", "iii......", raw="two-minute")])
        self.assertEqual(findings, [])
        self.assertEqual((stats["lost"], stats["added"], stats["swapped"]),
                         (0, 0, 0))

    def test_a_minority_emphasis_is_no_longer_invisible(self):
        """3 of 9 letters italic. The majority rule called the whole word
        upright, it matched the site's upright word, and the loss was never
        offered for comparison — the recall gap #850 was opened for."""
        stats, findings = self.run_compare(
            [mixed("twominute", "iii......", raw="two-minute")],
            [qmd_word("twominute", raw="two-minute")])
        self.assertEqual(stats["lost"], 1)
        self.assertEqual(findings[0]["marked"], "\u00abtwo\u00bb-minute")

    def test_the_style_label_describes_the_letters_that_disagree(self):
        """Not the whole word: for a minority italic the word is mostly
        upright, and reporting `pdf=-` on a `lost` run would contradict
        itself."""
        _, findings = self.run_compare(
            [mixed("twominute", "iii......", raw="two-minute")],
            [qmd_word("twominute", raw="two-minute")])
        self.assertEqual(findings[0]["pdf_style"], "i")
        self.assertEqual(findings[0]["qmd_style"], "-")

    def test_a_whole_word_finding_is_not_partial(self):
        """The shape every finding had before #850, and still the common one:
        `partial` has to stay false there or it means nothing."""
        _, findings = self.run_compare([pdf_word("help", italic=True)],
                                       [qmd_word("help")])
        self.assertFalse(findings[0]["partial"])
        self.assertEqual(findings[0]["marked"], "help",
                         "a whole-word finding needs no marks, and putting "
                         "them on every word of a run is noise")
        self.assertNotIn("partial-word", findings[0]["notes"])


class RecordTests(unittest.TestCase):
    def test_day_numbers_outside_the_course_are_refused(self):
        with self.assertRaises(emphasis.RecordError):
            emphasis.resolve("13")

    def test_record_names_are_constrained(self):
        with self.assertRaises(emphasis.RecordError):
            emphasis.resolve("../../etc/passwd")

    def test_all_records_covers_every_manifest(self):
        """A manifest that exists but is never run is a check that silently
        does not cover a page — the shape of #802."""
        names = emphasis.all_records()
        self.assertEqual([n for n in names if n.isdigit()],
                         [str(d) for d in range(1, 13)])
        for expected in ("appendix-main", "appendix-optional-extras",
                         "appendix-contributions-balaji-reddie",
                         "appendix-references", "index", "welcome"):
            self.assertIn(expected, names)
        self.assertFalse([n for n in names if n.startswith("day-")],
                         "day manifests are reached by number, not by name")


class AllowlistTests(unittest.TestCase):
    def test_every_styled_class_really_sets_bold_or_italic(self):
        """An entry here suppresses findings wherever it appears, so it has to
        be earned. `neave_note` is deliberately absent — it styles the block,
        not the words, which is why it needs the separate long-run rule."""
        css = (REPO_ROOT / "assets" / "styles" / "main.css").read_text()
        for name in emphasis.STYLED_CLASSES:
            with self.subTest(css_class=name):
                blocks = [b for b in css.split("}")
                          if re.search(rf"\.{re.escape(name)}(?![\w-])", b)]
                self.assertTrue(
                    any(re.search(r"font-(weight|style)\s*:\s*(bold|italic|[6-9]00)", b)
                        for b in blocks),
                    f".{name} is in STYLED_CLASSES but sets no bold/italic in main.css")

    def test_neave_note_is_not_a_styled_class(self):
        self.assertNotIn(emphasis.NEAVE_NOTE_CLASS, emphasis.STYLED_CLASSES)


class VersionTests(unittest.TestCase):
    LIB = REPO_ROOT / "scripts" / "lib" / "emphasis-version.sh"

    def files(self):
        body = re.search(r"^EMPHASIS_VERSION_FILES=\((.*?)^\)",
                         self.LIB.read_text(), re.MULTILINE | re.DOTALL).group(1)
        return re.findall(r"^\s*(\S+)\s*$", body, re.MULTILINE)

    def test_every_listed_file_exists(self):
        for rel in self.files():
            with self.subTest(file=rel):
                self.assertTrue((REPO_ROOT / rel).is_file())

    def test_checker_modules_are_covered(self):
        listed = set(self.files())
        for required in ("scripts/lib/emphasis.py", "scripts/check-emphasis.py"):
            self.assertIn(required, listed)

    def test_version_is_stable_and_order_independent(self):
        def compute(snippet):
            return subprocess.run(
                ["bash", "-c", f'set -euo pipefail\n. "{self.LIB}"\n{snippet}'],
                capture_output=True, text=True, cwd=REPO_ROOT)
        first = compute('compute_emphasis_version "$PWD"')
        self.assertEqual(first.returncode, 0, first.stderr)
        reversed_list = compute(
            'EMPHASIS_VERSION_FILES=('
            + " ".join(reversed(self.files()))
            + ')\ncompute_emphasis_version "$PWD"')
        self.assertEqual(first.stdout.strip(), reversed_list.stdout.strip())

    def test_empty_list_is_refused_rather_than_hashed(self):
        result = subprocess.run(
            ["bash", "-c",
             f'. "{self.LIB}"\nEMPHASIS_VERSION_FILES=()\n'
             'compute_emphasis_version "$PWD"'],
            capture_output=True, text=True, cwd=REPO_ROOT)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
