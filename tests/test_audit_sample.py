"""Tests for the Wave 3 sampling audit (#746): scripts/sample-audit.py and the
two modules behind it, scripts/lib/audit_sample.py and audit_population.py.

A published fidelity bound rests on three things this suite pins, and each can
go wrong while producing a perfectly plausible page:

  - **The draw is reproducible.** Same seed, same content, same cards and same
    plants — or an audit cannot be re-checked, and a re-draw cannot be told
    apart from a chosen sample.
  - **A plant is a fair test.** It must show on the card, inside text the
    paragraph actually covers, as the kind of slip Wave 2 found. A plant hidden
    in a link target is uncatchable and deflates the measured sensitivity; one
    that mangles the grammar is a proofreading catch and inflates it.
  - **The arithmetic is right.** Plants out of n, real defects out of the
    plants, and the bound divided by sensitivity rather than multiplied.

Everything except the final class runs without the source PDFs or pandoc, so
it runs in CI. The final class draws a real record, and skips where the PDFs
are absent — which is everywhere but the maintainer's machine (see #720).

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

import audit_population as ap  # noqa: E402
import audit_sample as sample  # noqa: E402
import paragraph_similarity as ps  # noqa: E402
import paragraphs as pg  # noqa: E402
import qmd_strip  # noqa: E402


def load_cli():
    spec = importlib.util.spec_from_file_location("sample_audit", REPO_ROOT / "scripts" / "sample-audit.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cli = load_cli()


class TestSeededChoice(unittest.TestCase):
    def test_rank_is_deterministic_and_ignores_input_order(self):
        items = [f"paragraph {i}" for i in range(50)]
        first = sample.rank(items, lambda x: (x,), 771, "day-05", "draw")
        again = sample.rank(list(reversed(items)), lambda x: (x,), 771, "day-05", "draw")
        self.assertEqual(first, again)

    def test_a_different_seed_or_record_draws_differently(self):
        items = [f"paragraph {i}" for i in range(50)]
        base = sample.rank(items, lambda x: (x,), 771, "day-05", "draw")[:20]
        self.assertNotEqual(base, sample.rank(items, lambda x: (x,), 772, "day-05", "draw")[:20])
        self.assertNotEqual(base, sample.rank(items, lambda x: (x,), 771, "day-06", "draw")[:20])

    def test_planted_count_varies_within_the_protocol_range(self):
        """2–4 in twenty, and all three occur — a fixed count tells the auditor when to stop."""
        counts = {sample.planted_count(seed, "day-05", 20) for seed in range(200)}
        self.assertEqual(counts, {2, 3, 4})

    def test_planted_count_scales_down_but_never_to_zero(self):
        self.assertTrue({sample.planted_count(s, "welcome", 5) for s in range(50)} <= {1})
        self.assertEqual({sample.planted_count(s, "day-01", 10) for s in range(200)}, {1, 2})


def kinds_of(raw):
    return {(p.kind, raw[p.start:p.end], p.replacement) for p in sample.candidates(1, raw)}


class TestCandidates(unittest.TestCase):
    def test_substitution_keeps_the_case_of_the_word_it_replaces(self):
        found = kinds_of("Will it help? It will.")
        self.assertIn(("substitution", "Will", "May"), found)
        self.assertIn(("substitution", "will", "may"), found)

    def test_a_one_letter_capital_takes_its_case_from_the_next_word(self):
        self.assertIn(("substitution", "A", "THE"), kinds_of("## DAY 9: A SYSTEM OF PROFOUND KNOWLEDGE"))
        self.assertIn(("substitution", "A", "The"), kinds_of("A new climate indeed"))

    def test_the_becomes_a_only_before_a_consonant(self):
        self.assertIn(("substitution", "the", "a"), kinds_of("into the statement"))
        self.assertNotIn(("substitution", "the", "a"), kinds_of("into the idea"))

    def test_insertions_only_before_a_content_word(self):
        good = kinds_of("Day 5 is devoted to the rest")
        self.assertIn(("inserted-word", "", " also"), good)
        for awkward in ("no worker has much control", "I have therefore suggested", "it is surely wrong"):
            with self.subTest(awkward=awkward):
                self.assertFalse({k for k in kinds_of(awkward) if k[0] == "inserted-word"})

    def test_number_changes_one_digit(self):
        self.assertIn(("number", "8", "9"), kinds_of("28 years after the war"))
        self.assertIn(("number", "9", "8"), kinds_of("as I implied on page 19"))

    def test_exclamation_both_ways(self):
        self.assertIn(("exclamation", ".", "!"), kinds_of("It works. Then more."))
        self.assertIn(("exclamation", "!", "."), kinds_of("Wrong! The world changes."))

    def test_an_image_marker_is_not_an_exclamation(self):
        self.assertFalse({k for k in kinds_of("![A chart](x.png)") if k[0] == "exclamation"})

    def test_emphasis_only_on_short_runs(self):
        self.assertIn(("emphasis", "*transformation*", "transformation"), kinds_of("a *transformation* of style"))
        long_run = "**Short-term thinking defeats constancy of purpose.**"
        self.assertFalse({k for k in kinds_of(long_run) if k[0] == "emphasis"})

    def test_escaped_asterisks_are_not_emphasis(self):
        found = {k for k in kinds_of(r"the \*\*\* wire *breaks* now") if k[0] == "emphasis"}
        self.assertEqual(found, {("emphasis", "*breaks*", "breaks")})

    def test_nothing_is_planted_inside_math_or_code(self):
        found = kinds_of("the mean $\\bar{X} = 12$ and `x = 5` here")
        self.assertFalse({k for k in found if k[0] == "number"})


def plant_for(raw, kind, before, after):
    matches = [p for p in sample.candidates(1, raw)
               if p.kind == kind and raw[p.start:p.end] == before and p.replacement == after]
    if not matches:
        raise AssertionError(f"no {kind} candidate {before!r} -> {after!r} in {raw!r}")
    return matches[0]


class TestValidate(unittest.TestCase):
    LINK = "As I implied on [page 19, the guidance for the Second Project](../x.qmd#sec-page19), it will help."

    def full_span(self, lines):
        return [(0, len(sample.excerpt_text(lines)))]

    def test_a_wrong_page_number_in_an_enriched_link_is_plantable(self):
        """The most consequential defect class: the probe method used to reject it."""
        lines = [(1, self.LINK)]
        self.assertTrue(sample.validate(plant_for(self.LINK, "number", "9", "8"), lines, self.full_span(lines)))

    def test_a_change_in_the_enriched_descriptor_is_invisible_to_the_comparison(self):
        lines = [(1, self.LINK)]
        plant = plant_for(self.LINK, "substitution", "the", "a")  # "the guidance"
        self.assertFalse(sample.validate(plant, lines, self.full_span(lines)))

    def test_a_change_in_a_link_target_is_rejected(self):
        raw = "See [the notes](../notes/the/will.qmd#sec-page5) now."
        lines = [(1, raw)]
        target = [p for p in sample.candidates(1, raw) if raw.index("](") < p.start < raw.index(") now")]
        self.assertTrue(target)
        for plant in target:
            with self.subTest(plant=plant):
                self.assertFalse(sample.validate(plant, lines, self.full_span(lines)))

    def test_a_change_outside_the_matched_sentences_is_rejected(self):
        raw = "It will help. The next paragraph will not."
        lines = [(1, raw)]
        first_sentence = [(0, len("It will help."))]
        early = plant_for(raw, "substitution", "will", "may")
        late = [p for p in sample.candidates(1, raw) if p.kind == "substitution" and p.start > 20][0]
        self.assertTrue(sample.validate(early, lines, first_sentence))
        self.assertFalse(sample.validate(late, lines, first_sentence))

    def test_dropped_emphasis_is_located_by_its_text(self):
        raw = "He was concerned with *transformation* here. Unrelated *tail* text."
        lines = [(1, raw)]
        spans = [(0, len("He was concerned with transformation here."))]
        self.assertTrue(sample.validate(plant_for(raw, "emphasis", "*transformation*", "transformation"), lines, spans))
        self.assertFalse(sample.validate(plant_for(raw, "emphasis", "*tail*", "tail"), lines, spans))

    def test_choose_plant_is_deterministic(self):
        lines = [(4, "Day 5 is devoted to 28 of the *best* ideas. It will help."), (5, "Wrong! The end.")]
        spans = self.full_span(lines)
        once = sample.choose_plant(771, "day-05", "A-01", lines, spans)
        self.assertEqual(once, sample.choose_plant(771, "day-05", "A-01", lines, spans))
        outcomes = {sample.choose_plant(seed, "day-05", "A-01", lines, spans) for seed in range(40)}
        self.assertGreater(len({p.kind for p in outcomes}), 2)


class TestBound(unittest.TestCase):
    def test_no_defects_is_one_minus_alpha_to_the_one_over_n(self):
        self.assertAlmostEqual(sample.upper_bound(0, 20), 1 - 0.05 ** (1 / 20), places=6)

    def test_bound_rises_with_defects_and_reaches_one(self):
        values = [sample.upper_bound(d, 20) for d in range(21)]
        self.assertEqual(values, sorted(values))
        self.assertEqual(values[-1], 1.0)

    def test_sensitivity_divides_the_bound(self):
        result = sample.adjusted_bound(0, 17, planted=3, caught=2)
        self.assertAlmostEqual(result["adjusted_upper"], min(1, result["upper"] / (2 / 3)), places=3)
        self.assertGreater(result["adjusted_upper"], result["upper"])

    def test_no_catches_supports_no_claim(self):
        self.assertEqual(sample.adjusted_bound(0, 17, planted=3, caught=0)["adjusted_upper"], 1.0)
        self.assertEqual(sample.adjusted_bound(0, 17, planted=0, caught=0)["adjusted_upper"], 1.0)


@unittest.skipUnless(shutil.which("ruby"), "ruby not installed")
class TestYaml(unittest.TestCase):
    def test_round_trips_through_a_real_yaml_parser(self):
        record = {
            "record": "day-05",
            "seed": 771,
            "bound": {"upper": 0.1616, "sensitivity": None},
            "findings": [],
            "paragraphs": [
                {"id": "A-01", "note": 'No: - yes, "quoted"\nand a second line — Neave’s', "planted": None},
                {"id": "A-02", "note": None, "planted": {"kind": "number", "from": "9", "to": "8", "caught": True}},
            ],
        }
        done = subprocess.run(
            ["ruby", "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.safe_load(STDIN.read))"],
            input=sample.to_yaml(record), capture_output=True, text=True, check=True,
        )
        self.assertEqual(json.loads(done.stdout), record)


QMD_A = """---
title: "A CHAPTER"
pagetitle: "x"
---

