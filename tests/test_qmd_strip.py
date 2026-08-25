"""Tests for scripts/lib/qmd_strip.py — the QMD side of the comparison.

Issue #739 moved this out of an untested awk + sed pipeline in
validate-transcription.sh. The stakes are asymmetric in a way worth stating:
markup this module fails to strip does not make the validator miss a defect,
it makes the validator *invent* one — a junk token inside a faithful sentence
depresses its score and produces a flagged "altered" line that no proofreading
pass can clear, because the transcription is correct. Day 9's triage found 55
of its 62 residual near-certain flags were that (#732).

FalsePositiveCategoryTests below is the centrepiece: one case per category in
that triage, each built from the real PDF and QMD text rather than an
invented example, so a future edit that reopens one of them fails here with
the actual sentence that used to break. Five categories are closed by this
module and assert that the two sides now normalise identically. The other
five are not this module's to close — they are artifacts of `pdftotext`, or
deliberate — and assert the *residual* difference instead, naming the issue
that owns it. A fixture asserting a difference is still a regression test: it
fails if someone later strips the wrong thing.

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
from qmd_strip import (  # noqa: E402
    main,
    resolve_brackets,
    strip_qmd,
    strip_workbook_refs,
    strip_workbook_refs_line,
)

MODULE = REPO_ROOT / "scripts" / "lib" / "qmd_strip.py"
VALIDATOR = REPO_ROOT / "scripts" / "validate-transcription.sh"


def prose(qmd: str) -> str:
    """What the scorer actually compares: stripped, then normalised."""
    return normalise(strip_qmd(qmd))


def pdf_prose(pdf: str) -> str:
    """The PDF side of the same comparison, workbook citations removed."""
    return normalise(strip_workbook_refs(pdf))


class BracketConstructTests(unittest.TestCase):
    """The four bracket shapes, and the one that is content rather than markup."""

    def test_link_keeps_its_visible_text(self):
        self.assertEqual(
            resolve_brackets("See [Day 4 page 20](../day-04/04-points-1-to-6.qmd#sec-page20)."),
            "See Day 4 page 20.",
        )

    def test_span_keeps_its_visible_text(self):
        self.assertEqual(
            resolve_brackets("[Institute modern methods of training.]{.deming_quote}"),
            "Institute modern methods of training.",
        )

    def test_empty_anchor_leaves_nothing(self):
        self.assertEqual(resolve_brackets("[]{#sec-page27}Instead, I think"), "Instead, I think")

    def test_image_leaves_nothing(self):
        self.assertEqual(resolve_brackets("![A control chart](/assets/x.png){.lightbox}"), "")

    def test_bang_before_a_plain_bracket_is_not_an_image(self):
        self.assertEqual(resolve_brackets("Astonishing! [A] came first"), "Astonishing! [A] came first")

    def test_content_brackets_survive(self):
        """`[A]`, `[B]` and alternate-edition page numbers are Neave's own text."""
        for line in ("parts: [A] Appreciation for a System", "pages 154–155[180–181] Dr Deming"):
            with self.subTest(line=line):
                self.assertEqual(resolve_brackets(line), line)

    def test_nested_content_bracket_inside_a_span(self):
        """The case the sed version could not express — see the module docstring.

        The span's closing bracket is the *third* `]` on the line, so every
        `[^]]*` pattern matches the wrong one and the construct is left whole.
        """
        self.assertEqual(
            resolve_brackets(
                "[The various segments can not be separated. They interact "
                "*[*tools, devices, formulae, etc*]* for rating people.]{.deming_quote}"
            ),
            "The various segments can not be separated. They interact "
            "*[*tools, devices, formulae, etc*]* for rating people.",
        )

    def test_nested_link_inside_a_span(self):
        self.assertEqual(
            resolve_brackets("[quoting [page 4](02-radar.qmd#sec-page4) here]{.deming_quote}"),
            "quoting page 4 here",
        )

    def test_unclosed_bracket_is_left_alone(self):
        """A link wrapped onto the next line is not a construct this can resolve."""
        self.assertEqual(resolve_brackets("mentioned on [Day 3 page 19"), "mentioned on [Day 3 page 19")

    def test_link_attributes_are_consumed(self):
        self.assertEqual(resolve_brackets("see [it](x.qmd){target=_blank} now"), "see it now")


