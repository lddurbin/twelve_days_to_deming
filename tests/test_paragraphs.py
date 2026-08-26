"""Tests for scripts/lib/paragraphs.py — assembling text into comparable paragraphs.

Issue #741 moved this out of an awk function in validate-transcription.sh, to
add the one thing a line-at-a-time rule could not do: decide that a blank line
is *not* a paragraph break. Three of the ten false-positive categories in
#732's Day 9 triage are that same failure — a mid-sentence PDF page break, a
blockquote split from the sentence that introduces it, a lettered list split
into one block per item — and each of them is a passage that one side of the
comparison breaks up and the other doesn't.

The fixtures below are the real text of those three cases, PDF side and QMD
side, rather than invented examples: ParagraphAssemblyAgreementTests asserts
what actually matters end to end, which is that the two sides come out of
assembly with sentences that score a perfect match against each other. A
regression there is a returning false positive, and it fails here with the
sentence that used to break.

ParityWithTheAwkTests pins the two filters this port deliberately did *not*
change. The port had to be measurable as only the rejoining it exists for, so
both floors still count bytes the way awk under `LC_ALL=C` did, down to the
blocks that sit a byte either side of them.

PageMarkerTests and SiftTests cover what #742 added: page boundaries carried
through the caller's cleanup as marker lines, and the three-way split that
hands the filters' leavings to scripts/lib/short_content.py instead of
dropping them. The marker's transparency is the load-bearing property —
paragraph output has to be identical with markers and without, or the pages
would have been bought with a change to every recorded result.

AccountingTests covers #743's counts of that same split. The one that matters
is the partition — every block read is unreadable, rejoined, short, or
compared, and nothing is in two of those or in none — because a provenance
record claiming to state what went unchecked is only worth reading if those
five numbers close.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

from paragraph_similarity import (  # noqa: E402
    build_pool,
    find_best_sentence,
    tokenise,
)
from paragraphs import (  # noqa: E402
    FIRST_PAGE,
    MIN_PARA_LEN,
    Block,
    account,
    blocks,
    continues,
    is_readable,
    join_continuations,
    main,
    mark_pages,
    read_blocks,
    sift,
    to_paragraphs,
)

MODULE = REPO_ROOT / "scripts" / "lib" / "paragraphs.py"

# pdftotext renders Day 9's running header in a symbol font. Two real ones,
# reproduced byte for byte: they are what sits between the two halves of a
# page-broken sentence, and the reason join_continuations() cannot run until
# the readability filter has been past.
GARBLED_HEADER = '! "#$!%!!&!!\'#()!)!!!\n"#$!%!&\'!()!"#$*!+&!",-./0!'
GARBLED_HEADER_2 = '! "#$!%!!&!!\'#()!""!\n1!2$*+,-!!333!!&\'!45&\'&6/7!8/&9:,70,!'


class BlocksTests(unittest.TestCase):
    def test_splits_on_blank_lines(self):
        self.assertEqual(blocks("one\n\ntwo\n\nthree"), ["one", "two", "three"])

    def test_joins_a_block_s_own_lines_with_single_spaces(self):
        self.assertEqual(blocks("wrapped over\ntwo lines"), ["wrapped over two lines"])

    def test_collapses_runs_of_whitespace_and_trims(self):
        self.assertEqual(blocks("  spaced   out  \n\ttabbed\t"), ["spaced out tabbed"])

    def test_emits_a_final_block_with_no_trailing_blank_line(self):
        self.assertEqual(blocks("first\n\nlast"), ["first", "last"])

    def test_whitespace_only_lines_are_blank(self):
        self.assertEqual(blocks("one\n   \t \ntwo"), ["one", "two"])

    def test_runs_of_blank_lines_produce_no_empty_blocks(self):
        self.assertEqual(blocks("\n\n\none\n\n\n\ntwo\n\n\n"), ["one", "two"])

    def test_empty_input_produces_nothing(self):
        self.assertEqual(blocks(""), [])
        self.assertEqual(blocks("\n  \n"), [])


class ReadabilityTests(unittest.TestCase):
    def test_prose_is_readable(self):
        self.assertTrue(is_readable("Consider the Massachusetts train wreck again."))

    def test_symbol_font_page_header_is_not(self):
        for header in GARBLED_HEADER.splitlines() + GARBLED_HEADER_2.splitlines():
            with self.subTest(header=header):
                self.assertFalse(is_readable(header))

    def test_empty_is_not(self):
        self.assertFalse(is_readable(""))
        self.assertFalse(is_readable("   "))

    def test_counts_bytes_not_characters(self):
        """A real contents entry that lands either side of the floor by counting.

        0.4000 by character and 0.3925 by byte, because the em dash is three
        non-letter bytes and one non-letter character. It is excluded today;
        this pins that the port did not quietly admit it.
        """
        entry = (
            "Point 10: Eliminate exhortations (p 8) "
            "...................................................... "
            "— see Appendix page 25"
        )
        self.assertFalse(is_readable(entry))


class ContinuesTests(unittest.TestCase):
    def test_a_colon_introduces_what_follows(self):
        self.assertTrue(continues("Let me quote Peter:", '"A fundamental premise'))

    def test_a_semicolon_is_the_middle_of_a_list(self):
        self.assertTrue(continues("A. Appreciation for a system;", "B. Some knowledge"))

    def test_an_unpunctuated_tail_continues_into_a_lower_case_head(self):
        self.assertTrue(continues("this was a poor system in dire", "need of improvement"))

    def test_a_hyphenated_line_wrap_continues(self):
        self.assertTrue(continues("including some material. Never-", "theless, his style"))

    def test_a_trailing_comma_continues(self):
        self.assertTrue(continues("first, second,", "and third"))

    def test_a_digit_tail_continues(self):
        self.assertTrue(continues("read through to page 264", "before continuing"))

    def test_an_unpunctuated_tail_does_not_swallow_a_new_sentence(self):
        """A heading ends without punctuation too — the head has to agree."""
        self.assertFalse(continues("Development of Profound Knowledge", "The five half-days"))

    def test_terminal_punctuation_ends_a_paragraph(self):
        self.assertFalse(continues("D. Knowledge of psychology.", "The five half-days"))
        self.assertFalse(continues("Was it really just somebody's fault?", "with the advantage"))
        self.assertFalse(continues("Such as what!", "consider the train wreck"))

    def test_a_closing_quote_ends_a_paragraph(self):
        self.assertFalse(continues('should another accident occur."', "does that sound familiar"))
        self.assertFalse(continues("should another accident occur.”", "does that sound familiar"))

    def test_an_empty_side_never_continues(self):
        self.assertFalse(continues("", "anything"))
        self.assertFalse(continues("anything", ""))


def on_page(page, *texts):
    """Blocks the way read_blocks() hands them to join_continuations()."""
    return [Block(text, page) for text in texts]


class JoinContinuationsTests(unittest.TestCase):
    def test_leaves_unrelated_paragraphs_alone(self):
        paras = on_page(1, "A finished sentence.", "Another finished sentence.")
        self.assertEqual(join_continuations(paras), paras)

    def test_chains_a_whole_lettered_list_in_one_pass(self):
        """Each rejoined item ends in the semicolon that pulls in the next."""
        joined = join_continuations(
            on_page(
                7,
                "followed by its four parts:",
                "A. Appreciation for a system;",
                "B. Some knowledge of theory of variation;",
                "C. Theory of knowledge;",
                "D. Knowledge of psychology.",
                "The five half-days from here follow the same structure.",
            )
        )
        self.assertEqual(
            joined,
            on_page(
                7,
                "followed by its four parts: A. Appreciation for a system; "
                "B. Some knowledge of theory of variation; C. Theory of knowledge; "
                "D. Knowledge of psychology.",
                "The five half-days from here follow the same structure.",
            ),
        )

    def test_an_empty_list_joins_to_nothing(self):
        self.assertEqual(join_continuations([]), [])

    def test_a_rejoined_block_keeps_the_page_it_started_on(self):
        """A sentence broken across a page break is found on the earlier page."""
        joined = join_continuations(
            [
                Block("surely an implication is that this was a poor system in dire", 21),
                Block("need of improvement anyway.", 22),
            ]
        )
        self.assertEqual(len(joined), 1)
        self.assertEqual(joined[0].page, 21)


class FilterOrderTests(unittest.TestCase):
    """The two filters bracket the join, and neither order is interchangeable."""

    def test_garbled_blocks_are_gone_before_the_join_looks_for_neighbours(self):
        text = (
            "surely an implication is that this was a poor system in dire\n\n"
            f"{GARBLED_HEADER}\n\n"
            "need of improvement anyway. (I am reminded of the ferry disaster.)"
        )
        paragraphs = to_paragraphs(text)
        self.assertEqual(len(paragraphs), 1)
        self.assertIn("in dire need of improvement", paragraphs[0])
        self.assertNotIn("#$", paragraphs[0])

    def test_the_length_floor_runs_after_the_join_not_before(self):
        """Day 9's four parts: three of them are under the floor on their own."""
        items = [
            "A. Appreciation for a system;",
            "B. Some knowledge of theory of variation "
            '(sometimes he called it "statistical theory");',
            "C. Theory of knowledge;",
            "D. Knowledge of psychology.",
        ]
        alone = [i for i in items if len(i.encode("utf-8")) < MIN_PARA_LEN]
        self.assertEqual(len(alone), 3, "the fixture has to include items the floor drops")

        text = "\n\n".join(
            [
                "Deming's Chapter 4 has an obvious five-part structure: firstly an "
                "introduction to the System of Profound Knowledge, followed by its "
                "four parts:"
            ]
            + items
        )
        paragraphs = to_paragraphs(text)
        self.assertEqual(len(paragraphs), 1)
        for item in items:
            with self.subTest(item=item):
                self.assertIn(item, paragraphs[0])

    def test_a_short_block_that_nothing_continues_is_still_dropped(self):
        text = "Sources of learning\n\nSuch is the nature of the System of Profound Knowledge."
        self.assertEqual(
            to_paragraphs(text),
            ["Such is the nature of the System of Profound Knowledge."],
        )