## The Deming Prize {#sec-page2}

Deming was born in 1900. He *always* said so.
It was a very long life.

```{r}
x <- 1
```

::: {.callout-note}
Why?
:::

[WB 12]

---

Another paragraph here, which is long enough to be compared.
"""


class TestLineProvenance(unittest.TestCase):
    def test_every_kept_line_carries_its_source_line_number(self):
        kept = ap.stripped_lines(QMD_A)
        lines = QMD_A.split("\n")
        for number, text in kept:
            with self.subTest(line=number):
                self.assertEqual(qmd_strip.strip_qmd(lines[number - 1] + "\n").rstrip("\n"), text)
        numbers = [n for n, _ in kept]
        for dropped, why in ((2, "front matter"), (12, "code"), (15, "layout directive"),
                             (19, "workbook citation alone on its line"), (21, "horizontal rule")):
            with self.subTest(dropped=why):
                self.assertNotIn(dropped, numbers)
        self.assertIn(16, numbers)  # prose inside a callout is still prose

    def test_blocks_collapse_as_read_blocks_does(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.qmd"
            path.write_text(QMD_A, encoding="utf-8")
            ours = [b.text for b in ap.site_blocks(path)]
        theirs = [b.text for b in pg.read_blocks(qmd_strip.strip_qmd(QMD_A))]
        self.assertEqual(ours, theirs)

    def test_paged_paragraphs_agree_with_to_paragraphs(self):
        text = pg.mark_pages("A first paragraph that is long enough to keep.\n\nshort\n\n\f"
                             "It continues onto the next page and is long enough:\n\nA. an item;\n\nB. another.\n")
        paged = ap.paged_paragraphs(text)
        self.assertEqual([b.text for b in paged], pg.to_paragraphs(text))
        self.assertEqual([b.page for b in paged], [1, 2])


class TestLocate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.a = root / "01-a.qmd"
        self.b = root / "02-b.qmd"
        self.a.write_text(
            "Why?\n\nIntroductory text about the prize, which runs long enough.\n\n"
            "He was concerned with *transformation* of management.\n"
            "He was working toward the very best way of managing.\n"
            "His aim was a management system for everyone concerned.\n",
            encoding="utf-8",
        )
        self.b.write_text(
            "A later chapter says something else entirely, at length.\n\n"
            "The purpose of the next stage is to look closer. Why?\n",
            encoding="utf-8",
        )
        self.setUp_pool()

    def setUp_pool(self):
        files = [self.a, self.b]
        combined = ap.qmd_combined(files)
        self.pop = ap.Population(
            record=ap.Record("test", Path("x.pdf"), files, Path("x.yml")),
            results={},
            paragraphs=[],
            qmd_pool=ps.build_pool(pg.to_paragraphs(combined)),
            short_pool=ps.build_pool([b.text for b in pg.sift(combined).short]),
        )
        self.blocks = {f: ap.site_blocks(f) for f in files}

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_hard_wrapped_block_is_trimmed_to_the_lines_matched(self):
        para = ap.Paragraph("His aim was a management system for everyone concerned.", 3, 0)
        excerpt = ap.locate(para, self.pop, self.blocks)
        self.assertEqual(excerpt.file, self.a)
        self.assertEqual([n for _, n in excerpt.lines], [7])
        self.assertEqual(excerpt.text, "His aim was a management system for everyone concerned.")

    def test_a_sentence_matched_far_away_is_named_not_spanned(self):
        para = ap.Paragraph("The purpose of the next stage is to look closer. Why?", 9, 0)
        excerpt = ap.locate(para, self.pop, self.blocks)
        self.assertEqual(excerpt.file, self.b)
        self.assertEqual(excerpt.elsewhere, [])  # "Why?" sits in the same block too
        para = ap.Paragraph("Introductory text about the prize, which runs long enough. "
                            "A later chapter says something else entirely, at length.", 2, 0)
        excerpt = ap.locate(para, self.pop, self.blocks)
        self.assertEqual(len(excerpt.elsewhere), 1)
        self.assertEqual(excerpt.elsewhere[0][1:], (self.b, 1))

    def test_a_sentence_no_run_of_blocks_holds_gets_no_line_number(self):
        """Pointing at the chosen run's first line instead would send the auditor somewhere unrelated."""
        self.b.write_text(
            "Introductory text about the prize, which runs long enough.\n\n"
            "Here are the data that were used for the computation:\n\n"
            "the first of the many subgroups, in time order.\n",
            encoding="utf-8",
        )
        self.setUp_pool()
        para = ap.Paragraph("Introductory text about the prize, which runs long enough. Here are the data "
                            "that were used for the computation: the first of the many subgroups, in time order.", 2, 0)
        original = ap._MAX_JOIN
        ap._MAX_JOIN = 1  # the colon join now needs a wider run than any window allows
        try:
            excerpt = ap.locate(para, self.pop, self.blocks)
        finally:
            ap._MAX_JOIN = original
        self.assertEqual([(w, n) for _, w, n in excerpt.elsewhere], [(None, None)])