class EnrichedReferenceTests(unittest.TestCase):
    """#610's link text writes a descriptor the source page does not carry."""

    def test_descriptor_after_the_reference_is_dropped(self):
        self.assertEqual(
            resolve_brackets("[page 1, in the Overture](01-overture.qmd#sec-page1)"),
            "page 1",
        )

    def test_day_prefixed_reference(self):
        self.assertEqual(
            resolve_brackets("[Day 3 page 19, the six processes](../day-03/07-six.qmd#sec-page19)"),
            "Day 3 page 19",
        )

    def test_page_range(self):
        self.assertEqual(
            resolve_brackets("[pages 19–21, starting where the four steps are](05-of.qmd#sec-page19)"),
            "pages 19–21",
        )

    def test_only_the_first_comma_splits_it(self):
        """`page 27, above` and `page 30, the note, as promised` both keep just the reference."""
        self.assertEqual(
            resolve_brackets("[page 30, the out-of-hours note, as promised](07-out.qmd#sec-page30)"),
            "page 30",
        )

    def test_woven_descriptor_is_not_touched(self):
        """`the table on page 4` is Neave's prose, not the site's enrichment.

        Canonicalising this shape to "page 4" would delete source text and
        manufacture a difference rather than remove one — the failure mode
        that makes this rule narrow on purpose.
        """
        self.assertEqual(
            resolve_brackets("[the table on page 4](02-your-radar-diagram.qmd#sec-page4)"),
            "the table on page 4",
        )

    def test_a_reference_followed_by_prose_without_a_comma_is_not_touched(self):
        """The comma is what marks the descriptor as ours rather than Neave's.

        Without it this rule would eat real source words — and worse, real
        reference tokens: "pages 6 and 7" would canonicalise to "pages 6",
        dropping a page number and manufacturing exactly the kind of
        mismatch #738's check exists to report.
        """
        for text in (
            "page 84 in the Technical Section",
            "page 47 of the Optional Extras",
            "pages 6 and 7 in Part A",
        ):
            with self.subTest(text=text):
                self.assertEqual(resolve_brackets(f"[{text}](06-part-f.qmd#sec-page84)"), text)

    def test_comma_before_the_reference_is_not_touched(self):
        self.assertEqual(
            resolve_brackets("[$H$, tabulated on page 21](09-tables.qmd#sec-page21)"),
            "$H$, tabulated on page 21",
        )

    def test_a_link_without_a_page_anchor_is_not_canonicalised(self):
        """Only the cross-reference convention produces this shape."""
        self.assertEqual(
            resolve_brackets("[page 3, of the report](https://example.org/report)"),
            "page 3, of the report",
        )


class WorkbookRefTests(unittest.TestCase):
    """`[WB NN]` — the one rule that has to run on both sides of the comparison."""

    def test_every_single_line_shape_in_the_sources(self):
        cases = {
            "Activity 1–f (p 42 [WB 5])": "Activity 1–f (p 42)",
            "on page 44 [WB 38–39].": "on page 44.",
            "where Part D begins [WB 201--209].": "where Part D begins.",
            "(pages 4 and 5 [WB 105 and 106]) before": "(pages 4 and 5) before",
            "write down here [or on WB 123] your own": "write down here your own",
            "summarised on page 29 [also on WB 151].": "summarised on page 29.",
            "pages 3–14 [*WB* 154–165].": "pages 3–14.",
        }
        for source, expected in cases.items():
            with self.subTest(source=source):
                self.assertEqual(strip_workbook_refs(source), expected)

    def test_a_bracket_carrying_prose_is_left_alone(self):
        """`[or WB 220–234 along with today's page 234]` is a cross-reference, not a citation."""
        line = "the text (i.e. pages 14–29 [or WB 220–234 along with today's page 234])"
        self.assertEqual(strip_workbook_refs(line), line)

    def test_never_matches_across_a_line_break(self):
        """Deliberate: a newline-eating pattern could fuse two paragraphs.

        Eight of the 179 citations in the sources wrap onto a second line and
        survive as a result. That is the cheap side of the trade — a stray
        paragraph boundary is a far more expensive error than a fragment of
        citation in a report.
        """
        for wrapped in (
            "(pages 4 and 5 [WB 105\nand 106]) before",   # break before the second number
            "summarised on page 29 [WB\n151].",           # break straight after "WB"
            "on pages 29–33 [WB 130–\n134].",             # break inside the range
        ):
            with self.subTest(wrapped=wrapped):
                self.assertEqual(strip_workbook_refs(wrapped), wrapped)

    def test_a_citation_only_line_is_dropped_not_emptied(self):
        """An emptied line would read downstream as a paragraph break.

        The paragraph would split in two and the half that lost its opening
        would be reported as unmatched content — a failure attributed to the
        transcription rather than to this module.
        """
        self.assertIsNone(strip_workbook_refs_line("   [WB 12]  "))
        self.assertEqual(strip_workbook_refs("keep this\n  [WB 12]\nand this"), "keep this\nand this")

    def test_a_line_that_was_already_blank_stays_blank(self):
        self.assertEqual(strip_workbook_refs_line("   "), "   ")

    def test_applies_to_the_qmd_side_too(self):
        """Seven Day 10/11 chapters kept the citations; the PDF has them everywhere.

        Stripping only the PDF side would trade one asymmetry for another —
        those chapters would start reporting QMD-only numbers just as the
        rest of the corpus stopped reporting PDF-only ones.
        """
        qmd = "> Today's material: [pages 3–14, starting with Part A below](02-a.qmd#sec-page3) [*WB* 154–165]."
        self.assertEqual(prose(qmd), "today s material pages 3 14")


