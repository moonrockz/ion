import copy
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

import performance


class PerformanceTests(unittest.TestCase):
    def setUp(self):
        self.report = {
            "schema_version": 1,
            "status": "passed",
            "commit": "after",
            "runner_os": "Linux",
            "target": "native",
            "architecture": "x86_64",
            "toolchain": "moon new",
            "cpu": "cpu",
            "config": {"samples": 5},
            "metrics": {"large/read-text-sync": {"median_ms": 10, "mib_per_second": 2}},
            "cli": {"input_bytes": 100, "median_ms": 4, "median_peak_rss_bytes": 2048},
            "errors": [],
        }

    def test_sampling_uses_median_and_checks_output(self):
        samples = [
            {"iterations": 10, "elapsed_ms": n, "input_bytes": 1024, "checksum": 20}
            for n in [10, 20, 1000]
        ]
        result = performance.summarize(samples)
        self.assertEqual(result["median_ms"], 2)
        self.assertEqual(result["samples"], samples)
        samples[-1]["checksum"] = 0
        with self.assertRaises(ValueError):
            performance.summarize(samples)
        with self.assertRaises(ValueError):
            performance.summarize(
                [{"iterations": 0, "elapsed_ms": 1, "input_bytes": 10}]
            )

    def test_changes_do_not_fail_current_results(self):
        old = copy.deepcopy(self.report)
        old["toolchain"] = "moon old"
        old["metrics"]["large/read-text-sync"]["median_ms"] = 1
        old["cli"]["median_peak_rss_bytes"] = 1024
        baseline = {
            "status": "available",
            "run_id": 1,
            "url": "https://example.test/run/1",
            "commit": "before",
            "report": old,
        }
        self.assertTrue(performance.compatible(self.report, old))
        self.report["comparison"] = performance.compare(self.report, baseline)
        self.assertEqual(
            self.report["comparison"]["metrics"]["large/read-text-sync"][
                "change_percent"
            ],
            900,
        )
        self.assertEqual(self.report["comparison"]["cli_peak_rss_change_percent"], 100)
        self.assertEqual(self.report["status"], "passed")
        rendered = performance.render(self.report)
        self.assertIn("+900.0%", rendered)
        self.assertIn("Environment changed", rendered)
        self.assertIn("https://example.test/run/1", rendered)
        json.dumps(self.report)

    def test_incompatible_baselines_and_unavailable(self):
        for key, value in [
            ("runner_os", "Windows"),
            ("architecture", "arm64"),
            ("target", "wasm"),
            ("config", {}),
            ("status", "failed"),
        ]:
            old = {**self.report, key: value}
            self.assertFalse(performance.compatible(self.report, old))
        old = {**self.report, "metrics": {"foo": {"median_ms": 0}}}
        self.assertFalse(performance.compatible(self.report, old))
        unavailable = {"status": "unavailable", "reason": "No prior artifact"}
        self.assertEqual(performance.compare(self.report, unavailable), unavailable)
        self.report["comparison"] = unavailable
        self.assertIn("No prior artifact", performance.render(self.report))

    @unittest.skipUnless(hasattr(os, "wait4"), "RSS runner requires POSIX wait4")
    def test_cli_rss_and_execution_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input"
            source.write_bytes(b"sample")
            result = performance.measure_cli(
                [
                    sys.executable,
                    "-c",
                    "import sys; assert sys.stdin.buffer.read() == b'sample'",
                ],
                source,
            )
            self.assertGreater(result["peak_rss_bytes"], 0)
            self.assertGreater(result["elapsed_ms"], 0)
            with self.assertRaisesRegex(RuntimeError, "CLI benchmark failed"):
                performance.measure_cli(
                    [sys.executable, "-c", "raise RuntimeError('sample failure')"],
                    source,
                )