class TestLiftFunction(unittest.TestCase):
    def test_lifts_the_real_extraction_function_whole(self):
        definition = ap.lift_function(ap.VALIDATOR.read_text(encoding="utf-8"), "extract_pdf_text")
        self.assertTrue(definition.rstrip().endswith("}"))
        self.assertIn("pdf_callouts.py", definition)  # the pipeline's last stage

    def test_a_column_zero_brace_inside_the_body_is_refused_by_name(self):
        source = "f() {\n  a\n}\n  echo still inside\n}\n\n# next\n"
        with self.assertRaisesRegex(ap.PopulationError, "did not lift cleanly"):
            ap.lift_function(source, "f")

    def test_a_whole_function_followed_by_the_next_is_accepted(self):
        source = "f() {\n  a\n}\n\ng() {\n  b\n}\n"
        self.assertEqual(ap.lift_function(source, "f"), "f() {\n  a\n}\n")


class TestReadResults(unittest.TestCase):
    def test_reads_the_fields_the_draw_checks(self):
        data = ap.read_results(REPO_ROOT / "workflow" / "validation" / "results" / "day-05.yml")
        self.assertRegex(data["scorer_version"], r"^[0-9a-f]{40}$")
        self.assertRegex(data["source_sha256"], r"^[0-9a-f]{64}$")
        self.assertTrue(data["counts"]["matched_cleanly"].isdigit())


