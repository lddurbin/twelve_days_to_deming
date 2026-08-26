"""Tests for scripts/lib/paragraph_similarity.py.

Issue #677 asked for the altered-content scorer to catch the real transcription
defects from #676, and allowed that acceptance to be verified by hand. Hand
verification doesn't survive a refactor, so the defect shapes are pinned here
instead: each `test_catches_*` case reproduces one real defect found in Day 4's
transcription, with the wording that actually shipped.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts" / "lib"))

from paragraph_similarity import (  # noqa: E402
    ALTERED_SIMILARITY_THRESHOLD as THRESHOLD,
    MISSING_SIMILARITY_THRESHOLD as MISSING_THRESHOLD,
    NEAR_MATCH_SCORE,
    REFERENCE_PAIR_THRESHOLD,
    UNSOURCED_SIMILARITY_THRESHOLD as UNSOURCED_THRESHOLD,
    analyse,
    classify_forward,
    diff_window,
    find_best_sentence,
    normalise,
    reference_mismatch,
    reference_tokens,
    render_reference_mismatches,
    split_sentences,
    tokenise,
)


def score_of(pdf_sentence: str, qmd_sentence: str) -> float:
    """Similarity the scorer assigns when `qmd_sentence` is the only candidate."""
    return find_best_sentence(
        tokenise(pdf_sentence), [(qmd_sentence, tokenise(qmd_sentence))]
    )[0]


class NormaliseTests(unittest.TestCase):
    def test_rejoins_line_wrap_hyphenation(self):
        # pdftotext -layout preserves the hyphen a line wrap introduced, and
        # text_to_paragraphs joins the lines with a space.
        self.assertEqual(normalise("Manage- ment"), normalise("Management"))

    def test_every_wrap_shape_of_a_hyphenated_word_agrees(self):
        """The three shapes one compound word takes across PDF and QMD.

        A wrapped "long- term", a no-space "indi-cated" (pdftotext emits both),
        and the QMD's intact "long-term" all have to normalise to the same
        word — before #740 the first became "longterm" and the third "long
        term", so the same word on both sides scored as a difference. Four of
        Day 9's 55 catalogued false positives were this shape (#732).
        """
        self.assertEqual(normalise("long- term"), "longterm")
        self.assertEqual(normalise("long-term"), "longterm")
        self.assertEqual(normalise("indi-cated"), "indicated")
        self.assertEqual(normalise("Stats-level 0"), normalise("Stats- level 0"))

    def test_joins_every_hyphen_of_a_multiply_hyphenated_word(self):
        """Regression: a rule that consumed the letter after the hyphen would
        leave the next hyphen without a left-hand letter, so where the wrap
        fell would change the answer — "x-y-z" and "x-y- z" must not differ."""
        self.assertEqual(normalise("state-of-the-art"), "stateoftheart")
        self.assertEqual(normalise("x-y-z"), normalise("x-y- z"))

    def test_digit_ranges_are_not_joined(self):
        """A hyphen between digits is a range, not a wrapped word. Joining
        "10-11" into "1011" would invent a reference token neither side of the
        comparison contains — see reference_tokens()."""
        self.assertEqual(normalise("pages 3-4"), "pages 3 4")
        self.assertEqual(normalise("in 1985-86"), "in 1985 86")
        self.assertEqual(reference_tokens("pages 10-11"), {"page 10": 1, "11": 1})

    def test_case_and_punctuation_insensitive(self):
        self.assertEqual(
            normalise('He said "Quality!" — twice.'), normalise("he said quality twice")
        )

    def test_preserves_f(self):
        """Regression: extract_pdf_text's `s/\\f//g` was read by BSD sed as
        "delete every f", and normalise() used to strip f on both sides to
        compensate. That hid every f-only difference; "of" and "or" must not
        collapse together."""
        self.assertNotEqual(normalise("a source of truth"), normalise("a source or truth"))
        self.assertEqual(normalise("Effort"), "effort")

    def test_preserves_digits(self):
        """Regression: a page-number rule ate inline numbers, and normalise()
        stripped digits on both sides to compensate. In a course built on "the
        14 Points", a mis-transcribed number is a defect worth catching."""
        self.assertNotEqual(normalise("the 14 Points"), normalise("the 12 Points"))
        self.assertNotEqual(normalise("Day 1 page 33"), normalise("Day 2 page 33"))


