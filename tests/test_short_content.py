"""Tests for scripts/lib/short_content.py — the pass over content too short to score.

Issue #742. The similarity scorer never sees a block under 40 bytes, for a
good reason (a four-word heading matches any other four-word heading at 0.5),
and until this module existed those 576 corpus-wide blocks were discarded
without record. The tests below are about the two claims that makes:

  1. **Nothing is dropped silently.** Every short block comes back matched,
     set aside with a stated reason, or reported. PartitionTests holds the
     arithmetic that guarantees it.
  2. **Nothing is graded.** Matching is exact, verbatim, or near-exact only —
     a heading with one word changed must come out *reported*, not quietly
     called a match, because at these lengths a substituted word and a
     legitimate rewording are the same number. MatchingTests pins both sides
     of that line.

The fixtures are real corpus text wherever the behaviour depends on its
shape: Day 2's Red Beads rows for column doubling, Day 9's contents page, Day
1's "SOME LIGHT RELIEF!" for the front-matter title path — which is the case
that would otherwise report every one of the site's 88 chapter headings as
missing from itself.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

from paragraphs import mark_pages  # noqa: E402
from short_content import (  # noqa: E402
    BUCKET_CONTENTS,
    BUCKET_DUPLICATED,
    BUCKET_FRAGMENT,
    MIN_VERBATIM_WORDS,
    SHORT_MATCH_THRESHOLD,
    Line,
    bucket_of,
    chapter_titles,
    compare,
    duplicated_column,
    main,
    render,
)
from paragraph_similarity import tokenise  # noqa: E402

MODULE = REPO_ROOT / "scripts" / "lib" / "short_content.py"

# Long enough to clear the 40-byte floor, so it lands in the scored population
# rather than in the one under test. Every fixture needs one: a text with no
# paragraphs at all is not what the module ever runs against.
PROSE = "A paragraph comfortably clear of the forty-byte floor, and then some."


def line(text, page=1):
    return Line(text, page, tokenise(text))


def result_for(pdf, qmd, titles=()):
    return compare(pdf, qmd, list(titles))


class DuplicatedColumnTests(unittest.TestCase):
    """`pdftotext -layout` reading a two-column table row twice."""

    def test_an_exact_doubling(self):
        self.assertTrue(duplicated_column(tokenise("Audrey 16 10 7 Audrey 16 10 7")))

    def test_a_doubling_with_the_next_column_started(self):
        """Day 2's rows run one cell into the repeat: "John 9 11 John 9 11 12"."""
        self.assertTrue(duplicated_column(tokenise("John 9 11 John 9 11 12")))

    def test_a_two_word_row_header(self):
        self.assertTrue(duplicated_column(tokenise("Daily Totals Daily Totals")))

    def test_prose_that_merely_repeats_a_word_is_not_a_table_row(self):
        """The repeat has to account for the line, or the rule reaches into prose."""
        self.assertFalse(
            duplicated_column(tokenise("That that is, is; that that is not, is not"))
        )

    def test_an_ordinary_short_line_is_not(self):
        self.assertFalse(duplicated_column(tokenise("SOME LIGHT RELIEF!")))


class BucketTests(unittest.TestCase):
    def test_a_contents_entry_ends_in_a_page_reference(self):
        self.assertEqual(bucket_of(line("Read DemDim Chapter 6 (p 27)")), BUCKET_CONTENTS)
        self.assertEqual(bucket_of(line("— Stage 3 (p 13)")), BUCKET_CONTENTS)

    def test_a_page_reference_mid_sentence_is_not_a_contents_entry(self):
        """Only a trailing one is the itinerary shape — inside the prose it's content."""
        self.assertIsNone(bucket_of(line("So off you go to Stage 6 on page 44.")))

    def test_a_single_word_is_a_fragment(self):
        self.assertEqual(bucket_of(line("POSTSCRIPT")), BUCKET_FRAGMENT)

    def test_a_table_row_is_recognised_before_its_page_reference(self):
        self.assertEqual(bucket_of(line("Al 4 9 Al 4 9")), BUCKET_DUPLICATED)

    def test_a_heading_is_for_triage(self):
        self.assertIsNone(bucket_of(line("THE THIRTEENTH OBSTACLE")))