class ParityWithTheAwkTests(unittest.TestCase):
    """What the port deliberately kept, so its measured effect is only the join."""

    def test_the_length_floor_is_unchanged(self):
        self.assertEqual(MIN_PARA_LEN, 40)

    def test_the_floor_counts_bytes_so_curly_quotes_pay_their_way(self):
        """39 characters, 43 bytes — admitted before the port, admitted after."""
        line = "“Here are the big gains, 97%, waiting.”"
        self.assertLess(len(line), MIN_PARA_LEN)
        self.assertGreaterEqual(len(line.encode("utf-8")), MIN_PARA_LEN)
        self.assertEqual(to_paragraphs(line), [line])


def sentences_of(text):
    """The comparable sentences one side of the comparison contributes."""
    return [sent for sent, _ in build_pool(to_paragraphs(text))]


def best_score(sentence, pool_text):
    pool = build_pool(to_paragraphs(pool_text))
    return find_best_sentence(tokenise(sentence), pool)[0]


class ParagraphAssemblyAgreementTests(unittest.TestCase):
    """The three #732 categories, as the two sides really arrive.

    Each case asserts the thing the report cares about: every sentence the PDF
    side contributes finds a perfect match on the QMD side. Before #741 each of
    these produced a flag in the near-certain band that no proofreading could
    clear, because the transcription was already right.
    """

    def assert_every_pdf_sentence_matches(self, pdf_text, qmd_text):
        for sentence in sentences_of(pdf_text):
            with self.subTest(sentence=sentence[:60]):
                self.assertEqual(best_score(sentence, qmd_text), 1.0)

    def test_mid_sentence_page_break(self):
        """Day 9: the sentence runs across a page boundary and its header."""
        pdf = (
            "In fact, if an individual’s error could have caused such havoc, surely an\n"
            "implication is that this was a poor system in dire\n\n\n"
            f"{GARBLED_HEADER}\n\n\n"
            "need of improvement anyway. (I am reminded of the Zeebruge Herald of Free\n"
            "Enterprise ferry disaster in 1987.)"
        )
        qmd = (
            "In fact, if an individual's error could have caused such havoc, surely an "
            "implication is that this was a poor system in dire need of improvement "
            "anyway. (I am reminded of the Zeebruge Herald of Free Enterprise ferry "
            "disaster in 1987.)"
        )
        self.assertEqual(len(to_paragraphs(pdf)), 1)
        self.assert_every_pdf_sentence_matches(pdf, qmd)

    def test_page_break_falling_inside_a_hyphenated_word(self):
        """Day 9's "Never-" / "theless," — the join hands normalise() a word to close."""
        pdf = (
            "including some material from his later versions. Never-\n\n"
            f"{GARBLED_HEADER_2}\n\n"
            "theless, his exceptional conciseness of style will still be well in evidence."
        )
        qmd = (
            "including some material from his later versions. Nevertheless, his "
            "exceptional conciseness of style will still be well in evidence."
        )
        self.assert_every_pdf_sentence_matches(pdf, qmd)

    def test_blockquote_split_from_its_lead_in(self):
        """Day 9's Peter Scholtes train-wreck quote.

        The `:!` in the PDF is a superscript footnote callout, not punctuation —
        see the `(?<![:;,][.!?])` guard in paragraph_similarity.py, without
        which this splits on the PDF side only and strands "Let me quote Peter".
        """
        pdf = (
            "One of their recommendations was to construct what we now know as a\n"
            "“conventional organisation chart”. Why? Let me quote Peter:! “A fundamental\n"
            "premise of the ‘train-wreck’ approach to management is that the primary\n"
            "cause of problems is ‘dereliction of duty’.”"
        )
        qmd = (
            "One of their recommendations was to construct what we now know as a "
            '"conventional organisation chart". Why? Let me quote Peter:\n\n'
            '"A fundamental premise of the \'train-wreck\' approach to management is '
            "that the primary cause of problems is 'dereliction of duty'.\""
        )
        self.assertEqual(len(to_paragraphs(qmd)), 1)
        self.assert_every_pdf_sentence_matches(pdf, qmd)

    def test_letter_prefixed_list(self):
        """Day 9's four parts of the System of Profound Knowledge."""
        pdf = (
            "Deming’s Chapter 4 has an obvious five-part structure: firstly an\n"
            "introduction to the System of Profound Knowledge, followed by its four\n"
            "parts: A. Appreciation for a system; B. Some knowledge of theory of\n"
            "variation; C. Theory of knowledge; D. Knowledge of psychology."
        )
        qmd = (
            "Deming's Chapter 4 has an obvious five-part structure: firstly an "
            "introduction to the System of Profound Knowledge, followed by its four "
            "parts:\n\n"
            "A. Appreciation for a system;\n\n"
            "B. Some knowledge of theory of variation;\n\n"
            "C. Theory of knowledge;\n\n"
            "D. Knowledge of psychology."
        )
        self.assertEqual(len(to_paragraphs(qmd)), 1)
        self.assert_every_pdf_sentence_matches(pdf, qmd)

    def test_a_real_defect_inside_a_rejoined_paragraph_still_flags(self):
        """Rejoining must not dilute a swapped word into invisibility.

        Sentence-level scoring is what makes a one-word defect visible (#677);
        a join that merged sentences rather than blocks would undo it. This is
        the page-break fixture with Day 9's real "Day 6" / "Day 5" defect
        planted in the rejoined half.
        """
        pdf = (
            "surely an implication is that this was a poor system in dire\n\n"
            f"{GARBLED_HEADER}\n\n"
            "need of improvement anyway. You used the same scale as you used during Day 6."
        )
        qmd = (
            "surely an implication is that this was a poor system in dire need of "
            "improvement anyway. You used the same scale as you used during Day 5."
        )
        scores = sorted(best_score(s, qmd) for s in sentences_of(pdf))
        self.assertEqual(scores[-1], 1.0, "the undamaged sentence must still match exactly")
        self.assertLess(scores[0], 1.0, "the damaged sentence must still be scored apart")