class StructureTests(unittest.TestCase):
    """The line-level filters, ported unchanged unless noted."""

    def test_front_matter_is_dropped(self):
        self.assertEqual(strip_qmd('---\ntitle: "X"\nexecute:\n  echo: false\n---\nBody.\n'), "Body.\n")

    def test_front_matter_only_counts_at_the_top_of_the_file(self):
        self.assertEqual(strip_qmd("Body.\n---\nnot front matter\n"), "Body.\nnot front matter\n")

    def test_code_fences_and_their_contents_are_dropped(self):
        self.assertEqual(strip_qmd("Before.\n```{r}\nplot(x)\n```\nAfter.\n"), "Before.\nAfter.\n")

    def test_layout_directives_are_dropped(self):
        self.assertEqual(strip_qmd("::: {.columns}\nText.\n:::\n"), "Text.\n")

    def test_html_tags_are_dropped(self):
        self.assertEqual(strip_qmd('<div class="major_activity_title"><h2>MAJOR ACTIVITY 9–e</h2></div>\n'),
                         "MAJOR ACTIVITY 9–e\n")

    def test_heading_marker_and_its_attributes_go(self):
        self.assertEqual(strip_qmd("## BACK TO THE WESTERN ELECTRIC COMPANY {#sec-page2}\n"),
                         "BACK TO THE WESTERN ELECTRIC COMPANY\n")

    def test_emphasis_markers_go(self):
        self.assertEqual(strip_qmd("**Stage 5.** Finally construct a *modified* version.\n"),
                         "Stage 5. Finally construct a modified version.\n")

    def test_footnote_reference_goes_and_its_definition_keeps_the_prose(self):
        self.assertEqual(strip_qmd("a brief extract[^a] from that page\n"), "a brief extract from that page\n")
        self.assertEqual(strip_qmd("[^a]: Photo by courtesy of SPC Press Inc.\n"),
                         "Photo by courtesy of SPC Press Inc.\n")

    def test_horizontal_rule_is_dropped(self):
        self.assertEqual(strip_qmd("Above.\n----\nBelow.\n"), "Above.\nBelow.\n")

    def test_a_file_without_a_trailing_newline(self):
        self.assertEqual(strip_qmd("One line"), "One line\n")

    def test_trailing_newline_does_not_add_a_line(self):
        """The caller sizes its chapter separator on this."""
        self.assertEqual(strip_qmd("One line\n"), "One line\n")


class PortedWartTests(unittest.TestCase):
    """Behaviour carried over deliberately, so a re-record is attributable."""

    def test_an_asterisk_rule_is_eaten_by_the_emphasis_rule_first(self):
        """`***` never reaches the rule meant to delete it — as in the sed original.

        Left as it was rather than fixed here: "port it, then change it" keeps
        the re-recorded results attributable to the new stripping rather than
        to a silent extra edit. A lone `*` is far below MIN_PARA_LEN, so
        nothing downstream can see the difference.
        """
        self.assertEqual(strip_qmd("***\n"), "*\n")