class MatchingTests(unittest.TestCase):
    def test_an_exact_short_block_matches(self):
        result = result_for(f"YOUR TURN\n\n{PROSE}", f"YOUR TURN\n\n{PROSE}")
        self.assertEqual((result.checked, result.matched), (1, 1))
        self.assertEqual(result.unmatched, [])

    def test_matching_ignores_case_punctuation_and_quote_style(self):
        """normalise() folds all three away, and the printed page differs in all three."""
        result = result_for(f"“STATISTICS? OH NO!”\n\n{PROSE}", f"'Statistics? Oh no!'\n\n{PROSE}")
        self.assertEqual(result.matched, 1)

    def test_a_line_folded_into_a_longer_paragraph_matches_verbatim(self):
        pdf = f"Avoid tampering\n\n{PROSE}"
        qmd = f"The rule of the funnel is simple: avoid tampering with a stable process.\n"
        result = result_for(pdf, f"{qmd}\n{PROSE}")
        self.assertEqual(result.matched, 1)

    def test_a_verbatim_match_cannot_span_a_paragraph_boundary(self):
        """The tail of one paragraph plus the head of the next is not the line.

        Both halves are here, in order, one blank line apart — and the site
        still does not say what the printed page says.
        """
        pdf = f"tampering with\n\n{PROSE}"
        qmd = f"Nobody is tampering.\n\nWith the funnel, at all, ever, in any way.\n\n{PROSE}"
        self.assertEqual(result_for(pdf, qmd).matched, 0)

    def test_a_verbatim_match_lands_on_whole_words(self):
        """"DAY 1" is not present in a chapter that merely mentions Day 12.

        The two sides are joined into strings to test for a run of words, so
        without space padding at both ends the run is found inside any longer
        token it prefixes or suffixes — and this corpus is full of "Day 1"
        beside "Day 12" and "Rule 1" beside "Rule 10".
        """
        pdf = f"DAY 1\n\n{PROSE}"
        qmd = f"We will come back to all of this on Day 12, at the very end.\n\n{PROSE}"
        result = result_for(pdf, qmd)
        self.assertEqual(result.matched, 0)
        self.assertEqual(len(result.unmatched), 1)

    def test_a_single_word_is_never_evidence_of_presence(self):
        pdf = f"PROJECT\n\n{PROSE}"
        qmd = f"Your Second Project begins in earnest this afternoon, in the workbook.\n\n{PROSE}"
        result = result_for(pdf, qmd)
        self.assertEqual(result.matched, 0)
        self.assertEqual([f.bucket for f in result.unjudged], [BUCKET_FRAGMENT])

    def test_a_heading_with_a_word_changed_is_reported_not_matched(self):
        """The line this pass exists for, and the reason the threshold is high."""
        result = result_for(
            f"ACTIVITY 9–c AND ORGANISATION CHARTS\n\n{PROSE}",
            f"ACTIVITY 9–c AND ORGANISATION CHARTERS\n\n{PROSE}",
        )
        self.assertEqual(result.matched, 0)
        self.assertEqual(len(result.unmatched), 1)
        self.assertLess(result.unmatched[0].score, SHORT_MATCH_THRESHOLD)

    def test_an_unmatched_line_reports_the_closest_candidate_it_found(self):
        result = result_for(
            f"ALL ONE SCIENTIFIC TEAM APPROACH\n\n{PROSE}", f"All One Team\n\n{PROSE}"
        )
        self.assertEqual(result.unmatched[0].closest, "All One Team")
        self.assertGreater(result.unmatched[0].score, 0)

    def test_a_line_with_nothing_resembling_it_scores_zero(self):
        result = result_for(f"LSL USL\n\n{PROSE}", f"Ranking and averages\n\n{PROSE}")
        self.assertEqual(result.unmatched[0].score, 0.0)

    def test_a_chapter_title_counts_as_the_site_carrying_the_heading(self):
        """The site renders Neave's headings as front-matter titles, not body text.

        Without them every printed heading in the corpus reads as unmatched —
        "SOME LIGHT RELIEF!" is on the site, as the title of day-01/10-relief.qmd.
        """
        pdf = f"SOME LIGHT RELIEF!\n\n{PROSE}"
        self.assertEqual(result_for(pdf, PROSE).matched, 0)
        self.assertEqual(result_for(pdf, PROSE, ["SOME LIGHT RELIEF"]).matched, 1)


