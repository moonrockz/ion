import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

import conformance_summary as summary


def result(suite, **changes):
    record = dict.fromkeys(summary.COUNTS, 0)
    record.update(suite=suite, total=10, passed=10, details=[])
    record.update(changes)
    return record


def log_with(**changes):
    records = [result(suite, **changes.get(suite, {})) for suite in summary.SUITES]
    return "compiler and test output\n" + "\n".join(
        summary.PREFIX + json.dumps(record) for record in records
    )


class ConformanceSummaryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def report(self, log, exit_code=0):
        return summary.make_report(log, exit_code, self.root, "wasm")

    def test_known_failures_and_exclusions_are_not_passes(self):
        report = self.report(
            log_with(
                **{
                    "isl-1.0": {"passed": 8, "known_failures": 2, "files": 3},
                    "ion-dsl": {"passed": 6, "skipped": 2, "not_applicable": 2},
                    "ion-hash": {"passed": 9, "skipped": 1},
                }
            )
        )
        self.assertEqual(report["status"], "passed")
        markdown = summary.render_markdown(report)
        self.assertIn(
            "| Ion Schema 1.0 | cases | 10 | 8 | 0 | 2 | 0 | 0 | 0 | Passed |", markdown
        )
        self.assertIn(
            "| Ion conformance DSL | cases | 10 | 6 | 2 | 0 | 2 | 0 | 0 | Passed |",
            markdown,
        )
        self.assertIn("Files: 3.", markdown)

    def test_failure_counts_and_details_survive_failed_command(self):
        report = self.report(
            log_with(
                **{
                    "ion-files": {
                        "passed": 9,
                        "unexpected": 1,
                        "details": ["bad/input.ion: accepted"],
                    },
                }
            ),
            exit_code=2,
        )
        self.assertEqual(report["status"], "failed")
        self.assertIn("bad/input.ion: accepted", summary.render_markdown(report))

    def test_stale_exclusions_fail_even_when_every_case_passes(self):
        report = self.report(log_with(**{"ion-dsl": {"stale": 1}}))
        self.assertEqual(report["status"], "failed")

    def test_missing_suite_is_incomplete_even_with_zero_exit_code(self):
        log = "\n".join(
            line for line in log_with().splitlines() if '"ion-readers"' not in line
        )
        report = self.report(log)
        self.assertEqual(report["status"], "incomplete")
        self.assertIn("no result reported for ion-readers", report["errors"])
        self.assertIn("Not reported", summary.render_markdown(report))

    def test_missing_exit_code_does_not_claim_success(self):
        self.assertEqual(self.report(log_with(), None)["status"], "incomplete")

    def test_wasm_gc_reports_disabled_corpora_as_excluded(self):
        log = summary.PREFIX + json.dumps(result("ion-hash"))
        report = summary.make_report(log, 0, self.root, "wasm-gc")
        self.assertEqual(report["status"], "passed")
        self.assertEqual(len(report["excluded_suites"]), 5)
        markdown = summary.render_markdown(report)
        self.assertIn("Excluded", markdown)
        self.assertIn("issues/13", markdown)
        self.assertNotIn("Not reported", markdown)

    def test_wasm_gc_still_requires_its_enabled_hash_suite(self):
        report = summary.make_report("", 0, self.root, "wasm-gc")
        self.assertEqual(report["status"], "incomplete")
        self.assertEqual(report["errors"], ["no result reported for ion-hash"])

    def test_reenabled_corpora_require_removing_target_exclusions(self):
        report = summary.make_report(log_with(), 0, self.root, "wasm-gc")
        self.assertEqual(report["status"], "incomplete")
        self.assertTrue(
            all("remove its target exclusion" in error for error in report["errors"])
        )

    def test_failed_command_is_failed_even_when_corpora_pass(self):
        self.assertEqual(self.report(log_with(), 1)["status"], "failed")

    def test_invalid_records_make_the_report_incomplete(self):
        invalid = [
            ("not json", "Expecting value"),
            (json.dumps(result("unknown")), "unknown corpus suite"),
            (json.dumps(result("ion-files", passed=-1)), "invalid count passed"),
            (json.dumps(result("ion-files", total=True)), "invalid count total"),
            (json.dumps(result("ion-files", passed=9)), "counts do not add up"),
            (json.dumps(result("ion-files", details="not a list")), "invalid details"),
        ]
        log = "\n".join(
            line for line in log_with().splitlines() if '"ion-files"' not in line
        )
        for record, expected in invalid:
            with self.subTest(record=record):
                report = self.report(log + "\n" + summary.PREFIX + record)
                self.assertEqual(report["status"], "incomplete")
                self.assertTrue(
                    any(expected in error for error in report["errors"]),
                    report["errors"],
                )

    def test_duplicate_records_are_rejected(self):
        report = self.report(
            log_with() + "\n" + summary.PREFIX + json.dumps(result("ion-files"))
        )
        self.assertIn("duplicate result for ion-files", report["errors"])

    def test_exclusion_details_are_escaped(self):
        report = self.report(
            log_with(
                **{
                    "ion-dsl": {"details": ["<script> | multiline\nreason"]},
                }
            )
        )
        markdown = summary.render_markdown(report)
        self.assertIn("&lt;script&gt; &#124; multiline reason", markdown)
        self.assertNotIn("<script>", markdown)

    def test_cli_writes_summary_and_artifacts_for_a_failed_run(self):
        log = self.root / "moon-test.log"
        log.write_text(log_with(), encoding="utf-8")
        step_summary = self.root / "step-summary.md"
        output = self.root / "report"
        process = subprocess.run(
            [
                sys.executable,
                str(Path(summary.__file__)),
                str(log),
                "--exit-code",
                "2",
                "--output-dir",
                str(output),
            ],
            env=dict(os.environ, GITHUB_STEP_SUMMARY=str(step_summary)),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(process.returncode, 1, process.stderr)
        self.assertEqual(
            json.loads((output / "conformance.json").read_text())["status"], "failed"
        )
        self.assertEqual(
            step_summary.read_text(), (output / "conformance.md").read_text()
        )

    def test_cli_publishes_missing_results_when_tests_never_ran(self):
        output = self.root / "report"
        process = subprocess.run(
            [
                sys.executable,
                str(Path(summary.__file__)),
                str(self.root / "missing.log"),
                "--exit-code",
                "",
                "--output-dir",
                str(output),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(process.returncode, 1, process.stderr)
        report = json.loads((output / "conformance.json").read_text())
        self.assertEqual(report["status"], "incomplete")
        self.assertEqual(len(report["errors"]), 7)

    def test_workflow_capture_preserves_test_exit_code_and_output(self):
        root = Path(summary.__file__).resolve().parents[2]
        for filename, step in [
            ("ci.yml", "Run unit tests"),
            ("release.yml", "Validate release readiness"),
        ]:
            workflow = (root / ".github/workflows" / filename).read_text()
            block = workflow.split("      - name: " + step + "\n", 1)[1]
            command = textwrap.dedent(
                block.split("        run: |\n", 1)[1].split("\n      - name:", 1)[0]
            )
            for coverage in ["true", "false"] if filename == "ci.yml" else ["false"]:
                for exit_code in (0, 2):
                    with self.subTest(
                        workflow=filename, exit_code=exit_code, coverage=coverage
                    ):
                        binary = self.root / "bin"
                        binary.mkdir(exist_ok=True)
                        executable = binary / (
                            "moon" if filename == "ci.yml" else "mise"
                        )
                        executable.write_text(
                            '#!/bin/sh\nif [ "$1" = coverage ]; then exit 0; fi\nprintf \'%s\\n\' "$@" > "$MOON_TEST_ARGS_FILE"\nprintf \'test output\\n\'\nexit '
                            + str(exit_code)
                            + "\n"
                        )
                        executable.chmod(0o755)
                        output = self.root / "github-output"
                        output.unlink(missing_ok=True)
                        process = subprocess.run(
                            ["bash", "-e", "-o", "pipefail", "-c", command],
                            capture_output=True,
                            text=True,
                            check=False,
                            env=dict(
                                os.environ,
                                PATH=str(binary) + os.pathsep + os.environ["PATH"],
                                GITHUB_OUTPUT=str(output),
                                RUNNER_TEMP=str(self.root),
                                TEST_TARGET="wasm",
                                COVERAGE_ENABLED=coverage,
                                MOON_TEST_ARGS_FILE=str(self.root / "moon-args"),
                            ),
                        )
                        self.assertEqual(process.returncode, exit_code, process.stderr)
                        self.assertEqual(
                            output.read_text(), "exit_code=" + str(exit_code) + "\n"
                        )
                        self.assertEqual(
                            (
                                self.root / "conformance-results/moon-test.log"
                            ).read_text(),
                            "test output\n",
                        )
                        if filename == "ci.yml":
                            arguments = (
                                (self.root / "moon-args").read_text().splitlines()
                            )
                            self.assertEqual(
                                "--enable-coverage" in arguments, coverage == "true"
                            )


if __name__ == "__main__":
    unittest.main()