class SplitSentencesTests(unittest.TestCase):
    def test_splits_on_sentence_boundary(self):
        self.assertEqual(
            split_sentences("One thing. Then another! And a third?"),
            ["One thing.", "Then another!", "And a third?"],
        )

    def test_does_not_split_mid_sentence_abbreviation(self):
        """Splitting on bare `[.!?]\\s+` shattered "e.g. when ..." into
        fragments too short to match anything, which surfaced as false
        positives."""
        self.assertEqual(
            split_sentences("This is related to work we have done, e.g. on Day 3."),
            ["This is related to work we have done, e.g. on Day 3."],
        )

    def test_ignores_empty_fragments(self):
        self.assertEqual(split_sentences("   "), [])

    def test_a_closing_quote_before_the_space_does_not_fuse_two_sentences(self):
        """The printed page sets quotes curly, the QMD sources them straight.

        A straight-only class split the QMD and left the PDF fused, which is
        an asymmetry the comparator invented on the side nobody can proofread
        (#741). Both conventions have to segment the same way.
        """
        for closing in ('"', "”"):
            with self.subTest(quote=closing):
                self.assertEqual(
                    split_sentences(f"He said it again.{closing} The meeting then ended."),
                    ["He said it again.", "The meeting then ended."],
                )

    def test_an_opening_quote_after_the_space_does_not_fuse_two_sentences(self):
        for opening in ('"', "“"):
            with self.subTest(quote=opening):
                self.assertEqual(
                    len(split_sentences(f"Worth reproducing in full. {opening}Figure 1 follows.")),
                    2,
                )

    def test_both_quote_conventions_produce_the_same_segmentation(self):
        straight = 'He left. "I will return," she said. The door closed.'
        typographic = "He left. “I will return,” she said. The door closed."
        self.assertEqual(len(split_sentences(straight)), len(split_sentences(typographic)))

    def test_a_footnote_callout_on_a_lead_in_colon_is_not_a_boundary(self):
        """`:!` is pdftotext's superscript marker: 55 in the PDFs, 0 in the QMD.

        Read as punctuation it splits the PDF where the QMD stays whole, and
        strands "Let me quote Peter" as a four-word fragment matching nothing.
        """
        fused = "Let me quote Peter:! “A fundamental premise of the approach."
        self.assertEqual(split_sentences(fused), [fused])

    def test_a_real_exclamation_before_a_quotation_still_is_a_boundary(self):
        self.assertEqual(
            len(split_sentences("Such as what! “A fundamental premise of the approach.")),
            2,
        )


class TokeniseTests(unittest.TestCase):
    def test_single_word_edit_is_visible_at_word_granularity(self):
        """The reason similarity is measured in words, not characters: a
        one-digit change is 1 char in 76 (0.9865, indistinguishable from clean)
        but 1 word in 14."""
        pdf = "This is even more the case when the control chart is used in the 97% region."
        qmd = "This is even more the case when the control chart is used in the 37% region."
        self.assertLess(score_of(pdf, qmd), 0.95)

    def test_faithful_transcription_tokenises_identically(self):
        self.assertEqual(tokenise("Manage- ment of the 14 Points"), tokenise("Management of the 14 Points"))


class FindBestSentenceTests(unittest.TestCase):
    def test_picks_closest_of_several(self):
        pool = [(s, tokenise(s)) for s in
                ("Something entirely unrelated.", "The cat sat on the mat.", "Nothing here.")]
        score, best = find_best_sentence(tokenise("The cat sat on a mat."), pool)
        self.assertEqual(best, "The cat sat on the mat.")
        # 1 differing word in 6 — 2*5/12 at word granularity.
        self.assertAlmostEqual(score, 5 / 6)

    def test_identical_text_scores_one(self):
        self.assertEqual(score_of("The cat sat on the mat.", "The cat sat on the mat."), 1.0)

    def test_quick_ratio_shortcut_agrees_with_exhaustive_search(self):
        """find_best_sentence skips candidates whose upper-bound ratio can't
        beat the current best. That's only sound if it returns the same answer
        an exhaustive scan would."""
        import difflib

        pool_text = [
            "Deming taught that quality begins with management.",
            "Quality begins with the management of the system.",
            "A wholly different sentence about red beads.",
            "Quality begins with management, Deming taught.",
        ]
        pool = [(s, tokenise(s)) for s in pool_text]
        probe = tokenise("Deming taught that quality begins with the management.")
        got_score, got_best = find_best_sentence(probe, pool)
        want = max(
            ((difflib.SequenceMatcher(None, t, probe, autojunk=False).ratio(), s) for s, t in pool),
            key=lambda p: p[0],
        )
        self.assertAlmostEqual(got_score, want[0])
        self.assertEqual(got_best, want[1])

    def test_common_words_are_not_discarded_as_junk(self):
        """difflib marks elements appearing in >1% of a 200+-element seq2 as
        ignorable junk. On word tuples that means "the"/"of"/"to", whose
        presence is real evidence. pdftotext can emit a 200+-word block (a
        whole bulleted list is one paragraph to it), so the scorer must pass
        autojunk=False or long blocks silently score low."""
        long_sentence = " ".join(["the quality of the system is the responsibility of management"] * 25)
        self.assertGreater(len(tokenise(long_sentence)), 200)
        self.assertEqual(score_of(long_sentence, long_sentence), 1.0)
        # One word changed out of 275 must stay far above threshold, not collapse.
        self.assertGreater(score_of(long_sentence, long_sentence.replace("quality", "calibre", 1)), 0.99)


