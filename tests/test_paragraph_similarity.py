"""Tests for scripts/lib/paragraph_similarity.py.

Issue #677 asked for the altered-content scorer to catch the real transcription
defects from #676, and allowed that acceptance to be verified by hand. Hand
verification doesn't survive a refactor, so the defect shapes are pinned here
instead: each `test_catches_*` case reproduces one real defect found in Day 4's
transcription, with the wording that actually shipped.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts" / "lib"))

from paragraph_similarity import (  # noqa: E402
    ALTERED_SIMILARITY_THRESHOLD as THRESHOLD,
    NEAR_MATCH_SCORE,
    analyse,
    diff_window,
    find_best_sentence,
    normalise,
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


if __name__ == "__main__":
    unittest.main()
