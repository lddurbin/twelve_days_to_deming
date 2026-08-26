"""Tests for scripts/lib/pdf_callouts.py — the PDF side's footnote apparatus.

Issue #755 closed the last of the ten false-positive categories in #732's Day
9 triage. What makes this module different from the other four in the pipeline
is that its rule is *dangerous by construction*: it takes a letter off the end
of a word, which is precisely the shape of the defects the comparator exists
to catch. `extractd` -> `extract` is a callout; `reasons` -> `reason`, `off` ->
`of` and `managed` -> `manage` are transcription defects, and nothing about
their shape tells them apart.

So the tests below are weighted the other way from the rest of the suite.
CalloutFixtureTests pins the sixteen occurrences the rule is *for*, but
RefusalTests is the load-bearing half: one case per bound, each built from
real corpus text, asserting that the strip does *not* happen. If a later edit
loosens a bound, the failure will name the real word it started eating.

KnownLimitTests states the one thing the rule cannot rule out, so it is a
recorded limit rather than something to be rediscovered.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

from paragraph_similarity import normalise  # noqa: E402
from pdf_callouts import (  # noqa: E402
    callout_letters,
    is_callout,
    strip_callouts,
    vocabulary,
)

MODULE = REPO_ROOT / "scripts" / "lib" / "pdf_callouts.py"


def approvals(*letters: str) -> str:
    """An *Approvals, Acknowledgments and Information* block defining `letters`.

    The shape `pdftotext` produces from the real pages: the heading, then each
    definition's letter alone on a line above its prose. Day 9's is the model.
    """
    entries = "\n".join(
        f"{letter}\n(page {n}) Reproduced with the approval of the publisher."
        for n, letter in enumerate(letters, start=1)
    )
    return f"Approvals, Acknowledgments and Information\n\n{entries}\n"


def stripped(pdf_body: str, qmd: str, *letters: str) -> str:
    """`pdf_body` run through the rule, for a day defining `letters`.

    Returns just the body — the appended Approvals block is dropped again, so a
    fixture reads as the sentence it is about.
    """
    pdf = f"{pdf_body}\n\n{approvals(*letters)}"
    return strip_callouts(pdf, qmd).split("\n\n")[0]


class CalloutLetterTests(unittest.TestCase):
    """A day's live callout letters come from that day's own Approvals block."""

    def test_letters_are_read_in_order(self):
        self.assertEqual(callout_letters(approvals("a", "b", "c")), ["a", "b", "c"])

    def test_a_day_with_no_approvals_block_defines_nothing(self):
        """Five of the twelve days (2, 4, 8, 10, 12) carry no such block at all."""
        self.assertEqual(callout_letters("Ordinary prose with no footnotes in it.\n"), [])

    def test_both_spellings_of_the_heading_are_accepted(self):
        """Neave writes "Acknowledgments" in the heading and "Acknowledgements" elsewhere."""
        self.assertEqual(
            callout_letters("Approvals, Acknowledgements and Information\n\na\n(page 1) Photo.\n"),
            ["a"],
        )

    def test_reading_stops_at_the_symbol_font_footer(self):
        """`pdftotext` renders the page footer as punctuation runs. Nothing past it counts."""
        block = approvals("a") + '\n!!!!!!!!!"#$!%!!&!!\'#()!%&!\n\nb\n'
        self.assertEqual(callout_letters(block), ["a"])

    def test_a_definition_missing_its_page_line_is_still_a_letter(self):
        """Day 1's `b` has no `(page N)` line — the two shapes are not reliably paired."""
        block = (
            "Approvals, Acknowledgments and Information\n\n"
            "a\n(page 1) Photo by courtesy of SPC Press Inc.\nb\nc\n(page 18) On 6 July 1989.\n"
        )
        self.assertEqual(callout_letters(block), ["a", "b", "c"])

    def test_prose_naming_the_section_is_not_a_heading(self):
        """Day 1's overture mentions the section mid-sentence; that must not define letters."""
        prose = (
            'superscript letters as a refer to the “Approvals, Acknowledgements and '
            'Information” at the end of the file.)\n'
        )
        self.assertEqual(callout_letters(prose), [])


