"""Publish Moon coverage as line counts, raw point totals, and browsable artifacts."""

import argparse
import html
import json
import os
import platform
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOCUS = [
    "pkgs/text/handler.mbt",
    "pkgs/ion/fold.mbt",
    "pkgs/ion/visitor.mbt",
    "pkgs/json/to_ion.mbt",
    "pkgs/schema/load.mbt",
    "pkgs/schema/validate.mbt",
]


def counts(covered, total):
    return {
        "covered": covered,
        "total": total,
        "percent": covered * 100 / total if total else None,
    }


def make_report(raw, point_summary, exit_code, target, root=ROOT):
    report = {
        "schema_version": 1,
        "status": "passed",
        "target": target,
        "runner_os": os.environ.get("RUNNER_OS", platform.system()),
        "commit": os.environ.get("GITHUB_SHA"),
        "test_exit_code": exit_code,
        "files": {},
        "packages": {},
        "errors": [],
    }
    if exit_code != 0:
        report["errors"].append(
            "Instrumented tests failed or did not report an exit code; coverage is partial"
        )
    try:
        sources = raw["source_files"]
        if not isinstance(sources, list) or not sources:
            raise ValueError("no instrumented source files reported")
        for source in sources:
            name = source["name"]
            path = Path(name)
            if (
                not isinstance(name, str)
                or path.is_absolute()
                or ".." in path.parts
                or not name.startswith("pkgs/")
                or not (root / path).is_file()
            ):
                raise ValueError("coverage source is not a project file: " + str(name))
            if name in report["files"]:
                raise ValueError("duplicate coverage source: " + name)
            coverage = source["coverage"]
            if not isinstance(coverage, list) or any(
                value is not None and (type(value) is not int or value < 0)
                for value in coverage
            ):
                raise ValueError("invalid line hits for " + name)
            instrumented = [value for value in coverage if value is not None]
            file = counts(sum(value > 0 for value in instrumented), len(instrumented))
            file["uncovered_lines"] = [
                line for line, value in enumerate(coverage, 1) if value == 0
            ]
            file["source_digest"] = source.get("source_digest")
            report["files"][name] = file
        report["lines"] = counts(
            sum(f["covered"] for f in report["files"].values()),
            sum(f["total"] for f in report["files"].values()),
        )
        if report["lines"]["total"] == 0:
            raise ValueError("no executable source lines reported")
        for name, file in report["files"].items():
            package = str(Path(name).parent)
            bucket = report["packages"].setdefault(package, {"covered": 0, "total": 0})
            bucket["covered"] += file["covered"]
            bucket["total"] += file["total"]
        report["packages"] = {
            name: counts(**value) for name, value in report["packages"].items()
        }
        match = re.search(r"^Total: (\d+)/(\d+)\s*$", point_summary, re.MULTILINE)
        if not match or int(match[1]) > int(match[2]) or int(match[2]) == 0:
            raise ValueError("Moon did not report valid instrumentation-point totals")
        report["points"] = counts(int(match[1]), int(match[2]))
        for name in FOCUS:
            if name not in report["files"]:
                raise ValueError("focused source was not instrumented: " + name)
    except (KeyError, TypeError, ValueError) as error:
        report["errors"].append(str(error))
    if report["errors"]:
        report["status"] = "partial" if report["files"] else "unavailable"
    return report


def row(name, value):
    percent = "n/a" if value["percent"] is None else f"{value['percent']:.2f}%"
    return f"| {html.escape(name).replace('|', '&#124;')} | {value['covered']} / {value['total']} | {percent} |"


def render(report):
    lines = [
        "## Code coverage",
        "",
        "Status: **"
        + report["status"]
        + "**. Target: `"
        + report["target"]
        + "`. OS: "
        + report["runner_os"]
        + ".",
        "",
        "Commit: `" + str(report["commit"] or "local working tree") + "`.",
        "",
        "Line coverage comes from Moon's Coveralls output; comments and uninstrumented lines are excluded. Moon's summary counts execution points, which can include several points on one line. These percentages are separate measures.",
        "",
    ]
    if "lines" in report:
        lines += [
            "| Measure | Covered / total | Coverage |",
            "| --- | ---: | ---: |",
            row("Executable lines", report["lines"]),
        ]
        if "points" in report:
            lines.append(row("Moon instrumentation points", report["points"]))
    lines += [
        "",
        "### Package line coverage",
        "",
        "| Package | Covered / total | Coverage |",
        "| --- | ---: | ---: |",
    ]
    lines += [row(name, value) for name, value in sorted(report["packages"].items())]
    lines += [
        "",
        "### Focused files",
        "",
        "| File | Covered / total | Line coverage |",
        "| --- | ---: | ---: |",
    ]
    lines += [
        row(name, report["files"][name]) for name in FOCUS if name in report["files"]
    ]
    if report["errors"]:
        lines += [
            "",
            "Reporting errors:",
            "",
            *["- " + html.escape(error) for error in report["errors"]],
        ]
    lines += [
        "",
        "Coverage percentages are informational. The coverage-results artifact includes HTML source views, Coveralls JSON, Cobertura XML, raw point totals, and per-file line counts with uncovered line numbers.",
        "",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--exit-code", required=True)
    parser.add_argument("--target", default="wasm")
    parser.add_argument("--target-dir", type=Path, default=ROOT / "_build")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    raw, point_summary, errors = {}, "", []
    formats = [
        ("summary", "moon-summary.txt"),
        ("coveralls", "coverage.coveralls.json"),
        ("cobertura", "coverage.cobertura.xml"),
        ("html", "html"),
    ]
    for format, filename in formats:
        output = args.output_dir / filename
        command = [
            "moon",
            "coverage",
            "--target-dir",
            str(args.target_dir),
            "report",
            "-f",
            format,
        ]
        if format != "summary":
            command += ["-o", str(output)]
        try:
            result = subprocess.run(
                command,
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=60,
                check=True,
            )
            if format == "summary":
                point_summary = result.stdout
                output.write_text(point_summary, encoding="utf-8")
            if format == "html" and not (output / "index.html").is_file():
                raise ValueError("HTML source index was not generated")
            if format == "cobertura" and not output.is_file():
                raise ValueError("Cobertura XML was not generated")
            if format == "coveralls":
                raw = json.loads(output.read_text(encoding="utf-8"))
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            detail = (
                error.stderr
                if isinstance(error, subprocess.CalledProcessError)
                else str(error)
            )
            errors.append(format + " report failed: " + str(detail)[:2000])
    report = make_report(
        raw, point_summary, int(args.exit_code) if args.exit_code else None, args.target
    )
    if errors:
        report["errors"] += errors
        report["status"] = "partial" if report["files"] else "unavailable"
    (args.output_dir / "coverage.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    markdown = render(report)
    (args.output_dir / "coverage.md").write_text(markdown, encoding="utf-8")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as output:
            output.write(markdown)
    else:
        print(markdown)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