class FalsePositiveCategoryTests(unittest.TestCase):
    """One case per category in #732's Day 9 triage, from the real corpus.

    Five are closed here and assert the two sides normalise identically. Five
    are not this module's to close and assert the residual difference, naming
    the issue that owns it.
    """

    # ── Closed by this module ──────────────────────────────────

    def test_1_deming_quote_span_with_a_nested_editorial_bracket(self):
        """27 of Day 9's 55 residual flags. The largest single category."""
        pdf = (
            "Management of a system is action based on prediction. Rational prediction "
            "requires systematic learning [as a good example, learning through the PDSA "
            "(Plan-Do-Study-Act) cycle which we shall cover on Day 11] and comparison of "
            "predictions of short-term and long-term results."
        )
        qmd = (
            "[Management of a system is action based on prediction. Rational prediction "
            "requires systematic learning *[as a good example, learning through the PDSA "
            "(Plan-Do-Study-Act) cycle which we shall cover on Day 11]* and comparison of "
            "predictions of short-term and long-term results.]{.deming_quote}"
        )
        self.assertEqual(prose(qmd), pdf_prose(pdf))

    def test_2_enriched_page_reference_link(self):
        """Day 9 page 27, verbatim from `L.Day.9.15Feb22.pdf` and the chapter file."""
        pdf = (
            "The reason will be immediately clear if you refer back to my small-print "
            "paragraph on today’s page 21: i.e. there are some clear relationships "
            "between the Joiner Triangle’s three bases."
        )
        qmd = (
            "The reason will be immediately clear if you refer back to my small-print "
            "paragraph on today's [page 21, the small-print paragraph on the Joiner "
            "Triangle connections](05-of-profound-knowledge.qmd#sec-page21): i.e. there "
            "are some clear relationships between the Joiner Triangle's three bases."
        )
        self.assertEqual(prose(qmd), pdf_prose(pdf))

    def test_3_workbook_citation_the_site_dropped(self):
        pdf = (
            "followed by Day 4 pages 16–27 [WB 56–67] to browse through the work that "
            "you carried out on the first six Points."
        )
        qmd = (
            "followed by Day 4 pages 16–27 to browse through the work that you carried "
            "out on the first six Points."
        )
        self.assertEqual(prose(qmd), pdf_prose(pdf))

    def test_4_sec_page_anchor_scaffolding(self):
        """Both placements: the bare inline marker and the heading id."""
        self.assertEqual(
            prose("[]{#sec-page27}Instead, I think it would be very useful for you"),
            pdf_prose("Instead, I think it would be very useful for you"),
        )
        self.assertEqual(
            prose("## BACK TO THE WESTERN ELECTRIC COMPANY {#sec-page2}"),
            pdf_prose("BACK TO THE WESTERN ELECTRIC COMPANY"),
        )

    def test_9_blockquote_separator_no_longer_fuses_quoted_paragraphs(self):
        """A bare `>` is the blank line inside a blockquote, not a line of text.

        The sed rule required a trailing space, so the separator survived as a
        non-blank line and three quoted paragraphs fused into one on the QMD
        side while the source had them separate.
        """
        qmd = "> DemDim: pages 264–270.\n>\n> Today's material: pages 3–14.\n"
        self.assertEqual(strip_qmd(qmd), "DemDim: pages 264–270.\n\nToday's material: pages 3–14.\n")

    # ── Not this module's to close ─────────────────────────────

    def test_5_line_wrap_hyphenation_is_asymmetric(self):
        """normalise() rejoins `informa- tion`, but turns a real hyphen into a space.

        So the wrapped form and the solid form agree, while the wrapped form
        and a genuinely hyphenated word do not. Owned by #740.
        """
        self.assertEqual(pdf_prose("the informa- tion at c"), prose("the information at c"))
        self.assertNotEqual(pdf_prose("page 259 to two- thirds down"), prose("page 259 to two-thirds down"))

    def test_6_footnote_superscript_is_glued_to_the_word_by_pdftotext(self):
        """The QMD marker strips cleanly; the PDF's superscript letter does not.

        `extract[^a]` becomes `extract`, but the PDF renders the callout as a
        letter fused to the preceding word — `extractd` — which no stripping
        rule can separate from a real word. Owned by #741/#742.
        """
        self.assertEqual(prose("a brief extract[^a] from that page"), "a brief extract from that page")
        self.assertNotEqual(prose("a brief extract[^a] from that page"),
                            pdf_prose("a brief extractd from that page"))

    def test_7_mid_sentence_page_break_truncates_a_word(self):
        """`Nevertheless` arrives as `theless` across a page boundary. Not recoverable."""
        self.assertNotEqual(
            pdf_prose("theless, his exceptional conciseness of style will still be well in evidence"),
            prose("Nevertheless, his exceptional conciseness of style will still be well in evidence"),
        )

    def test_8_sanctioned_typo_correction_must_stay_visible(self):
        """"Zeebrugge" (site, correct) vs "Zeebruge" (PDF misprint).

        Exempted under docs/deviations/_preamble.md — and it has to keep being
        reported, because the check that would hide it is the same check that
        would hide a real substitution.
        """
        self.assertNotEqual(
            pdf_prose("the Zeebruge Herald of Free Enterprise ferry disaster in 1987"),
            prose("the Zeebrugge Herald of Free Enterprise ferry disaster in 1987"),
        )

    def test_10_letter_prefixed_list_rendered_as_separate_paragraphs(self):
        """The source's running "... four parts: A. ...; B. ..." is split on the site.

        A structural difference in where paragraphs begin, not markup this can
        strip.
        """
        self.assertNotEqual(
            pdf_prose("followed by its four parts: A."),
            prose("followed by its four parts:"),
        )