class DiffWindowTests(unittest.TestCase):
    """The report must always show the reader the difference it flagged."""

    def test_shows_a_difference_past_the_truncation_point(self):
        """The regression: truncating from the start displayed two
        identical-looking strings. Day 4's Malcolm Gall sentence differs at
        character 241 of 249, well past the 200-character window."""
        head = ("My friend Malcolm Gall once pointed out to me that a \"Scientific Approach\"—which I "
                "suppose might be interpreted as something like a \"Purely Logical Approach\"—may be "
                "seen by some as an inhibitor of creativity and innovation (to be studied on ")
        pdf, qmd = head + "Day 11).", head + "Day 9)."
        pdf_out, qmd_out = diff_window(pdf, qmd)
        self.assertIn("Day 11", pdf_out)
        self.assertIn("Day 9", qmd_out)
        self.assertNotEqual(pdf_out, qmd_out)

    def test_short_sentences_are_shown_whole_and_unmarked(self):
        pdf_out, qmd_out = diff_window("The cat sat on the mat.", "The cat sat on a mat.")
        self.assertEqual(pdf_out, "The cat sat on the mat.")
        self.assertEqual(qmd_out, "The cat sat on a mat.")

    def test_elides_only_the_side_actually_trimmed(self):
        pdf = "Alpha differs here. " + "padding word " * 40
        qmd = "Alpha matches here. " + "padding word " * 40
        pdf_out, _ = diff_window(pdf, qmd)
        self.assertIn("differs", pdf_out)
        self.assertFalse(pdf_out.startswith("..."), "difference is at the head; nothing to elide before it")
        self.assertTrue(pdf_out.endswith("..."))

    def test_identical_after_normalisation_still_renders(self):
        """Typographic-only differences produce no opcodes worth windowing;
        the excerpt must still be the sentence, not an empty string."""
        pdf_out, qmd_out = diff_window("It's plain.", "It's plain.")
        self.assertEqual((pdf_out, qmd_out), ("It's plain.", "It's plain."))

    def test_window_stays_within_budget(self):
        pdf = "word " * 200 + "alpha " + "word " * 200
        qmd = "word " * 200 + "omega " + "word " * 200
        pdf_out, _ = diff_window(pdf, qmd, width=80)
        self.assertIn("alpha", pdf_out)
        self.assertLessEqual(len(pdf_out.strip(".")), 80)


class DefectDetectionTests(unittest.TestCase):
    """Each case is a real Day 4 defect: the PDF wording, then what shipped."""

    def assert_flagged(self, pdf: str, qmd: str, *, near_certain: bool = True):
        score = score_of(pdf, qmd)
        self.assertLess(
            score, THRESHOLD,
            f"scored {score:.4f}, at/above the {THRESHOLD} threshold — would not be flagged",
        )
        if near_certain:
            self.assertGreaterEqual(
                score, NEAR_MATCH_SCORE,
                f"scored {score:.4f}, below the {NEAR_MATCH_SCORE} near-match band, so it "
                "would sort into the ambiguous tail instead of the review-first band",
            )

    def test_catches_subject_swap(self):
        # #676 defect 1: the subject of the sentence was swapped.
        self.assert_flagged(
            "Back then, those were pretty much all I knew about the Deming philosophy.",
            "Back then, there were pretty much all I knew about the Deming philosophy.",
        )

    def test_catches_dropped_qualifier(self):
        self.assert_flagged(
            "That compares interestingly with the five “Deadly Diseases” of Western "
            "management (which we shall get to tomorrow afternoon).",
            "That compares interestingly with the five \"Deadly Diseases\" of Western "
            "management (which we shall get to tomorrow).",
        )

    def test_catches_dropped_word_in_proper_noun(self):
        self.assert_flagged(
            "So that little diagram of the Joiner Triangle was not just simple—it was profound.",
            "So that little diagram of the Triangle was not just simple—it was profound.",
        )

    def test_catches_substituted_phrase(self):
        self.assert_flagged(
            "Some ten suggestions of what might be included apparently arose from those "
            "discussions, although unfortunately I do not have any details.",
            "Some ten suggestions of what might be included apparently emerged from those "
            "discussions, although unfortunately I do not have any details.",
        )

    def test_catches_inserted_words(self):
        self.assert_flagged(
            "And this encouraged me to search for a more fruitful way of finding those links.",
            "And this encouraged me to change my approach to search for a more fruitful way "
            "of finding those links.",
            near_certain=False,
        )

    def test_catches_numeric_change(self):
        """Only detectable because normalise() stopped stripping digits."""
        self.assert_flagged(
            "This is even more the case when the control chart is used in the 97% region.",
            "This is even more the case when the control chart is used in the 37% region.",
        )

    def test_does_not_flag_clean_transcription(self):
        """A faithful transcription differing only in typographic quotes and an
        em dash must not be flagged, or the report drowns in noise."""
        pdf = ("In all fields of activity, everyone recognises the importance of quality "
               "to a certain extent—“that’s obvious”.")
        qmd = ("In all fields of activity, everyone recognises the importance of quality "
               "to a certain extent--\"that's obvious\".")
        self.assertGreaterEqual(score_of(pdf, qmd), THRESHOLD)