class PageMarkerTests(unittest.TestCase):
    def test_a_form_feed_becomes_a_marker_line(self):
        marked = mark_pages("last line of one\n\fDAY 9: A SYSTEM\n")
        self.assertEqual(
            marked.splitlines(),
            ["last line of one", "@@pdf-page 2@@", "DAY 9: A SYSTEM"],
        )

    def test_text_without_form_feeds_is_untouched(self):
        text = "no pages here\n\nat all\n"
        self.assertEqual(mark_pages(text), text)

    def test_pages_number_from_one_upward(self):
        marked = mark_pages("one\n\ftwo\n\fthree\n")
        self.assertEqual(
            [line for line in marked.splitlines() if line.startswith("@@")],
            ["@@pdf-page 2@@", "@@pdf-page 3@@"],
        )

    def test_a_mid_line_form_feed_does_not_corrupt_the_line(self):
        """Every form feed in the twelve PDFs starts a line; this is the guard."""
        marked = mark_pages("prose runs on\fPAGE HEADER")
        self.assertEqual(
            marked.splitlines(), ["prose runs on", "@@pdf-page 2@@", "PAGE HEADER"]
        )

    def test_markers_are_transparent_to_block_assembly(self):
        """The whole point: paragraphs must not move because pages are tracked.

        A marker is neither content nor a paragraph break, so a block that
        pdftotext ran across a page boundary stays the single block it was
        when the boundary was deleted outright.
        """
        without = "tail of one page\nhead of the next\n\nA second block.\n"
        with_marker = "tail of one page\n@@pdf-page 12@@\nhead of the next\n\nA second block.\n"
        self.assertEqual(blocks(with_marker), blocks(without))
        self.assertEqual(to_paragraphs(with_marker), to_paragraphs(without))

    def test_a_block_is_stamped_with_the_page_it_starts_on(self):
        text = mark_pages("first page block\n\n\fsecond page block\n\n\fthird page block\n")
        self.assertEqual([block.page for block in read_blocks(text)], [1, 2, 3])

    def test_a_block_spanning_a_boundary_belongs_to_the_earlier_page(self):
        text = mark_pages("opening words\fclosing words\n")
        self.assertEqual(read_blocks(text), [Block("opening words closing words", 1)])

    def test_unmarked_text_reads_as_the_first_page(self):
        """The QMD side has no pages at all, and must still assemble."""
        self.assertEqual(read_blocks("a block"), [Block("a block", FIRST_PAGE)])