class CliTests(unittest.TestCase):
    def run_cli(self, *args, stdin=""):
        return subprocess.run(
            [sys.executable, str(MODULE), *args],
            capture_output=True, text=True, input=stdin, cwd=REPO_ROOT,
        )

    def test_files_are_separated_by_a_blank_line(self):
        """Without it the last paragraph of one chapter fuses with the next chapter's first."""
        with tempfile.TemporaryDirectory() as tmp:
            one, two = Path(tmp) / "01.qmd", Path(tmp) / "02.qmd"
            one.write_text("Last paragraph of chapter one.\n", encoding="utf-8")
            two.write_text("First paragraph of chapter two.\n", encoding="utf-8")
            result = self.run_cli(str(one), str(two))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "Last paragraph of chapter one.\n\nFirst paragraph of chapter two.\n\n",
        )

    def test_utf8_survives_the_round_trip(self):
        """The caller runs under LC_ALL=C and the course text is full of en dashes."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.qmd"
            path.write_text("Days 4–5 — Neave’s “quotes”.\n", encoding="utf-8")
            result = self.run_cli(str(path))
        self.assertIn("Days 4–5 — Neave’s “quotes”.", result.stdout)

    def test_workbook_refs_mode_reads_stdin(self):
        result = self.run_cli("--workbook-refs", stdin="on page 44 [WB 38–39].\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "on page 44.\n")

    def test_workbook_refs_mode_rejects_file_arguments(self):
        self.assertNotEqual(self.run_cli("--workbook-refs", "some.qmd").returncode, 0)

    def test_no_arguments_is_an_error(self):
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Usage", result.stderr)

    def test_a_missing_file_fails_loudly(self):
        """A silent skip would drop a whole chapter out of the QMD pool."""
        result = self.run_cli("does-not-exist.qmd")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does-not-exist.qmd", result.stderr)

    def test_main_is_callable_without_the_subprocess(self):
        self.assertEqual(main([]), 1)


class ValidatorIntegrationTests(unittest.TestCase):
    """The orchestration side: the shell must call this and keep no copy."""

    def setUp(self):
        self.script = VALIDATOR.read_text(encoding="utf-8")

    def test_the_shell_no_longer_defines_its_own_stripper(self):
        self.assertNotIn("strip_qmd() {", self.script)

    def test_the_qmd_side_calls_the_module(self):
        self.assertIn('qmd_strip.py" "${qmd_files[@]}"', self.script)

    def test_the_pdf_side_runs_the_same_workbook_rule(self):
        """A second sed copy of the rule would be free to drift from this one."""
        self.assertIn("qmd_strip.py\" --workbook-refs", self.script)

    def test_a_stripping_failure_is_not_swallowed(self):
        self.assertIn("QMD markup stripping failed", self.script)


if __name__ == "__main__":
    unittest.main()