class AnalyseTests(unittest.TestCase):
    def test_finds_defect_in_trailing_sentence_of_a_block(self):
        """The case the paragraph-level presence check structurally cannot see:
        pdftotext merges consecutive paragraphs into one blank-line-delimited
        block, so matching the block's opening words marks the whole block
        present — trailing sentences included. Day 4 shipped a dropped passage
        exactly this way."""
        pdf_block = ("This is another situation where teaching obstructs Deming. "
                     "An interesting related topic is COPQ: the cost of poor quality.")
        qmd = ["This is another situation where teaching obstructs Deming."]
        result = analyse([pdf_block], qmd, THRESHOLD)
        self.assertEqual(len(result), 1)
        flagged_pdf_sentences = [f[1] for f in result[0][1]]
        self.assertIn(
            "An interesting related topic is COPQ: the cost of poor quality.",
            flagged_pdf_sentences,
        )
        self.assertNotIn(
            "This is another situation where teaching obstructs Deming.",
            flagged_pdf_sentences,
        )

    def test_orders_by_descending_similarity(self):
        pdf = ["A totally unrelated sentence about beads and funnels here.",
               "The cat sat on the mat."]
        qmd = ["The cat sat on a mat.", "Something else entirely different."]
        result = analyse(pdf, qmd, THRESHOLD)
        top_scores = [flagged[0][0] for _, flagged in result]
        self.assertEqual(top_scores, sorted(top_scores, reverse=True))

    def test_empty_qmd_returns_no_findings(self):
        """A degenerate QMD side must not produce -100% "findings"."""
        self.assertEqual(analyse(["Any sentence at all here."], [], THRESHOLD), [])
        self.assertEqual(analyse(["Any sentence at all here."], ["...", "!!!"], THRESHOLD), [])

    def test_identical_documents_flag_nothing(self):
        paras = ["The first paragraph. It has two sentences.", "A second paragraph here."]
        self.assertEqual(analyse(paras, paras, THRESHOLD), [])

    def test_reverse_direction_flags_qmd_paragraph_with_no_pdf_source(self):
        """#718: analyse() is direction-agnostic, so the "unsourced" pass in
        validate-transcription.sh is the same function called with the QMD
        paragraphs as the walk-list and the PDF paragraphs as the pool."""
        pdf_paras = ["Dr Deming's fourteen points are a foundation for transformation."]
        qmd_paras = [
            "Dr Deming's fourteen points are a foundation for transformation.",
            "Reveal the suggested answer for this activity below.",
        ]
        result = analyse(qmd_paras, pdf_paras, UNSOURCED_THRESHOLD)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0][0], "Reveal the suggested answer for this activity below.")


class ClassifyForwardTests(unittest.TestCase):
    """Coverage for the #719 replacement of find_in_qmd()'s fingerprint grep:
    classify_forward() derives missing/altered/matched from the same sentence
    scores this module already computes, rather than a separate presence
    check."""

    def test_paragraph_with_no_close_match_is_missing(self):
        pdf_paras = ["A wholly unrelated paragraph about beads and funnels here."]
        qmd_paras = ["Something completely different about quality management systems."]
        missing, altered, matched, _refs = classify_forward(pdf_paras, qmd_paras, MISSING_THRESHOLD, THRESHOLD)
        self.assertEqual(missing, pdf_paras)
        self.assertEqual(altered, [])
        self.assertEqual(matched, 0)

    def test_paragraph_with_a_close_match_is_not_missing(self):
        pdf_paras = ["The cat sat on the mat. This sentence is unrelated filler text here."]
        qmd_paras = ["The cat sat on the mat."]
        missing, altered, matched, _refs = classify_forward(pdf_paras, qmd_paras, MISSING_THRESHOLD, THRESHOLD)
        self.assertEqual(missing, [])

    def test_clean_paragraph_is_matched_not_altered(self):
        paras = ["The first paragraph. It has two sentences.", "A second paragraph here."]
        missing, altered, matched, _refs = classify_forward(paras, paras, MISSING_THRESHOLD, THRESHOLD)
        self.assertEqual(missing, [])
        self.assertEqual(altered, [])
        self.assertEqual(matched, len(paras))

    def test_present_but_altered_paragraph_is_not_missing(self):
        """A paragraph that clears the missing bar but has a flagged sentence
        must land in 'altered', not 'missing' — the two checks are not
        redundant, they classify different paragraphs."""
        pdf_paras = ["Back then, those were pretty much all I knew about the Deming philosophy."]
        qmd_paras = ["Back then, there were pretty much all I knew about the Deming philosophy."]
        missing, altered, matched, _refs = classify_forward(pdf_paras, qmd_paras, MISSING_THRESHOLD, THRESHOLD)
        self.assertEqual(missing, [])
        self.assertEqual(len(altered), 1)
        self.assertEqual(matched, 0)

    def test_paragraph_with_no_scoreable_sentence_fails_closed(self):
        """Regression for the find_in_qmd() bug this replaces: an empty
        fingerprint used to count as matched with no check performed at all.
        A paragraph that normalises to nothing scoreable must fail closed
        into 'missing', never silently into 'matched'."""
        pdf_paras = ["--- *** ---"]
        qmd_paras = ["Some ordinary sentence that exists on the site."]
        missing, altered, matched, _refs = classify_forward(pdf_paras, qmd_paras, MISSING_THRESHOLD, THRESHOLD)
        self.assertEqual(missing, pdf_paras)
        self.assertEqual(matched, 0)

    def test_empty_qmd_pool_marks_everything_missing(self):
        pdf_paras = ["Any paragraph at all, it doesn't matter what it says here."]
        missing, altered, matched, _refs = classify_forward(pdf_paras, [], MISSING_THRESHOLD, THRESHOLD)
        self.assertEqual(missing, pdf_paras)
        self.assertEqual(altered, [])
        self.assertEqual(matched, 0)

    def test_every_paragraph_is_classified_exactly_once(self):
        pdf_paras = [
            "A wholly unrelated paragraph about beads and funnels here.",
            "Back then, those were pretty much all I knew about the Deming philosophy.",
            "The first paragraph. It has two sentences.",
        ]
        qmd_paras = [
            "Something completely different about quality management systems.",
            "Back then, there were pretty much all I knew about the Deming philosophy.",
            "The first paragraph. It has two sentences.",
        ]
        missing, altered, matched, _refs = classify_forward(pdf_paras, qmd_paras, MISSING_THRESHOLD, THRESHOLD)
        self.assertEqual(len(missing) + len(altered) + matched, len(pdf_paras))


