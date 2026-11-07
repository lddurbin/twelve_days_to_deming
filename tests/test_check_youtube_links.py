"""Tests for scripts/check-youtube-links.py — the oEmbed check lychee can't do.

YouTube answers HTTP 200 for a video or playlist that doesn't exist, so the
status-code check in link-check.yml can never see a dead YouTube link (#805).
These tests pin the parts that decide what gets checked and what counts as
dead, with the network stubbed out, plus the workflow wiring: a checker the
weekly run never calls would be the same blind spot with extra steps.

Run with:  python3 -m unittest discover -s tests -p 'test_*.py'
"""
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "check-youtube-links.py"
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "link-check.yml"

spec = importlib.util.spec_from_file_location("check_youtube_links", SCRIPT)
yt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(yt)

LIVE = "https://www.youtube.com/watch?v=ehMAwIHGN0Y"
# #420's mistranscription: a capital I read as an 8.
DEAD = "https://www.youtube.com/watch?v=ehMAw8HGN0Y"


class CanonicalTest(unittest.TestCase):
    def test_watch_url_keeps_only_the_video_id(self):
        self.assertEqual(
            yt.canonical("https://www.youtube.com/watch?v=ehMAwIHGN0Y&t=30s&list=PLx"),
            LIVE,
        )

    def test_short_and_mobile_hosts_resolve_to_the_watch_url(self):
        self.assertEqual(yt.canonical("https://youtu.be/ehMAwIHGN0Y"), LIVE)
        self.assertEqual(yt.canonical("https://m.youtube.com/watch?v=ehMAwIHGN0Y"), LIVE)
        self.assertEqual(yt.canonical("http://youtube.com/watch?v=ehMAwIHGN0Y"), LIVE)

    def test_playlist_url(self):
        self.assertEqual(
            yt.canonical("https://www.youtube.com/playlist?list=PLCADAD3F2F91BD570"),
            "https://www.youtube.com/playlist?list=PLCADAD3F2F91BD570",
        )

    def test_urls_that_name_no_single_video_are_skipped(self):
        for url in (
            "https://www.youtube.com/@DemingInstitute",
            "https://www.youtube.com/watch",
            "https://www.youtube.com/playlist",
            "https://youtu.be/",
        ):
            with self.subTest(url=url):
                self.assertIsNone(yt.canonical(url))


class FindLinksTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "content" / "days").mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        path = self.root / rel
        path.write_text(text, encoding="utf-8")
        return path

    def links(self):
        return yt.find_links(yt.corpus_files(self.root), self.root)

    def test_markdown_link_autolink_and_bare_url_with_trailing_period(self):
        self.write(
            "content/days/a.qmd",
            "See [the talk](https://youtu.be/ehMAwIHGN0Y).\n"
            "Or <https://www.youtube.com/watch?v=ehMAwIHGN0Y>, or\n"
            "https://www.youtube.com/watch?v=ehMAwIHGN0Y.\n",
        )
        self.assertEqual(
            [site for _, site in self.links()[LIVE]],
            ["content/days/a.qmd:1", "content/days/a.qmd:2", "content/days/a.qmd:3"],
        )

    def test_scope_matches_lychee_content_and_root_qmd_only(self):
        self.write("content/days/a.qmd", f"[x]({LIVE})\n")
        self.write("index.qmd", f"[x]({DEAD})\n")
        self.write("README.md", "[x](https://youtu.be/notscanned1)\n")
        self.assertEqual(set(self.links()), {LIVE, DEAD})


class ClassifyTest(unittest.TestCase):
    def test_live_reports_the_title(self):
        self.assertEqual(
            yt.classify(200, {"title": "Dr. Deming - The 5 Deadly Diseases 1984"}),
            ("live", "Dr. Deming - The 5 Deadly Diseases 1984"),
        )

    def test_not_found_and_malformed_ids_are_dead(self):
        for status in (404, 400):
            with self.subTest(status=status):
                self.assertEqual(yt.classify(status, None)[0], "dead")

    def test_anything_oembed_cannot_settle_is_unverified_not_dead(self):
        for status in (401, 403, 429, 500, None):
            with self.subTest(status=status):
                self.assertEqual(yt.classify(status, None)[0], "unverified")


class MainTest(unittest.TestCase):
    def run_main(self, responses):
        links = {url: [(url, "content/x.qmd:1")] for url in responses}
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(yt, "find_links", return_value=links), \
                mock.patch.object(yt, "fetch_oembed", side_effect=lambda u: responses[u]), \
                mock.patch("sys.stdout"):
            out = Path(tmp) / "report.md"
            code = yt.main(["--output", str(out)])
            return code, out.read_text(encoding="utf-8")

    def test_a_dead_link_fails_the_run_and_is_listed_first(self):
        code, text = self.run_main({LIVE: (200, {"title": "Live talk"}), DEAD: (404, None)})
        self.assertEqual(code, 1)
        self.assertIn("2 checked: 1 dead, 0 unverified, 1 live.", text)
        self.assertLess(text.index(DEAD), text.index(LIVE))
        self.assertIn("Live talk", text)

    def test_unverified_alone_does_not_fail_the_run(self):
        code, text = self.run_main({LIVE: (429, None)})
        self.assertEqual(code, 0)
        self.assertIn("| unverified |", text)


class WorkflowWiringTest(unittest.TestCase):
    """The weekly run has to call the checker and act on its exit code."""

    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_workflow_runs_the_checker(self):
        self.assertIn("scripts/check-youtube-links.py", self.workflow)

    def test_a_dead_youtube_link_alone_updates_the_tracking_issue(self):
        self.assertIn("steps.youtube.outputs.exit_code != '0'", self.workflow)

    def test_the_report_reaches_the_tracking_issue(self):
        self.assertIn("youtube-report.md", self.workflow)


if __name__ == "__main__":
    unittest.main()