class SiftTests(unittest.TestCase):
    """The three-way split #742 needs: scored, too short, too garbled."""

    def test_partitions_every_block(self):
        text = mark_pages(
            "SOME LIGHT RELIEF!\n\n"
            "Here are some of my favourite wrong predictions, in chronological order.\n"
            "\n\f"
            f"{GARBLED_HEADER}\n\n"
            "Nothing about this block is short enough to be dropped by the floor.\n"
        )
        sifted = sift(text)
        self.assertEqual(len(sifted.paragraphs), 2)
        self.assertEqual([block.text for block in sifted.short], ["SOME LIGHT RELIEF!"])
        self.assertEqual([block.page for block in sifted.garbled], [2])

    def test_short_blocks_carry_their_page(self):
        text = mark_pages("A long enough paragraph to clear the floor easily.\n\n\fYOUR TURN\n")
        self.assertEqual([(b.text, b.page) for b in sift(text).short], [("YOUR TURN", 2)])

    def test_paragraphs_are_what_to_paragraphs_returns(self):
        """One implementation, so the scored population cannot drift from the split."""
        text = "YOUR TURN\n\nA paragraph comfortably clear of the forty-byte floor.\n"
        self.assertEqual(sift(text).paragraphs, to_paragraphs(text))


class AccountingTests(unittest.TestCase):
    """The counts #743 records: what a run read, and where each block went."""

    # One text carrying all four outcomes: a garbled page header, a lettered
    # list whose items rejoin into their lead-in, a heading under the floor,
    # and two paragraphs long enough to score.
    TEXT = mark_pages(
        f"{GARBLED_HEADER}\n\n"
        "SOME LIGHT RELIEF!\n\n"
        "Deming's System of Profound Knowledge, followed by its four parts:\n\n"
        "A. Appreciation for a system;\n\n"
        "B. Knowledge about variation;\n\n"
        "C. Theory of knowledge;\n\n"
        "D. Psychology.\n\n\f"
        "Here are some of my favourite wrong predictions, in chronological order.\n"
    )

    def test_the_four_outcomes_partition_every_block_read(self):
        """The invariant the provenance record's honesty rests on."""
        counted = account(self.TEXT)
        self.assertEqual(
            counted.total,
            counted.unreadable + counted.rejoined + counted.short + counted.compared,
        )

    def test_total_counts_blocks_before_assembly_not_after(self):
        """Nine blocks in, however few paragraphs come out the far end."""
        self.assertEqual(account(self.TEXT).total, len(read_blocks(self.TEXT)))

    def test_rejoined_counts_blocks_folded_into_the_one_before_them(self):
        """The four list items, which are part of the paragraph that introduces them."""
        self.assertEqual(account(self.TEXT).rejoined, 4)

    def test_the_counts_are_the_sift_it_reports_on(self):
        """One measurement, so a results file cannot disagree with a report."""
        counted, sifted = account(self.TEXT), sift(self.TEXT)
        self.assertEqual(counted.unreadable, len(sifted.garbled))
        self.assertEqual(counted.short, len(sifted.short))
        self.assertEqual(counted.compared, len(sifted.paragraphs))

    def test_compared_is_the_population_that_gets_scored(self):
        self.assertEqual(account(self.TEXT).compared, len(to_paragraphs(self.TEXT)))

    def test_nothing_is_counted_twice_when_there_is_no_residue(self):
        text = "A paragraph comfortably clear of the forty-byte floor, and alone.\n"
        self.assertEqual(tuple(account(text)), (1, 0, 0, 0, 1))


