"""Tests that every page the book serves has a stated source — issue #802.

Before #802 the validation system was addressed by directory: a manifest named
a `content_dir` and `scripts/validate-transcription.sh` globbed `*.qmd` inside
it. That made "which source PDF is this page answerable to?" a question about
where a file sits on disk, and it went wrong in both directions at once.

  - `content/appendix/11-references-and-sources.qmd` was compared against
    `P.Appendix.09Feb22.pdf`, which contains none of it, because it shares a
    directory with eleven chapters that do come from there. Its real source,
    `R.References.and.Sources.09Feb22.pdf`, was opened by no run at all.
  - `index.qmd` and `welcome.qmd` sat in no manifest's directory, so they were
    compared against nothing, and nothing said so.
  - `content/appendix/glossary.qmd` has no source PDF and never did, but that
    was indistinguishable from the two cases above.

The result was 69 structural entries in one run's 70 "unsourced" findings,
sitting beside the single real one with nothing to tell them apart.

So the property worth pinning is not about any one file: it is that the set of
pages the book serves, the set of pages some manifest claims, and the set of
pages declared to have no source at all, line up exactly — with no page in two
of them and none in neither.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
VALIDATION = REPO_ROOT / "workflow" / "validation"
BOOK = REPO_ROOT / "_quarto-en.yml"
NO_SOURCE = VALIDATION / "no-source.yml"
PDF_DIR = REPO_ROOT / "12-Days-to-Deming" / "PDFs"

# These files are parsed with regexes rather than a YAML library on purpose:
# .github/workflows/scorer-tests.yml runs this suite with nothing but a
# checkout and `python3`, and states that the absence of a dependency step is
# what makes it cheap enough to run on every PR. The readers below are strict —
# a shape they don't recognise raises rather than quietly returning nothing —
# so a change to how these files are written breaks this test loudly instead of
# turning it into a check that passes by finding nothing to check.


def book_pages():
    """Every .qmd `_quarto-en.yml` lists, in book order.

    Matches both a plain chapter entry and the `part:` form that opens a
    section with a real page (`- part: content/appendix/optional-extras/…`).
    """
    pages = re.findall(
        r"^\s*-\s*(?:part:\s*)?(\S+\.qmd)\s*$",
        BOOK.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if not pages:
        raise AssertionError(f"no chapters found in {BOOK} — has its shape changed?")
    return pages


def manifest_pages():
    """Map each page claimed by a manifest to the manifest claiming it.

    Day manifests carry no `content_dir`; their chapters live at the
    convention-derived `content/days/day-NN/`, which is the same rule
    check-structure.sh applies.
    """
    claimed = {}
    for manifest in sorted(VALIDATION.glob("*-manifest.yml")):
        text = manifest.read_text(encoding="utf-8")
        name = manifest.name[: -len("-manifest.yml")]

        content_dir = re.search(r"^content_dir:\s*[\"']?(.+?)[\"']?\s*$", text, re.MULTILINE)
        if content_dir:
            base = content_dir.group(1)
        elif name.startswith("day-"):
            base = f"content/days/{name}"
        else:
            raise AssertionError(f"{manifest.name} declares no content_dir")

        files = re.findall(r"^\s*-\s*file:\s*[\"'](.+?)[\"']\s*$", text, re.MULTILINE)
        if not files:
            raise AssertionError(f"{manifest.name} lists no chapters — has its shape changed?")

        for f in files:
            path = f if base == "." else f"{base}/{f}"
            claimed.setdefault(path, []).append(manifest.name)
    return claimed


def no_source_pages():
    """Pages declared to have no source PDF, mapped to their stated reason."""
    text = NO_SOURCE.read_text(encoding="utf-8")
    body = text.split("\npages:\n", 1)
    if len(body) != 2:
        raise AssertionError(f"{NO_SOURCE.name} has no `pages:` block")
    entries = re.findall(r"^  (\S+\.qmd):\s*(.*?)$", body[1], re.MULTILINE)
    if not entries:
        raise AssertionError(f"{NO_SOURCE.name} declares no pages — has its shape changed?")
    return dict(entries)


class BookPagesAreAccountedFor(unittest.TestCase):
    """The three sets partition the book: claimed, declared sourceless, nothing else."""

    def setUp(self):
        self.pages = book_pages()
        self.claimed = manifest_pages()
        self.sourceless = no_source_pages()
        # What a run actually compares. The two lists answer different
        # questions and are allowed to overlap: a manifest's `chapters:` is
        # what check-structure.sh walks for headings and figure references,
        # and content/appendix/glossary.qmd belongs there like any other
        # chapter. What it has not got is a source PDF. So no-source.yml wins,
        # and validate-transcription.sh subtracts it from the file list rather
        # than comparing a site original against a book that never contained
        # it — the overlap is the mechanism, not a mistake.
        self.validated = {
            page: names
            for page, names in self.claimed.items()
            if page not in self.sourceless
        }

    def test_every_page_the_book_serves_has_a_stated_source(self):
        unaccounted = [
            p for p in self.pages if p not in self.claimed and p not in self.sourceless
        ]
        self.assertEqual(
            [],
            unaccounted,
            "These pages are in no manifest and are not declared sourceless, so no "
            "validation run compares them and nothing records that fact — the exact "
            "state index.qmd and welcome.qmd were in before #802. Either add the page "
            "to the manifest for its source PDF, or declare it in "
            "workflow/validation/no-source.yml with the reason.",
        )

    def test_no_page_is_claimed_by_two_manifests(self):
        doubled = {p: m for p, m in self.validated.items() if len(m) > 1}
        self.assertEqual(
            {},
            doubled,
            "A page claimed by two manifests would be compared against two different "
            "source PDFs and score as unsourced against at least one of them.",
        )

    def test_every_manifest_still_validates_at_least_one_page(self):
        """A manifest whose whole chapter list is declared sourceless opens no PDF.

        It would pass every other check here — its pages are accounted for, and
        none is claimed twice — while quietly restoring the state #802 fixed:
        a source PDF that no run reads, and no record saying so.
        """
        by_manifest = {}
        for page, names in self.claimed.items():
            for name in names:
                by_manifest.setdefault(name, []).append(page)
        for name, pages in sorted(by_manifest.items()):
            with self.subTest(manifest=name):
                self.assertTrue(
                    [p for p in pages if p not in self.sourceless],
                    f"{name} declares chapters but every one is declared sourceless, "
                    f"so its source PDF is never opened",
                )

    def test_declared_sourceless_pages_carry_a_reason(self):
        """An entry with no reason is the absence this file exists to replace."""
        for page, reason in sorted(self.sourceless.items()):
            with self.subTest(page=page):
                self.assertTrue(
                    reason.strip(),
                    f"{page} is declared sourceless with no reason given",
                )

    def test_every_declared_page_exists(self):
        for page in sorted(set(self.claimed) | set(self.sourceless)):
            with self.subTest(page=page):
                self.assertTrue(
                    (REPO_ROOT / page).is_file(), f"{page} is declared but does not exist"
                )


class ManifestsNameRealSourcePdfs(unittest.TestCase):
    """Each non-day manifest points at a PDF, and no two point at the same one."""

    def setUp(self):
        self.pdfs = {}
        for manifest in sorted(VALIDATION.glob("*-manifest.yml")):
            if manifest.name.startswith("day-"):
                continue
            m = re.search(r"^pdf_file:\s*(.+?)\s*$", manifest.read_text(encoding="utf-8"), re.MULTILINE)
            self.assertIsNotNone(m, f"{manifest.name} declares no pdf_file")
            self.pdfs.setdefault(m.group(1), []).append(manifest.name)

    def test_no_two_manifests_claim_the_same_source_pdf(self):
        shared = {pdf: names for pdf, names in self.pdfs.items() if len(names) > 1}
        self.assertEqual({}, shared, "Two manifests comparing against one PDF would each "
                                     "report the other's chapters as missing from it.")

    @unittest.skipUnless(PDF_DIR.is_dir(), "source PDFs are gitignored and local-only (#720)")
    def test_declared_source_pdfs_exist(self):
        """Skipped in CI by design: the PDFs live only on the maintainer's machine."""
        for pdf in sorted(self.pdfs):
            with self.subTest(pdf=pdf):
                self.assertTrue((PDF_DIR / pdf).is_file(), f"{pdf} is not in {PDF_DIR}")


if __name__ == "__main__":
    unittest.main()