class UnsourcedTests(unittest.TestCase):
    """Coverage for the reverse ("unsourced") direction added by #718: QMD
    content with no credible PDF source, which the forward Missing/Altered
    checks cannot see because they only ever ask whether a *PDF* paragraph is
    present in the QMD."""

    def test_fabricated_sentence_scores_far_below_threshold(self):
        """Acceptance criterion 1: content invented during transcription, with
        no PDF counterpart at all, must score well under
        UNSOURCED_SIMILARITY_THRESHOLD regardless of what the rest of the PDF
        happens to be about."""
        pdf_pool = [
            "Dr Deming's fourteen points are a foundation for transformation of "
            "American industry.",
            "The system of profound knowledge has four parts: appreciation for a "
            "system, knowledge about variation, theory of knowledge, and psychology.",
        ]
        fabricated = (
            "Deming's fifteenth point, added posthumously by his estate in 2003, "
            "calls for mandatory quarterly audits of every supplier's statistical "
            "control charts."
        )
        score, _ = find_best_sentence(
            tokenise(fabricated), [(s, tokenise(s)) for s in pdf_pool]
        )
        self.assertLess(score, UNSOURCED_THRESHOLD)

    def test_catches_645_wrong_numbers_shape(self):
        """Acceptance criterion 2, using #645's actual wording. That issue was
        two defects in one paragraph: wrong finishing-position numbers, and a
        closing sentence copied verbatim from the Rule 4 section elsewhere in
        the same PDF. The reverse pass catches the first and, as documented in
        the module docstring, structurally cannot catch the second — a
        verbatim duplicate scores a perfect match against its true (but
        wrongly relocated) origin. Both outcomes are pinned here rather than
        left to be rediscovered.
        """
        # The true Rule 3 close (source page 49) and the true Rule 4 close
        # (source page 52) the defect borrowed verbatim.
        pdf_pool = [
            "Carefully confirm with your track that the next finishing positions "
            "are: marble under funnel at 29, funnel moved to 31, marble at 28, "
            "and funnel moved to 32.",
            "So the picture stays unchanged at the fourth stage and, at the fifth "
            "stage, both the marble and then the funnel end up at the target of "
            "30—the “happy accident” to which I referred on page 52.",
        ]
        pool = [(s, tokenise(s)) for s in pdf_pool]

        # Defect 1 (caught): the numbers that shipped (29/31 correct, but
        # 25/35 instead of the true 28/32) contradict Rule 3's own arithmetic.
        wrong_numbers = (
            "Carefully confirm with your track that the next finishing positions "
            "are: marble at 29, funnel moves to 31; marble at 25, and funnel "
            "moves to 35."
        )
        score, best = find_best_sentence(tokenise(wrong_numbers), pool)
        self.assertEqual(best, pdf_pool[0])
        self.assertLess(score, THRESHOLD)

        # Defect 2 (known blind spot, not a passing UNSOURCED assertion): the
        # borrowed sentence IS the Rule 4 text, verbatim, so it scores a
        # perfect match against its true origin — this is exactly why it
        # cannot be flagged by a similarity-only reverse pass.
        borrowed = pdf_pool[1]
        score, best = find_best_sentence(tokenise(borrowed), pool)
        self.assertEqual(score, 1.0)
        self.assertEqual(best, pdf_pool[1])