class CommandLineTests(unittest.TestCase):
    def test_reads_stdin_and_writes_one_paragraph_per_line(self):
        result = subprocess.run(
            [sys.executable, str(MODULE)],
            input="Let me quote Peter:\n\nA fundamental premise of the approach.\n",
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "Let me quote Peter: A fundamental premise of the approach.\n",
        )

    def test_min_length_reports_the_floor_the_caller_prints(self):
        result = subprocess.run(
            [sys.executable, str(MODULE), "--min-length"], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(MIN_PARA_LEN))

    def test_mark_pages_filters_stdin_to_stdout(self):
        result = subprocess.run(
            [sys.executable, str(MODULE), "--mark-pages"],
            input="page one\n\fpage two\n",
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "page one\n@@pdf-page 2@@\npage two\n")

    def test_counts_filters_stdin_to_key_value_lines(self):
        """The contract validate-transcription.sh parses by name (#743)."""
        result = subprocess.run(
            [sys.executable, str(MODULE), "--counts"],
            input="YOUR TURN\n\nA paragraph comfortably clear of the forty-byte floor.\n",
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            ["TOTAL=2", "UNREADABLE=0", "REJOINED=0", "SHORT=1", "COMPARED=1"],
        )

    def test_short_writes_the_sub_floor_blocks_one_per_line(self):
        # #761: paragraph_similarity.py reads these as match candidates, in the
        # same shape as the default mode's output, so the two sides of the
        # comparison cannot end up with different ideas of what "short" means.
        text = (
            "A paragraph comfortably over the forty-byte floor, so that it is scored.\n"
            "\n"
            "(See Appendix page 24.)\n"
        )
        result = subprocess.run(
            [sys.executable, str(MODULE), "--short"],
            input=text,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "(See Appendix page 24.)\n")

    def test_short_and_the_default_mode_partition_the_same_input(self):
        text = "Over the floor by a comfortable margin, so this one is scored.\n\nShort.\n"
        run = lambda *args: subprocess.run(
            [sys.executable, str(MODULE), *args],
            input=text,
            capture_output=True,
            text=True,
            encoding="utf-8",
        ).stdout.splitlines()
        self.assertEqual(len(run() + run("--short")), 2)
        self.assertNotIn("Short.", run())
        self.assertIn("Short.", run("--short"))

    def test_an_unknown_argument_is_a_usage_error(self):
        self.assertEqual(main(["--paragraphs"]), 1)

    def test_utf8_survives_the_round_trip(self):
        """The caller runs under LC_ALL=C and the text is full of curly quotes.

        `encoding="utf-8"` on the call, not just `text=True`: `text=True` alone
        encodes through the *runner's* locale, which under `LC_ALL=C` would
        mangle these quotes before the module's own UTF-8 wrapper ever saw
        them — and the locale is the thing this test is about.
        """
        line = "Dr Deming’s own title was “Production Viewed as a System”, universally."
        result = subprocess.run(
            [sys.executable, str(MODULE)],
            input=line,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(result.stdout, line + "\n")


if __name__ == "__main__":
    unittest.main()