class CalloutFixtureTests(unittest.TestCase):
    """The sixteen real occurrences, verbatim from the twelve source PDFs.

    Nine glued to a word, seven to a closing quotation mark — and since the
    whole point is that both sides end up saying the same thing, each asserts
    the normalised PDF sentence matches the transcription rather than merely
    that a character went missing.
    """

    def assert_agrees(self, pdf_body, qmd, *letters):
        self.assertEqual(normalise(stripped(pdf_body, qmd, *letters)), normalise(qmd))

    def test_day_1_extractd(self):
        self.assert_agrees(
            "Here’s a brief extractd from that page (in which I wish the first few words "
            "were really true)",
            "Here’s a brief extract from that page (in which I wish the first few words "
            "were really true)",
            "a", "b", "c", "d", "e", "f",
        )

    def test_day_1_medalb(self):
        self.assert_agrees(
            "The inscription near the bottom of the medalb is a quotation from Dr Deming",
            "The inscription near the bottom of the medal is a quotation from Dr Deming",
            "a", "b", "c", "d", "e", "f",
        )

    def test_day_1_demingf(self):
        self.assert_agrees(
            "the superb biography The World of W Edwards Demingf): “The lectures are being held",
            "the superb biography The World of W Edwards Deming): “The lectures are being held",
            "a", "b", "c", "d", "e", "f",
        )

    def test_day_3_numbera(self):
        self.assert_agrees(
            "around page 30 depending on the edition and reprint numbera).",
            "around page 30 depending on the edition and reprint number).",
            "a", "b",
        )

    def test_day_3_controlb(self):
        self.assert_agrees(
            "his book with David Chambers: Understanding Statistical Process Controlb.",
            "his book with David Chambers: Understanding Statistical Process Control.",
            "a", "b",
        )

    def test_day_6_finda(self):
        self.assert_agrees(
            "these were the best short summaries of this report that I could finda)",
            "these were the best short summaries of this report that I could find)",
            "a", "b",
        )

    def test_day_9_improvementb(self):
        self.assert_agrees(
            "The diagram that follows (from Bill Scherkenbach’s Deming’s Road to Continual "
            "Improvementb page 10) is conceptual, rather than being intended as a model!",
            "The diagram that follows (from Bill Scherkenbach’s Deming’s Road to Continual "
            "Improvement page 10) is conceptual, rather than being intended as a model!",
            "a", "b", "c",
        )

    def test_day_11_demingb(self):
        self.assert_agrees(
            "It is an extract from Chapter 7: “Management is Prediction” on page 263 of "
            "The Essential Demingb.",
            "It is an extract from Chapter 7: “Management is Prediction” on page 263 of "
            "The Essential Deming.",
            "a", "b", "c",
        )

    def test_day_11_diagramc(self):
        self.assert_agrees(
            "Bill rightly claims that this seven-word diagramc really represents a complete "
            "theory of knowledge.",
            "Bill rightly claims that this seven-word diagram really represents a complete "
            "theory of knowledge.",
            "a", "b", "c",
        )

    def test_a_callout_after_a_closing_quote(self):
        """Day 9's `care.”c` — punctuation, so no stem and no vocabulary to test."""
        self.assert_agrees(
            "The reader, after study of the rest of this paper, might wish to try to "
            "construct a system of medical care.”c",
            "The reader, after study of the rest of this paper, might wish to try to "
            "construct a system of medical care.”",
            "a", "b", "c",
        )

    def test_a_callout_after_a_closing_quote_mid_paragraph(self):
        """Day 7's `calls.”a`, which had been holding a real `fake`/`false` defect under the band."""
        self.assert_agrees(
            "and the £197,000 cost of the fake calls.”a",
            "and the £197,000 cost of the fake calls.”",
            "a",
        )

    def test_a_callout_on_a_heading(self):
        """Day 6's `Westminster”b` — no sentence punctuation before the quote at all."""
        self.assert_agrees(
            "Transcript from “The Week in Westminster”b",
            "Transcript from “The Week in Westminster”",
            "a", "b",
        )

    def test_a_callout_on_a_line_wrapped_word(self):
        """`pdftotext` breaks words at hyphens; normalise() rejoins them, so this must see the whole word.

        Not one of the seventeen — no real callout happens to land on a wrapped
        word — but the rule has to be right about it either way, because the
        contrary case (`contri- bute`) is real and is what this guards.
        """
        self.assertEqual(
            normalise(stripped("the reprint num- bera)", "the reprint number)", "a", "b")),
            normalise("the reprint number)"),
        )