class ReferenceTokenTests(unittest.TestCase):
    def test_qualified_and_bare_numerals_are_distinct_tokens(self):
        self.assertEqual(
            reference_tokens("See page 19, and also 19 others on Day 19."),
            {"page 19": 1, "19": 1, "day 19": 1},
        )

    def test_plurals_and_abbreviations_fold_onto_the_singular(self):
        """"pages 27" and "p 27" name the same target as "page 27".

        Only the target is this check's business; "page" vs "pages" is a
        wording difference, which the altered check already owns. Without the
        folding, every such wording difference would be reported twice.
        """
        for phrase in ("on page 27", "on pages 27", "on p 27", "on pp 27"):
            self.assertEqual(reference_tokens(phrase), {"page 27": 1}, phrase)

    def test_repeated_numbers_are_counted_not_deduplicated(self):
        """A multiset, so dropping one of a repeated pair is still visible."""
        self.assertEqual(
            reference_tokens("pages 10-11, 22-23 and 26-27"),
            {"page 10": 1, "11": 1, "22": 1, "23": 1, "26": 1, "27": 1},
        )
        self.assertNotEqual(
            reference_tokens("Rule 4, Rule 4"), reference_tokens("Rule 4")
        )

    def test_ordinals_years_and_degree_artifacts_read_as_their_number(self):
        """The several shapes one number takes across PDF and QMD.

        "11th"/"11" and "1990s"/"1990" are ordinary prose variation, and "2o"
        is how `pdftotext -layout` renders "2°" — the QMD, which has the real
        degree sign, normalises to a bare "2". Each of these would otherwise
        read as a token present on one side and absent on the other, for no
        defect at all.
        """
        self.assertEqual(reference_tokens("the 11th Point"), {"11": 1})
        self.assertEqual(reference_tokens("back in the 1990s"), {"1990": 1})
        self.assertEqual(reference_tokens("strays 2o from"), reference_tokens("strays 2 from"))

    def test_ignores_numbers_inside_words(self):
        """Only a word that *starts* with a digit is a reference."""
        self.assertEqual(reference_tokens("the B1 workbook and F3 chart"), {})

    def test_line_wrap_hyphenation_does_not_change_a_number(self):
        """Inherited from normalise(), which the score also runs through."""
        self.assertEqual(reference_tokens("on page 1-\n9 today"), reference_tokens("on page 19 today"))

    def test_agreeing_sentences_report_no_mismatch(self):
        self.assertIsNone(reference_mismatch("See page 19 today.", "See page 19 today."))

    def test_mismatch_names_which_side_each_token_came_from(self):
        """Which side is empty is the first thing a reader needs — a token only
        the PDF has is content dropped, one only the QMD has is content added."""
        self.assertEqual(
            reference_mismatch("See page 19.", "See page 18."), (["page 19"], ["page 18"])
        )
        self.assertEqual(
            reference_mismatch("See page 19 [WB 151].", "See page 19."), (["151"], [])
        )
        self.assertEqual(
            reference_mismatch("See page 19.", "See page 19, in Point 13."),
            ([], ["point 13"]),
        )


class ReferenceEscapeClassTests(unittest.TestCase):
    """The defect class #738 exists for: a wrong number that scores as clean.

    Both pairs below are real, taken verbatim from the corpus and from the
    site as it shipped — not constructed to make a point.
    """

    # Day 9 PDF page 1 against content/days/day-09/01-introduction.qmd, as the
    # site stands today. 50 words each side, differing in exactly one digit.
    LIVE_PDF = (
        "One reason for keeping this quite short is to allow you plenty of time "
        "for today\u2019s Major Activity which is to develop an \u201cOrganisation "
        "Viewed as a System\u201d flow diagram for your organisa- tion, guided by "
        "Deming\u2019s famous diagram that you saw as early as Day 1 page 35."
    )
    LIVE_QMD = (
        "One reason for keeping this quite short is to allow you plenty of time "
        "for today's Major Activity which is to develop an \"Organisation Viewed "
        "as a System\" flow diagram for your organisation, guided by Deming's "
        "famous diagram that you saw as early as Day 1 page 25."
    )

    def test_a_one_digit_error_in_a_long_sentence_scores_as_a_clean_match(self):
        """The premise. 50 words, one wrong digit, and the scorer says clean.

        This is not a threshold that wants tightening: at word granularity one
        word in fifty is 0.98 exactly, and any cut low enough to catch it would
        flag every ordinary two-word rewording in the corpus.
        """
        self.assertEqual(len(tokenise(self.LIVE_PDF)), 50)
        score = score_of(self.LIVE_PDF, self.LIVE_QMD)
        self.assertAlmostEqual(score, 0.98, places=4)
        self.assertGreaterEqual(score, THRESHOLD)

    def test_that_same_pair_is_caught_by_reference_tokens(self):
        self.assertEqual(
            reference_mismatch(self.LIVE_PDF, self.LIVE_QMD), (["page 35"], ["page 25"])
        )

    def test_classify_forward_reports_it_while_calling_the_paragraph_clean(self):
        """End to end: the same paragraph counts as matched *and* as a
        reference mismatch. The two are independent by design."""
        missing, altered, matched, refs = classify_forward(
            [self.LIVE_PDF], [self.LIVE_QMD], MISSING_THRESHOLD, THRESHOLD
        )
        self.assertEqual((missing, altered, matched), ([], [], 1))
        self.assertEqual(len(refs), 1)
        score, _pdf, _qmd, pdf_only, qmd_only = refs[0]
        self.assertGreaterEqual(score, THRESHOLD)
        self.assertEqual((pdf_only, qmd_only), (["page 35"], ["page 25"]))