class TestBalance(unittest.TestCase):
    def test_closes_what_an_excerpt_leaves_open(self):
        self.assertEqual(cli.balance('<div class="x"><p>text</p>'), '<div class="x"><p>text</p></div>')

    def test_drops_a_closer_with_no_opener(self):
        self.assertEqual(cli.balance("<p>text</p></div>"), "<p>text</p>")

    def test_keeps_entities_and_void_elements(self):
        self.assertEqual(cli.balance("a &amp; b<br>c"), "a &amp; b<br>c")


def page_and_key():
    items = [
        {"id": f"A-{i:02d}", "pdf_page": 5 + i, "file": "01-a.qmd", "lines": str(10 + i), "line": 10 + i}
        for i in range(1, 6)
    ]
    page = {
        "pass": "audit-day-99-abc", "source_pdf": "Z.pdf", "scorer_version": "f" * 40,
        "content_dir": "content/days/day-99",
        "audit": {"record": "day-99", "seed": 1, "cards": 5, "population": 50, "commit": "c" * 40,
                  "drawn_at": "2026-09-13"},
        "sections": [{"items": items}],
    }
    key = {"pass": "audit-day-99-abc", "planted": [
        {"id": "A-02", "kind": "number", "line": 12, "from": "9", "to": "8"},
        {"id": "A-04", "kind": "emphasis", "line": 14, "from": "*best*", "to": "best"},
    ]}
    return page, key


