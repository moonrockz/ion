import copy
import io
import json
import os
import unittest
import zipfile
from unittest.mock import patch

import ci_baseline
import conformance_summary as summary
from test_conformance_summary import log_with


def archive(report):
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w") as output:
        output.writestr("conformance.json", json.dumps(report))
    return data.getvalue()


class BaselineTests(unittest.TestCase):
    def setUp(self):
        from pathlib import Path

        self.current = summary.make_report(log_with(), 0, Path("/nonexistent"), "wasm")
        self.current["runner_os"] = "Linux"
        self.previous = copy.deepcopy(self.current)
        self.previous["commit"] = "before"
        self.env = patch.dict(
            os.environ, GITHUB_REPOSITORY="owner/repo", GITHUB_RUN_ID="50"
        )
        self.env.start()
        self.addCleanup(self.env.stop)

    def find(self, request):
        return ci_baseline.find_baseline(
            "conformance-results-ubuntu-latest-wasm",
            "conformance.json",
            lambda report: summary.compatible_baseline(self.current, report),
            request,
        )

    def test_selects_prior_successful_main_and_skips_expired_or_wrong_target(self):
        requests = []
        wrong = copy.deepcopy(self.previous)
        wrong["runner_os"] = "Windows"

        def request(endpoint):
            requests.append(endpoint)
            if "workflows/" in endpoint:
                return json.dumps(
                    {
                        "workflow_runs": [
                            {
                                "id": i,
                                "head_branch": "main",
                                "conclusion": "success",
                                "event": "push",
                                "html_url": "https://github.com/owner/repo/actions/runs/"
                                + str(i),
                                "head_sha": "head",
                            }
                            for i in [51, 50, 49, 48, 47]
                        ]
                    }
                ).encode()
            if "/runs/" in endpoint:
                i = int(endpoint.split("/runs/")[1].split("/")[0])
                return json.dumps(
                    {
                        "artifacts": [
                            {
                                "name": "conformance-results-ubuntu-latest-wasm",
                                "id": i,
                                "expired": i == 49,
                            }
                        ]
                    }
                ).encode()
            return archive(wrong if "/48/" in endpoint else self.previous)

        baseline = self.find(request)
        self.assertEqual(baseline["run_id"], 47)
        self.assertFalse(
            any("runs/51/" in path or "runs/50/" in path for path in requests)
        )
        self.assertFalse(any("artifacts/49/" in path for path in requests))

    def test_permissions_and_missing_history_are_nonfatal(self):
        def denied(_endpoint):
            raise RuntimeError("permission denied")

        baseline = self.find(denied)
        self.assertEqual(baseline["status"], "unavailable")
        self.assertIn("permission denied", baseline["reason"])
        empty = self.find(lambda _: b'{"workflow_runs": []}')
        self.assertEqual(empty["status"], "unavailable")
        self.assertEqual(summary.compare_report(self.current, baseline), baseline)
        self.assertEqual(self.current["status"], "passed")

    def test_counts_revisions_and_missing_suites_remain_distinct(self):
        self.current["suites"]["ion-files"]["total"] += 2
        self.current["suites"]["ion-files"]["passed"] += 1
        self.current["suites"]["ion-files"]["unexpected"] += 1
        self.current["suites"]["ion-files"]["out_of_scope"] += 3
        self.current["suites"]["isl-1.0"]["passed"] -= 1
        self.current["suites"]["isl-1.0"]["known_failures"] += 1
        self.current["corpora"]["ion-tests"] = "new-corpus"
        del self.current["suites"]["ion-readers"]
        del self.current["suites"]["ion-dsl"]
        self.current["excluded_suites"]["ion-dsl"] = "reason"
        baseline = {
            "status": "available",
            "run_id": 49,
            "url": "https://github.com/owner/repo/actions/runs/49",
            "commit": "before",
            "report": self.previous,
        }
        comparison = summary.compare_report(self.current, baseline)
        self.assertEqual(comparison["suites"]["ion-files"]["delta"]["passed"], 1)
        self.assertEqual(comparison["suites"]["ion-files"]["delta"]["unexpected"], 1)
        self.assertEqual(
            comparison["suites"]["ion-readers"]["current_state"], "missing"
        )
        self.assertEqual(comparison["suites"]["ion-dsl"]["current_state"], "excluded")
        self.assertTrue(comparison["suites"]["ion-dsl"]["exclusion_changed"])
        self.assertEqual(comparison["corpus_changes"], ["ion-tests"])
        markdown = "\n".join(summary.render_comparison(comparison))
        self.assertIn("reported → missing", markdown)
        self.assertIn("reported → excluded", markdown)
        self.assertIn("Count changes may include added", markdown)
        self.assertIn("| Ion 1.0 corpus | files | +2 | +1", markdown)
        self.assertIn("actions/runs/49", markdown)
        self.assertIn("out-of-scope files/forms +3", markdown)
        self.assertEqual(comparison["suites"]["isl-1.0"]["delta"]["known_failures"], 1)

    def test_incompatible_and_incomplete_baselines_are_rejected(self):
        for key, value in [
            ("runner_os", "Windows"),
            ("target", "native"),
            ("status", "incomplete"),
            ("schema_version", 99),
            ("suites", {}),
            ("test_exit_code", 1),
        ]:
            report = copy.deepcopy(self.previous)
            report[key] = value
            self.assertFalse(summary.compatible_baseline(self.current, report))
        self.assertTrue(summary.compatible_baseline(self.current, self.previous))

    def test_artifact_lookup_does_not_extract_arbitrary_paths(self):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as output:
            output.writestr("../conformance.json", "{}")
        with self.assertRaises(KeyError):
            ci_baseline.archive_report(data.getvalue(), "conformance.json")