class KnownDefectShapeTests(unittest.TestCase):
    """The two hand-found reference defects named in #738, pinned verbatim.

    Neither actually reaches ALTERED_SIMILARITY_THRESHOLD — both sentences are
    around 30 words, so one wrong word costs ~3%, and both were duly flagged as
    altered. What went wrong was not that the scorer missed them: Day 9 carried
    62 near-certain flags at the time, and these two sat in that list
    indistinguishable from 60 wording nits. That is the second thing this
    section is for, alongside the genuine >=0.98 escapes in the class above —
    it promotes the consequential findings out of a list nobody can read in
    one sitting. REFERENCE_PAIR_THRESHOLD is set at 0.85 — not 0.98, and not
    the 0.90 the rest of the near-certain machinery uses — so that shapes like
    these are covered too: the page-19 pair scores 0.8788, because the
    descriptor the site wrote into the link costs more similarity than the
    wrong digit does. The assertions below pin those scores, so raising the
    floor fails here rather than silently dropping the coverage.
    """

    def test_catches_the_page_19_cross_reference(self):
        """Wave 0 of #734: content/days/day-09/06-introductions-to-the-system.qmd
        said "page 18" where the source says "page 19", and linked to
        #sec-page18 to match. The descriptor the site had written accurately
        described page 18, so the link was internally consistent and wrong only
        against the PDF."""
        pdf = (
            "Next, as I implied on page 19, I strongly recommend that you include "
            "the relevant \u201cPrelude\u201d within the browsing session that begins "
            "your study of each of the four parts."
        )
        qmd = (
            "Next, as I implied on page 18, the guidance for the Second Project, I "
            "strongly recommend that you include the relevant \"Prelude\" within the "
            "browsing session that begins your study of each of the four parts."
        )
        score = score_of(pdf, qmd)
        self.assertLess(score, THRESHOLD)          # was flagged, and buried
        # 0.8788: the six-word descriptor the site wrote into the link costs
        # more similarity than the wrong digit does. This pair is why
        # REFERENCE_PAIR_THRESHOLD is 0.85 and not 0.90.
        self.assertGreaterEqual(score, REFERENCE_PAIR_THRESHOLD)
        self.assertLess(score, 0.90)
        self.assertEqual(reference_mismatch(pdf, qmd), (["page 19"], ["page 18"]))

    def test_catches_the_day_5_for_day_6_reference(self):
        """#732 defect 9: content/days/day-09/07-out-of-hours.qmd said the 0-5
        scale was the one used "during Day 5"; the source says Day 6, and the
        table really was introduced on Day 6."""
        pdf = (
            "I suggest you use the same kind of 0\u20135 scale in this table as you "
            "used during Day 6 (ranging from 5 = very strong rela- tionship to 0 = "
            "no apparent relationship)."
        )
        qmd = (
            "I suggest you use the same kind of 0\u20135 scale as in this table as you "
            "used during Day 5 (ranging from 5 = very strong relationship to 0 = no "
            "apparent relationship)."
        )
        score = score_of(pdf, qmd)
        self.assertLess(score, THRESHOLD)
        self.assertGreaterEqual(score, REFERENCE_PAIR_THRESHOLD)
        self.assertEqual(reference_mismatch(pdf, qmd), (["day 6"], ["day 5"]))

    def test_canonicalising_the_link_text_must_not_hide_the_page_19_defect(self):
        """The invariant #738 exists to hold for #739.

        Once strip_qmd() canonicalises "[page 18, descriptor](target)" down to
        "page 18", this pair loses the descriptor that was dragging it down and
        rises from 0.8788 to 0.9667 — closer to a clean match than before, and
        *further* from being flagged as altered. The reference check is the
        thing that must still see it, and it does, because it does not consult
        the score at all.
        """
        pdf = (
            "Next, as I implied on page 19, I strongly recommend that you include "
            "the relevant \u201cPrelude\u201d within the browsing session that begins "
            "your study of each of the four parts."
        )
        canonicalised = pdf.replace("page 19", "page 18")
        score = score_of(pdf, canonicalised)
        self.assertGreater(score, 0.96)
        self.assertLess(score, THRESHOLD)
        self.assertGreaterEqual(score, REFERENCE_PAIR_THRESHOLD)
        self.assertEqual(reference_mismatch(pdf, canonicalised), (["page 19"], ["page 18"]))

    def test_the_repeated_0_and_5_do_not_mask_the_day_number(self):
        """Both sentences above contain "0" and "5" several times over, and the
        defect is a "5" replacing a "6". Without the day/page qualifier the two
        multisets would still differ, but the report would say "6 -> 5" and
        leave the reader hunting; with it, the finding names itself."""
        self.assertIn("day 6", reference_tokens("as you used during Day 6 (5 to 0)"))
        self.assertNotIn("day 5", reference_tokens("as you used during Day 6 (5 to 0)"))