def verdicts(decisions, pass_name="audit-day-99-abc"):
    return {"pass": pass_name, "decisions": [
        {"id": i, "decision": d, "note": None if d == "accept" else "note"} for i, d in decisions.items()
    ]}


class TestScore(unittest.TestCase):
    def test_plants_and_real_defects_are_counted_apart(self):
        page, key = page_and_key()
        result = cli.score(page, key, verdicts(
            {"A-01": "reject", "A-02": "reject", "A-03": "accept", "A-04": "discuss", "A-05": "accept"}
        ), auditor="Lee", today="2026-09-20")
        self.assertEqual(result["sample"], {"cards": 5, "audited": 3, "planted": 2})
        self.assertEqual(result["plants"], {"planted": 2, "caught": 1})
        self.assertEqual(result["bound"]["real_defects"], 1)
        self.assertEqual([f["id"] for f in result["findings"]], ["A-01"])
        self.assertEqual(result["verdicts"], {"exact": 2, "trivial": 1, "defect": 2})
        planted = {p["id"]: p["planted"] for p in result["paragraphs"]}
        self.assertTrue(planted["A-02"]["caught"])
        self.assertFalse(planted["A-04"]["caught"])  # trivial is not a catch
        self.assertEqual(result["paragraphs"][0]["file"], "content/days/day-99/01-a.qmd")

    def test_other_defect_is_a_finding_and_a_missed_plant(self):
        page, key = page_and_key()
        result = cli.score(page, key, verdicts(
            {"A-01": "accept", "A-02": "reject", "A-03": "accept", "A-04": "accept", "A-05": "accept"}
        ), auditor="Lee", other_defects={"A-02"})
        self.assertEqual(result["plants"]["caught"], 0)
        self.assertEqual([f["id"] for f in result["findings"]], ["A-02"])
        self.assertEqual(result["bound"]["real_defects"], 0)  # outside n

    def test_refuses_verdicts_from_another_draw(self):
        page, key = page_and_key()
        with self.assertRaisesRegex(ValueError, "same draw"):
            cli.score(page, key, verdicts({f"A-0{i}": "accept" for i in range(1, 6)}, "audit-day-99-zzz"), "Lee")

    def test_refuses_an_undecided_card(self):
        page, key = page_and_key()
        with self.assertRaisesRegex(ValueError, "undecided"):
            cli.score(page, key, verdicts({"A-01": "undecided", **{f"A-0{i}": "accept" for i in range(2, 6)}}), "Lee")

    def test_refuses_other_defect_on_an_unplanted_card(self):
        page, key = page_and_key()
        with self.assertRaisesRegex(ValueError, "not planted"):
            cli.score(page, key, verdicts({f"A-0{i}": "reject" for i in range(1, 6)}), "Lee", other_defects={"A-01"})


