"""Publish corpus results emitted by the MoonBit tests, including failed runs."""

import argparse
import hashlib
import html
import json
import os
import platform
import subprocess
from pathlib import Path

SUITES = {
    "ion-files": ("Ion 1.0 corpus", "files"),
    "ion-readers": ("Ion readers and writers", "checks"),
    "ion-dsl": ("Ion conformance DSL", "cases"),
    "isl-1.0": ("Ion Schema 1.0", "cases"),
    "isl-2.0": ("Ion Schema 2.0", "cases"),
    "ion-hash": ("Ion Hash identity serialization", "cases"),
}
COUNTS = (
    "total",
    "passed",
    "skipped",
    "known_failures",
    "not_applicable",
    "unexpected",
    "stale",
    "files",
    "out_of_scope",
)
PREFIX = "CONFORMANCE "
WASM_GC_EXCLUSION = (
    "The conformance package is disabled on wasm-gc because of the upstream "
    "BigInt conversion bug: https://github.com/moonrockz/ion/issues/13"
)


def parse_results(log, excluded_suites=()):
    results = {}
    errors = []
    for line in log.splitlines():
        if not line.startswith(PREFIX):
            continue
        try:
            result = json.loads(line[len(PREFIX) :])
            if not isinstance(result, dict) or result.get("suite") not in SUITES:
                raise ValueError("unknown corpus suite")
            suite = result["suite"]
            if suite in results:
                raise ValueError("duplicate result for " + suite)
            for key in COUNTS:
                if type(result.get(key)) is not int or result[key] < 0:
                    raise ValueError("invalid count " + key + " for " + suite)
            accounted = sum(
                result[key]
                for key in (
                    "passed",
                    "skipped",
                    "known_failures",
                    "not_applicable",
                    "unexpected",
                )
            )
            if accounted != result["total"]:
                raise ValueError("counts do not add up for " + suite)
            if not isinstance(result.get("details"), list) or not all(
                isinstance(detail, str) for detail in result["details"]
            ):
                raise ValueError("invalid details for " + suite)
            results[suite] = result
            if suite in excluded_suites:
                errors.append(
                    "excluded suite reported results; remove its target exclusion: "
                    + suite
                )
        except (ValueError, TypeError) as error:
            errors.append(str(error))
    for suite in SUITES:
        if suite not in results and suite not in excluded_suites:
            errors.append("no result reported for " + suite)
    return results, errors


def git_revision(directory):
    if not (directory / ".git").exists():
        return None
    result = subprocess.run(
        ["git", "-C", str(directory), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def make_report(log, exit_code, root, target):
    exclusions = (
        {suite: WASM_GC_EXCLUSION for suite in SUITES if suite != "ion-hash"}
        if target == "wasm-gc"
        else {}
    )
    results, errors = parse_results(log, exclusions)
    if exit_code is None:
        errors.append("test command did not report an exit code")
    failed = exit_code not in (0, None) or any(
        result["unexpected"] or result["stale"] for result in results.values()
    )
    fixture = root / "tests/fixtures/ion_hash_tests.ion"
    return {
        "schema_version": 1,
        "status": "failed" if failed else "incomplete" if errors else "passed",
        "test_exit_code": exit_code,
        "target": target,
        "runner_os": os.environ.get("RUNNER_OS", platform.system()),
        "excluded_suites": exclusions,
        "commit": git_revision(root),
        "corpora": {
            "ion-tests": git_revision(root / "tests/ion-tests"),
            "ion-schema-tests": git_revision(root / "tests/ion-schema-tests"),
            "ion-hash-fixture-sha256": (
                hashlib.sha256(fixture.read_bytes()).hexdigest()
                if fixture.exists()
                else None
            ),
        },
        "suites": results,
        "errors": errors,
    }


def escape(text):
    return html.escape(str(text), quote=False).replace("|", "&#124;").replace("\n", " ")


def render_markdown(report):
    lines = [
        "## Corpus conformance",
        "",
        "Result: **"
        + report["status"]
        + "**. Target: `"
        + escape(report["target"])
        + "`.",
        "Runner OS: " + escape(report["runner_os"]) + ".",
        "Test command exit code: " + str(report["test_exit_code"]) + ".",
        "",
        "| Corpus | Unit | Total | Passed | Skipped | Known failures | N/A | Unexpected | Stale exclusions | Status |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for suite, (name, unit) in SUITES.items():
        result = report["suites"].get(suite)
        if result is None:
            status = (
                "Excluded" if suite in report["excluded_suites"] else "Not reported"
            )
            lines.append(
                "| "
                + name
                + " | "
                + unit
                + " | - | - | - | - | - | - | - | "
                + status
                + " |"
            )
            continue
        status = "Failed" if result["unexpected"] or result["stale"] else "Passed"
        cells = [name, unit] + [str(result[key]) for key in COUNTS[:7]] + [status]
        lines.append("| " + " | ".join(cells) + " |")
    lines += [
        "",
        "Counts use each runner's unit; they are not a combined test total.",
        "Known failures and skipped cases are excluded from passes. N/A cases do not apply to Ion 1.0.",
        "Stale exclusions fail the suite even when their cases pass.",
        "",
        "### Corpus revisions",
        "",
        "Commit: `" + escape(report["commit"] or "unavailable") + "`.",
        "",
    ]
    for name, revision in report["corpora"].items():
        lines.append("- " + name + ": `" + escape(revision or "unavailable") + "`.")
    if report["excluded_suites"]:
        lines += ["", "### Target exclusions", ""]
        for reason in sorted(set(report["excluded_suites"].values())):
            lines.append("- " + escape(reason))
    for suite, result in report["suites"].items():
        if result["files"] or result["out_of_scope"] or result["details"]:
            lines += [
                "",
                "<details>",
                "<summary>" + SUITES[suite][0] + " details</summary>",
                "",
            ]
            if result["files"]:
                lines.append("Files: " + str(result["files"]) + ".")
            if suite == "ion-dsl":
                lines.append(
                    "Ion 1.1 test forms not run: " + str(result["out_of_scope"]) + "."
                )
            elif result["out_of_scope"]:
                lines.append(
                    "Corpus files omitted: " + str(result["out_of_scope"]) + "."
                )
            if result["details"]:
                lines.append("")
                lines.extend("- " + escape(detail) for detail in result["details"])
            lines += ["", "</details>"]
    if report["errors"]:
        lines += ["", "### Reporting errors", ""]
        lines.extend("- " + escape(error) for error in report["errors"])
    lines += [
        "",
        "The conformance-results artifact contains this summary, JSON counts, and the full test log.",
        "",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument(
        "--exit-code",
        required=True,
        help="Test exit code, or empty if tests did not run",
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--target", default="wasm")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    log = (
        args.log.read_text(encoding="utf-8", errors="replace")
        if args.log.exists()
        else ""
    )
    report = make_report(
        log, int(args.exit_code) if args.exit_code else None, root, args.target
    )
    markdown = render_markdown(report)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "conformance.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    (args.output_dir / "conformance.md").write_text(markdown, encoding="utf-8")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write(markdown)
    else:
        print(markdown)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