class PartitionTests(unittest.TestCase):
    """Every short block is accounted for — the claim the whole issue turns on."""

    def test_checked_is_matched_plus_unmatched_plus_unjudged(self):
        pdf = mark_pages(
            "YOUR TURN\n\n"
            "THE THIRTEENTH OBSTACLE\n\n"
            "Al 4 9 Al 4 9\n\n"
            "Read DemDim Chapter 6 (p 27)\n\n"
            "PROJECT\n\n"
            f"{PROSE}\n"
        )
        result = result_for(pdf, f"YOUR TURN\n\n{PROSE}")
        self.assertEqual(result.checked, 5)
        self.assertEqual(
            result.matched
            + sum(f.occurrences for f in result.unmatched)
            + sum(f.occurrences for f in result.unjudged),
            result.checked,
        )

    def test_garbled_blocks_are_counted_separately(self):
        """Page furniture in a symbol font: stated, not silently dropped."""
        pdf = f'! "#$!%!!&!!\'#()!)!!!\n\n{PROSE}\n'
        result = result_for(pdf, PROSE)
        self.assertEqual((result.checked, result.garbled), (0, 1))

    def test_repeat_wordings_are_grouped_with_their_pages(self):
        pdf = mark_pages(
            f"{PROSE}\n\nNet Effect of Adopted Options\n\n"
            f"\fNet Effect of Adopted Options\n\n"
            f"\f\fNet Effect of Adopted Options\n"
        )
        result = result_for(pdf, PROSE)
        self.assertEqual(len(result.unmatched), 1)
        self.assertEqual(result.unmatched[0].occurrences, 3)
        self.assertEqual(result.unmatched[0].pages, [1, 2, 4])

    def test_findings_are_ordered_by_score_highest_first(self):
        """Triage order, as everywhere else in this comparator."""
        pdf = f"LSL USL\n\nRanking and average\n\n{PROSE}"
        result = result_for(pdf, f"Rankings and averages\n\n{PROSE}")
        scores = [f.score for f in result.unmatched]
        self.assertEqual(scores, sorted(scores, reverse=True))


class RenderTests(unittest.TestCase):
    def test_a_finding_shows_its_pages_count_and_closest_match(self):
        pdf = mark_pages(f"{PROSE}\n\nTHE DEMING STORY\n\n\fTHE DEMING STORY\n")
        report = "\n".join(render(result_for(pdf, f"The Deming Dimension\n\n{PROSE}")))
        self.assertIn("THE DEMING STORY", report)
        self.assertIn("x2", report)
        self.assertIn("PDF page(s) 1, 2", report)
        self.assertIn("The Deming Dimension", report)

    def test_a_set_aside_line_states_which_bucket_and_why(self):
        pdf = f"Al 4 9 Al 4 9\n\n{PROSE}"
        report = "\n".join(render(result_for(pdf, PROSE)))
        self.assertIn(f"[{BUCKET_DUPLICATED}]", report)
        self.assertIn("#725", report)

    def test_nothing_unfound_is_still_a_readable_section(self):
        report = "\n".join(render(result_for(f"YOUR TURN\n\n{PROSE}", f"YOUR TURN\n\n{PROSE}")))
        self.assertIn("Short Content", report)
        self.assertNotIn("Not found in the QMD", report)


class ChapterTitleTests(unittest.TestCase):
    def test_reads_the_title_of_every_chapter_that_declares_one(self):
        """Against the real Day 9 sources, so a front-matter change is caught here."""
        titles = chapter_titles(sorted(str(p) for p in (REPO_ROOT / "content" / "days" / "day-09").glob("*.qmd")))
        self.assertIn("A SYSTEM ...", titles)
        self.assertIn("... OF PROFOUND KNOWLEDGE", titles)


class CommandLineTests(unittest.TestCase):
    def test_reports_counts_by_key_then_the_section(self):
        pdf_file = REPO_ROOT / "tests" / "__pycache__" / "short_pdf.txt"
        qmd_file = REPO_ROOT / "tests" / "__pycache__" / "short_qmd.txt"
        pdf_file.parent.mkdir(exist_ok=True)
        pdf_file.write_text(f"THE THIRTEENTH OBSTACLE\n\n{PROSE}\n", encoding="utf-8")
        qmd_file.write_text(f"{PROSE}\n", encoding="utf-8")
        try:
            result = subprocess.run(
                [sys.executable, str(MODULE), str(pdf_file), str(qmd_file)],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
        finally:
            pdf_file.unlink()
            qmd_file.unlink()
        self.assertEqual(result.returncode, 0, result.stderr)
        header, _, body = result.stdout.partition("\n\n")
        self.assertIn("SHORT_CHECKED=1", header)
        self.assertIn("SHORT_UNMATCHED=1", header)
        self.assertIn(f"SHORT_THRESHOLD={SHORT_MATCH_THRESHOLD}", header)
        self.assertIn("THE THIRTEENTH OBSTACLE", body)

    def test_too_few_arguments_is_a_usage_error(self):
        self.assertEqual(main(["short_content.py", "only-one"]), 1)


class ThresholdTests(unittest.TestCase):
    """The two numbers this module's honesty rests on."""

    def test_the_match_threshold_is_above_a_one_word_difference(self):
        """A seven-word line with one word swapped scores 0.86 — it must not match."""
        swapped = tokenise("one two three four five six seven")
        changed = tokenise("one two three four five six eight")
        import difflib

        score = difflib.SequenceMatcher(None, swapped, changed, autojunk=False).ratio()
        self.assertLess(score, SHORT_MATCH_THRESHOLD)

    def test_verbatim_matching_needs_more_than_one_word(self):
        self.assertGreaterEqual(MIN_VERBATIM_WORDS, 2)


if __name__ == "__main__":
    unittest.main()