class TestTemplateOverrides(unittest.TestCase):
    TEMPLATE = (REPO_ROOT / "workflow" / "validation" / "adjudication" / "template.html").read_text(encoding="utf-8")

    def test_every_default_wave_2_wording_is_still_the_default(self):
        for wording in ('"Accepted"', '"Declined"', '"findings"', "Anything I should know before making this edit"):
            with self.subTest(wording=wording):
                self.assertIn(wording, self.TEMPLATE)

    def test_the_overrides_an_audit_page_sets_are_read(self):
        for field in ("noun", "filters", "keys", "note_placeholder", "reject_tone", "outro_html"):
            with self.subTest(field=field):
                self.assertIn(f"UI.{field}", self.TEMPLATE)


PDFS = REPO_ROOT / "12-Days-to-Deming" / "PDFs"


@unittest.skipUnless(PDFS.is_dir() and (shutil.which("pandoc") or shutil.which("quarto")),
                     "source PDFs and pandoc are only on the maintainer's machine")
class TestDrawEndToEnd(unittest.TestCase):
    """Draws Day 5 twice for real: the determinism claim, end to end.

    Seeds 1 and 2, never 771: that is Day 5's real audit seed (its Wave 2 pass
    issue), and a failing assertEqual on the key would print the real plants to
    the terminal of the person who is going to audit them.
    """

    def draw(self, out, seed):
        done = subprocess.run(
            [sys.executable, str(REPO_ROOT / "scripts" / "sample-audit.py"), "draw", "day-05",
             "--seed", str(seed), "--allow-dirty", "--output-dir", str(out)],
            capture_output=True, text=True,
        )
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("planted", done.stdout.lower().replace("planted-defect", ""))
        return (json.loads((out / "day-05.sample.json").read_text()),
                json.loads((out / "day-05.key.json").read_text()),
                (out / "day-05.html").read_text())

    def test_same_seed_same_draw_and_nothing_of_the_key_on_the_page(self):
        with tempfile.TemporaryDirectory() as tmp:
            one = self.draw(Path(tmp) / "one", 1)
            two = self.draw(Path(tmp) / "two", 1)
            other = self.draw(Path(tmp) / "other", 2)
        self.assertEqual(one[0], two[0])
        self.assertTrue(one[1] == two[1], "same seed drew different plants")
        self.assertNotEqual(one[0]["pass"], other[0]["pass"])
        page, key, html = one
        self.assertIn(len(key["planted"]), (2, 3, 4))
        for secret in ("context_before", "context_after", '"planted"'):
            self.assertNotIn(secret, html)
        for plant in key["planted"]:
            card = next(i for i in page["sections"][0]["items"] if i["id"] == plant["id"])
            self.assertNotIn("plant", json.dumps(card).lower())


if __name__ == "__main__":
    unittest.main()