class RefusalTests(unittest.TestCase):
    """One case per bound. Every one of these is a word, not a callout."""

    def assert_untouched(self, pdf_body, qmd, *letters):
        self.assertEqual(stripped(pdf_body, qmd, *letters), pdf_body)

    def test_a_real_one_letter_substitution_still_flags(self):
        """Day 11: the source reads "rea- sons", the site "reason".

        Five lines from `diagramc` in the same near-certain band, and the reason
        this rule cannot be a shape rule. Day 11 defines `a`, `b`, `c`; `s` is
        not one of them, and the site writes "reasons" elsewhere in the day
        besides.
        """
        pdf = "Deming never said or wrote anything without good rea- sons."
        qmd = "Deming never said or wrote anything without good reason. There are reasons for that."
        self.assertEqual(stripped(pdf, qmd, "a", "b", "c"), pdf)
        self.assertNotEqual(normalise(stripped(pdf, qmd, "a", "b", "c")), normalise(qmd))

    def test_off_is_not_of_plus_a_callout(self):
        """Day 1's callout set runs to `f`, and its QMD writes "off" six times."""
        self.assert_untouched(
            "So off you go to Stage 6 on page 44.",
            "So of you go to Stage 6 on page 44. Six times off appears elsewhere.",
            "a", "b", "c", "d", "e", "f",
        )

    def test_managed_is_not_manage_plus_a_callout(self):
        self.assert_untouched(
            "the way the organisation is managed",
            "the way the organisation is manage. Elsewhere the site writes managed.",
            "a", "b", "c", "d", "e", "f",
        )

    def test_theme_is_not_them_plus_a_callout(self):
        """Both words are real Day 1 vocabulary; the QMD veto is what separates them."""
        self.assert_untouched(
            "a theme running through the whole course",
            "a theme running through the whole course",
            "a", "b", "c", "d", "e", "f",
        )

    def test_the_stem_must_be_a_word(self):
        """`board` -> `boar` is refused before the veto is reached: Day 1's QMD has neither word."""
        self.assert_untouched(
            "the members of the board were unconvinced",
            "the members of the group were unconvinced",
            "a", "b", "c", "d", "e", "f",
        )

    def test_the_letter_must_be_one_the_day_defines(self):
        """Day 5 defines `a` alone, so its own `b` through `f` are protected."""
        self.assert_untouched(
            "the entry in Dr Deming’s diary quoted above",
            "the entry in Dr Deming’s diary quoted below",
            "a",
        )

    def test_a_running_head_prefix_is_not_a_callout(self):
        """Days 4-7 open "G DAY 4:", "H DAY 5:", "I DAY 6:", "J DAY 7:".

        The letter is `pdftotext`'s rendering of the source file's own prefix
        (G=Day 4 … J=Day 7), it flags in the same near-certain band as the
        callouts, and it is the same shape. No day defines a callout past `f`,
        which is what keeps it safe.
        """
        self.assert_untouched(
            "G DAY 4: THE JOINER TRIANGLE and THE 14 POINTS (part 1)",
            "DAY 4: THE JOINER TRIANGLE AND THE 14 POINTS (part 1)",
            "a",
        )

    def test_a_degree_sign_is_not_a_callout(self):
        """Day 2's `44o` is how `pdftotext` renders 44°, and Day 2 defines no callouts at all."""
        self.assertEqual(
            strip_callouts("holding it at a specified angle of 44o to the horizontal", ""),
            "holding it at a specified angle of 44o to the horizontal",
        )

    def test_a_short_stem_is_refused(self):
        """`inc`, `ka`, `oa`, `ab` are `pdftotext` debris, not callouts."""
        self.assert_untouched("SPC Press Inc and others", "SPC Press In and others", "a", "b", "c")

    def test_an_apostrophe_is_not_a_closing_quote(self):
        """`they’d`, `you’d`, `he’d` and `I’d` all match the quote shape on Day 1."""
        self.assert_untouched(
            "they’d never been able to attend before",
            "they’d never been able to attend before",
            "a", "b", "c", "d", "e", "f",
        )

    def test_an_abbreviation_is_not_a_callout(self):
        """`i.e.` and `c.f.` are 15 of the 20 raw matches a full-stop rule would make on Day 1."""
        self.assert_untouched(
            "around Dr Deming’s 90th birthday, i.e. in 1990 and 1991",
            "around Dr Deming’s 90th birthday, i.e. in 1990 and 1991",
            "a", "b", "c", "d", "e", "f",
        )

    def test_a_hyphen_wrapped_word_is_seen_whole(self):
        """"contri- bute" is `contribute`, not `but` plus a callout `e`."""
        self.assert_untouched(
            "I would ask the delegates to contri- bute very little",
            "I would ask the delegates to contribute very little",
            "a", "b", "c", "d", "e", "f",
        )

    def test_a_page_marker_is_left_alone(self):
        """Structural, not prose — nothing in it is ever a callout (see paragraphs.py).

        The letters are chosen so the marker would lose characters if it were
        treated as prose: `pdf-page` hyphen-joins to `pdfpage`, whose stem is
        made attested here, and `50` sits beside a `page` the QMD never writes.
        """
        pdf = f"A pdfpag heading.\n@@pdf-page 50@@\nMore prose.\n\n{approvals('a', 'b', 'c', 'd', 'e')}"
        self.assertIn("@@pdf-page 50@@", strip_callouts(pdf, "A heading. More prose."))

    def test_an_opening_straight_quote_keeps_the_word_after_it(self):
        """`pdftotext` renders real quotes typographically; a straight `"` is page furniture.

        The quote branch carries none of the four bounds, so an opening
        straight quote in the class would eat the first letter of whatever
        followed it.
        """
        self.assert_untouched(
            '"a system of profound knowledge" is what he called it',
            "a system of profound knowledge is what he called it",
            "a", "b", "c",
        )


