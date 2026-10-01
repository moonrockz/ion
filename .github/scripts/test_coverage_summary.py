import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import coverage_summary as summary


def raw_report():
    return {
        "source_files": [
            {"name": name, "coverage": [None, 0, 1, 2], "source_digest": "digest"}
            for name in summary.FOCUS
        ]
    }


class CoverageTests(unittest.TestCase):
    def report(self, raw=None, points="Total: 12/24\n", exit_code=0):
        return summary.make_report(
            raw_report() if raw is None else raw, points, exit_code, "wasm"
        )

    def test_counts_exclude_uninstrumented_lines_and_keep_points_separate(self):
        report = self.report()
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["lines"]["covered"], 12)
        self.assertEqual(report["lines"]["total"], 18)
        self.assertEqual(report["points"]["percent"], 50)
        self.assertAlmostEqual(report["lines"]["percent"], 66.6666667)
        self.assertEqual(report["files"][summary.FOCUS[0]]["uncovered_lines"], [2])
        self.assertEqual(report["packages"]["pkgs/ion"]["total"], 6)
        markdown = summary.render(report)
        self.assertIn("Executable lines | 12 / 18 | 66.67%", markdown)
        self.assertIn("Moon instrumentation points | 12 / 24 | 50.00%", markdown)
        self.assertIn("pkgs/ion | 4 / 6", markdown)

    def test_failed_or_missing_test_exit_is_partial(self):
        for exit_code in [2, None]:
            report = self.report(exit_code=exit_code)
            self.assertEqual(report["status"], "partial")
            self.assertTrue(report["errors"])
            self.assertIn("coverage is partial", summary.render(report))

    def test_empty_malformed_or_missing_data_cannot_claim_success(self):
        for raw in [
            {},
            {"source_files": []},
            {"source_files": None},
            {"source_files": [None]},
        ]:
            report = self.report(raw)
            self.assertNotEqual(report["status"], "passed")
            self.assertTrue(report["errors"])
        for value in [-1, True, 0.5, "one"]:
            raw = raw_report()
            raw["source_files"][0]["coverage"][2] = value
            self.assertNotEqual(self.report(raw)["status"], "passed")
        for points in ["", "Total: 25/24", "Total: 0/0"]:
            self.assertNotEqual(self.report(points=points)["status"], "passed")
        raw = raw_report()
        raw["source_files"] = raw["source_files"][1:]
        self.assertIn(
            "focused source was not instrumented", self.report(raw)["errors"][0]
        )

    def test_source_paths_and_duplicates_are_validated(self):
        for name in [
            "/etc/passwd",
            "pkgs/../../escape.mbt",
            "other/dependency.mbt",
            "pkgs/missing.mbt",
            3,
        ]:
            raw = raw_report()
            raw["source_files"][0]["name"] = name
            self.assertNotEqual(self.report(raw)["status"], "passed")
        raw = raw_report()
        raw["source_files"].append(copy.deepcopy(raw["source_files"][0]))
        self.assertIn("duplicate coverage source", self.report(raw)["errors"][0])

    def test_cli_publishes_artifacts_and_marks_export_failure(self):
        for fail_html, exit_code in [(False, "0"), (True, "0"), (False, "2")]:
            with (
                self.subTest(fail_html=fail_html, exit_code=exit_code),
                tempfile.TemporaryDirectory() as directory,
            ):
                output = Path(directory) / "output"
                step_summary = Path(directory) / "step-summary"

                def exporter(command, _fail_html=fail_html, **_kwargs):
                    format = command[command.index("-f") + 1]
                    if format == "html" and _fail_html:
                        raise subprocess.CalledProcessError(
                            1, command, stderr="missing traces"
                        )
                    if format == "summary":
                        return subprocess.CompletedProcess(
                            command, 0, stdout="Total: 12/24\n", stderr=""
                        )
                    target = Path(command[command.index("-o") + 1])
                    if format == "html":
                        target.mkdir()
                        (target / "index.html").write_text("<html>source views</html>")
                    else:
                        target.write_text(
                            json.dumps(raw_report())
                            if format == "coveralls"
                            else "<coverage/>"
                        )
                    return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

                with (
                    patch.object(
                        sys,
                        "argv",
                        [
                            "coverage_summary.py",
                            "--output-dir",
                            str(output),
                            "--exit-code",
                            exit_code,
                        ],
                    ),
                    patch.dict(
                        os.environ,
                        GITHUB_STEP_SUMMARY=str(step_summary),
                        GITHUB_SHA="tested-commit",
                    ),
                    patch.object(summary.subprocess, "run", side_effect=exporter),
                ):
                    status = summary.main()
                report = json.loads((output / "coverage.json").read_text())
                self.assertEqual(status, 1 if fail_html or exit_code != "0" else 0)
                self.assertEqual(report["commit"], "tested-commit")
                self.assertEqual(
                    step_summary.read_text(), (output / "coverage.md").read_text()
                )
                self.assertTrue((output / "coverage.coveralls.json").is_file())
                self.assertTrue((output / "coverage.cobertura.xml").is_file())
                if fail_html:
                    self.assertIn(
                        "html report failed", (output / "coverage.md").read_text()
                    )
                else:
                    self.assertTrue((output / "html/index.html").is_file())