class ClassifyForwardReferenceTests(unittest.TestCase):
    PDF = "The chart on page 41 shows the whole of the second year's data in one place."
    QMD = "The chart on page 14 shows the whole of the second year's data in one place."

    def test_pairs_below_the_reference_threshold_are_not_compared(self):
        """A numeral disagreement is only evidence when the two sentences are
        credibly the same sentence. Below the floor the "closest match" is a
        different sentence that happens to share vocabulary, and its numbers
        have nothing to say about this one."""
        unrelated = "Red beads and white beads are drawn with a paddle from a bowl of 4000."
        _m, _a, _c, refs = classify_forward(
            [self.PDF], [unrelated], MISSING_THRESHOLD, THRESHOLD
        )
        self.assertEqual(refs, [])

    def test_the_threshold_is_a_parameter_not_a_hardcoded_constant(self):
        _m, _a, _c, refs = classify_forward(
            [self.PDF], [self.QMD], MISSING_THRESHOLD, THRESHOLD, reference_threshold=1.01
        )
        self.assertEqual(refs, [])

    def test_a_missing_paragraph_contributes_no_reference_mismatch(self):
        """Guaranteed structurally: REFERENCE_PAIR_THRESHOLD is well above
        MISSING_SIMILARITY_THRESHOLD, so a paragraph holding a qualifying pair
        cannot itself be missing. Pinned so the two constants can't be re-tuned
        into overlapping without a test going red."""
        self.assertGreater(REFERENCE_PAIR_THRESHOLD, MISSING_THRESHOLD)
        missing, _a, _c, refs = classify_forward(
            [self.PDF], ["Nothing here resembles that sentence at all, page 41."],
            MISSING_THRESHOLD, THRESHOLD,
        )
        self.assertEqual(missing, [self.PDF])
        self.assertEqual(refs, [])

    def test_findings_are_ordered_by_descending_similarity(self):
        """Triage order, matching every other section of the report.

        The two paragraphs share no vocabulary, so each can only match its own
        counterpart; they differ in length, so the same one-number swap costs
        each of them a different amount of similarity.
        """
        long_pdf = (
            "The funnel experiment described on page 41 demonstrates that adjusting a "
            "stable process against the last result makes the variation of the output "
            "substantially worse rather than better."
        )
        short_pdf = "Red beads are drawn with a paddle from a bowl described on page 22."
        _m, _a, _c, refs = classify_forward(
            [short_pdf, long_pdf],
            [short_pdf.replace("page 22", "page 23"), long_pdf.replace("page 41", "page 14")],
            MISSING_THRESHOLD, THRESHOLD,
        )
        self.assertEqual(len(refs), 2)
        self.assertEqual([r[0] for r in refs], sorted((r[0] for r in refs), reverse=True))
        self.assertEqual(refs[0][3], ["page 41"])  # the longer sentence scores higher


class RenderReferenceMismatchesTests(unittest.TestCase):
    def test_shows_both_sides_and_the_similarity(self):
        out = "\n".join(render_reference_mismatches(
            [(0.98, "See page 19 today.", "See page 18 today.", ["page 19"], ["page 18"])],
            REFERENCE_PAIR_THRESHOLD,
        ))
        self.assertIn("Reference mismatch 1 [similarity 98%]", out)
        self.assertIn("PDF only:", out)
        self.assertIn("page 19", out)
        self.assertIn("page 18", out)

    def test_an_empty_side_is_labelled_not_blank(self):
        """A blank after "QMD only:" reads as a rendering bug rather than as
        the finding it is — a number the site dropped entirely."""
        out = "\n".join(render_reference_mismatches(
            [(0.95, "See page 19 [WB 151].", "See page 19.", ["151"], [])],
            REFERENCE_PAIR_THRESHOLD,
        ))
        self.assertIn("(none)", out)


class ReportHeaderContractTests(unittest.TestCase):
    """The KEY=VALUE header is a contract with validate-transcription.sh.

    That script reads every count out of this module's stdout by key. A key
    added here and not read there is a number that silently never reaches the
    provenance record — the same shape of gap #737 found between the files a
    scorer_version hashes and the paths its workflow filters.
    """

    REPO = Path(__file__).resolve().parents[1]
    SCORER = REPO / "scripts" / "lib" / "paragraph_similarity.py"
    VALIDATOR = REPO / "scripts" / "validate-transcription.sh"

    def run_scorer(self, pdf_paras, qmd_paras):
        with tempfile.TemporaryDirectory() as tmp:
            pdf_path = Path(tmp) / "pdf.txt"
            qmd_path = Path(tmp) / "qmd.txt"
            pdf_path.write_text("\n".join(pdf_paras) + "\n", encoding="utf-8")
            qmd_path.write_text("\n".join(qmd_paras) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(self.SCORER), str(pdf_path), str(qmd_path)],
                capture_output=True, text=True, check=True,
            )
        header, _, body = result.stdout.partition("\n\n")
        return dict(line.split("=", 1) for line in header.splitlines()), body

    def test_every_header_key_is_read_by_the_validator(self):
        header, _ = self.run_scorer(["A paragraph about page 19."], ["A paragraph about page 18."])
        script = self.VALIDATOR.read_text(encoding="utf-8")
        unread = [key for key in header if f"s/^{key}=//p" not in script]
        self.assertEqual(unread, [], f"printed but never parsed by {self.VALIDATOR.name}")

    def test_the_new_counts_reach_the_provenance_record(self):
        """Parsed is not the same as recorded — #720's result files are the
        only durable trace a run leaves."""
        script = self.VALIDATOR.read_text(encoding="utf-8")
        self.assertIn("reference_mismatches: $reference", script)
        self.assertIn("reference: $reference_threshold", script)

    def test_a_reference_mismatch_is_reported_even_when_everything_is_clean(self):
        """The whole point, end to end through the CLI: nothing is missing,
        altered or unsourced, and the section is still there to be read."""
        pdf = [ReferenceEscapeClassTests.LIVE_PDF]
        qmd = [ReferenceEscapeClassTests.LIVE_QMD]
        header, body = self.run_scorer(pdf, qmd)
        self.assertEqual(header["ALTERED_COUNT"], "0")
        self.assertEqual(header["MISSING_COUNT"], "0")
        self.assertEqual(header["MATCHED_COUNT"], "1")
        self.assertEqual(header["REFERENCE_MISMATCHES"], "1")
        self.assertEqual(float(header["REFERENCE_THRESHOLD"]), REFERENCE_PAIR_THRESHOLD)
        self.assertIn("Reference Mismatches", body)
        self.assertIn("page 35", body)


if __name__ == "__main__":
    unittest.main()