class KnownLimitTests(unittest.TestCase):
    """What the rule cannot rule out, recorded rather than left to be found."""

    def test_the_qmd_veto_can_only_refuse_a_strip(self):
        """The one direction the transcription can influence the source's reading."""
        pdf = "the reprint numbera)"
        self.assertEqual(stripped(pdf, "the reprint number)", "a"), "the reprint number)")
        self.assertEqual(stripped(pdf, "the reprint numbera)", "a"), pdf)

    def test_a_dropped_letter_on_a_word_used_nowhere_else_would_be_missed(self):
        """If the site drops a callout letter's twin from a word it never repeats.

        `pictured` -> `picture` is a real defect, `d` is a Day 1 callout letter,
        and if "pictured" appears nowhere else in the day's transcription then
        all four bounds are satisfied and the source is read as carrying a
        callout. The stem-attested bound is what keeps this narrow — it takes a
        defect that leaves a real word behind — but it does not close it.
        """
        pdf = "Dr W Edwards Deming, pictured above left, aged 88"
        qmd = "Dr W Edwards Deming, picture above left, aged 88"
        self.assertEqual(
            stripped(pdf, qmd, "a", "b", "c", "d"),
            "Dr W Edwards Deming, picture above left, aged 88",
        )


class HelperTests(unittest.TestCase):
    def test_vocabulary_de_hyphenates_and_lowercases(self):
        self.assertEqual(vocabulary("Contri- bute\nMEDAL"), {"contribute", "medal"})

    def test_vocabulary_drops_digits(self):
        """A vocabulary is a set of words: "44o" contributes `o`, not `44o`."""
        self.assertEqual(vocabulary("angle of 44o"), {"angle", "of", "o"})

    def test_is_callout_needs_all_four_bounds(self):
        letters, pdf_words, qmd_words = {"b"}, {"medal", "medalb"}, {"medal"}
        self.assertTrue(is_callout("medalb", letters, pdf_words, qmd_words))
        self.assertFalse(is_callout("medalb", {"a"}, pdf_words, qmd_words))
        self.assertFalse(is_callout("medalb", letters, pdf_words, {"medal", "medalb"}))
        self.assertFalse(is_callout("medalb", letters, set(), set()))
        self.assertFalse(is_callout("orb", letters, {"or"}, {"or"}))


class CliTests(unittest.TestCase):
    def run_cli(self, *args, stdin=""):
        return subprocess.run(
            [sys.executable, str(MODULE), *args],
            capture_output=True, text=True, input=stdin, cwd=REPO_ROOT,
        )

    def test_letters_flag_lists_the_days_callouts(self):
        result = self.run_cli("--letters", stdin=approvals("a", "b", "c"))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.split(), ["a", "b", "c"])

    def test_stripping_reads_the_qmd_text_from_a_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            qmd = Path(tmp) / "qmd.txt"
            qmd.write_text("the bottom of the medal is a quotation\n", encoding="utf-8")
            pdf = f"the bottom of the medalb is a quotation\n\n{approvals('a', 'b')}"
            result = self.run_cli(str(qmd), stdin=pdf)
        self.assertEqual(result.returncode, 0)
        self.assertIn("the bottom of the medal is a quotation", result.stdout)

    def test_no_arguments_is_a_usage_error(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Usage:", result.stderr)


class ValidatorIntegrationTests(unittest.TestCase):
    """The orchestration side, including the one ordering constraint."""

    def setUp(self):
        self.script = (REPO_ROOT / "scripts" / "validate-transcription.sh").read_text(
            encoding="utf-8"
        )

    def test_the_pdf_side_runs_this_module(self):
        self.assertIn('pdf_callouts.py" "$qmd_text"', self.script)

    def test_the_qmd_text_is_extracted_before_the_pdf_text(self):
        """The rule reads the transcription, so the QMD extraction has to run first.

        Nothing else in the pipeline depends on that order, which is exactly
        why it is easy to reverse by accident while tidying main().
        """
        self.assertLess(
            self.script.index("Extracting QMD text..."),
            self.script.index("Extracting PDF text..."),
        )

    def test_an_extraction_failure_is_not_swallowed(self):
        self.assertIn("PDF text extraction failed", self.script)

    def test_the_module_is_in_the_scorer_version(self):
        """It changes what a run reports, so a stale result must not read fresh."""
        version = (REPO_ROOT / "scripts" / "lib" / "scorer-version.sh").read_text(encoding="utf-8")
        self.assertIn("scripts/lib/pdf_callouts.py", version)


if __name__ == "__main__":
    unittest.main()
