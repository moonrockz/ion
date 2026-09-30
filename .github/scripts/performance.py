"""Sample native release operations and CLI RSS; timing deltas are informational."""

import argparse
import json
import math
import os
import platform
import statistics
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from ci_baseline import find_baseline

MODES = [
    "read-text-sync",
    "read-text-stream",
    "read-binary-sync",
    "read-binary-stream",
    "write-text-sync",
    "write-text-stream",
    "write-binary-sync",
    "write-binary-stream",
    "hash",
]
ROOT = Path(__file__).resolve().parents[2]


def cpu_identifier():
    info = Path("/proc/cpuinfo")
    if info.exists():
        for line in info.read_text().splitlines():
            if line.startswith(("model name", "Hardware")):
                return line.split(":", 1)[-1].strip()
    return platform.processor() or platform.machine()


def command(args, combined=False):
    result = subprocess.run(
        args, cwd=ROOT, text=True, capture_output=True, check=True, timeout=180
    )
    return result.stdout + (result.stderr if combined else "")


def summarize(samples):
    if not samples or any(
        s["iterations"] <= 0 or s["elapsed_ms"] <= 0 or s["input_bytes"] <= 0
        for s in samples
    ):
        raise ValueError("benchmark returned invalid measurements")
    if len({(s["input_bytes"], s["checksum"]) for s in samples}) != 1:
        raise ValueError("benchmark output changed between samples")
    times = [s["elapsed_ms"] / s["iterations"] for s in samples]
    median = statistics.median(times)
    return {
        "median_ms": median,
        "mib_per_second": samples[0]["input_bytes"] / (1024 * 1024) / (median / 1000),
        "samples": samples,
    }


def measure_cli(args, source):
    """wait4 reports this child's peak RSS rather than the parent's historical max."""
    with open(source, "rb") as input_file, tempfile.TemporaryFile() as errors:
        start = time.perf_counter()
        child = subprocess.Popen(
            args, stdin=input_file, stdout=subprocess.DEVNULL, stderr=errors, cwd=ROOT
        )
        # The timer bounds execution without adding another process to the RSS sample.
        timer = threading.Timer(180, child.kill)
        timer.start()
        try:
            _, status, usage = os.wait4(child.pid, 0)
            child.returncode = os.waitstatus_to_exitcode(status)
        finally:
            timer.cancel()
        elapsed = (time.perf_counter() - start) * 1000
        if child.returncode:
            errors.seek(0)
            raise RuntimeError(
                "CLI benchmark failed: " + errors.read().decode(errors="replace")[:2000]
            )
        rss = usage.ru_maxrss * (1 if platform.system() == "Darwin" else 1024)
        return {"elapsed_ms": elapsed, "peak_rss_bytes": rss}


def compatible(current, previous):
    return (
        isinstance(previous, dict)
        and previous.get("schema_version") == 1
        and previous.get("status") == "passed"
        and all(
            previous.get(key) == current[key]
            for key in ["runner_os", "target", "architecture", "config"]
        )
        and isinstance(previous.get("metrics"), dict)
        and isinstance(previous.get("cli"), dict)
        and isinstance(previous["cli"].get("median_peak_rss_bytes"), (int, float))
        and math.isfinite(previous["cli"]["median_peak_rss_bytes"])
        and previous["cli"]["median_peak_rss_bytes"] > 0
        and all(
            isinstance(m, dict)
            and isinstance(m.get("median_ms"), (int, float))
            and math.isfinite(m["median_ms"])
            and m["median_ms"] > 0
            for m in previous["metrics"].values()
        )
    )


def compare(current, baseline):
    if baseline["status"] != "available":
        return baseline
    previous = baseline["report"]
    result = {key: value for key, value in baseline.items() if key != "report"}
    result["current_commit"] = current["commit"]
    result["environment_changes"] = {
        key: {"previous": previous.get(key), "current": current.get(key)}
        for key in ["toolchain", "cpu"]
        if previous.get(key) != current.get(key)
    }
    result["metrics"] = {
        name: {
            "baseline_ms": previous["metrics"][name]["median_ms"],
            "change_percent": (
                metric["median_ms"] / previous["metrics"][name]["median_ms"] - 1
            )
            * 100,
        }
        for name, metric in current["metrics"].items()
        if name in previous["metrics"]
    }
    old_rss = previous.get("cli", {}).get("median_peak_rss_bytes", 0)
    if old_rss > 0:
        result["cli_peak_rss_change_percent"] = (
            current["cli"]["median_peak_rss_bytes"] / old_rss - 1
        ) * 100
    return result


def render(report):
    lines = [
        "## Native performance",
        "",
        "Status: **"
        + report["status"]
        + "**. Timing and memory changes are informational; no thresholds fail CI.",
        "",
        "Commit: `"
        + report["commit"]
        + "`. OS: "
        + report["runner_os"]
        + "; architecture: "
        + report["architecture"]
        + ".",
        "",
        "Toolchain: `" + report["toolchain"].replace("\n", " / ") + "`.",
        "",
        "Workloads: "
        + str(report["config"])
        + ". Release builds; fixture setup and warmup excluded from samples.",
        "",
    ]
    baseline = report.get(
        "comparison", {"status": "unavailable", "reason": "Current measurements failed"}
    )
    if baseline["status"] == "available":
        lines += [
            "Baseline: [main CI run "
            + str(baseline["run_id"])
            + "]("
            + baseline["url"]
            + "), commit `"
            + baseline["commit"]
            + "`.",
            "",
        ]
        if baseline["environment_changes"]:
            lines += [
                "Environment changed: `"
                + json.dumps(baseline["environment_changes"])
                + "`. Interpret deltas with care.",
                "",
            ]
    else:
        lines += ["Baseline unavailable: " + baseline["reason"] + ".", ""]
    lines += [
        "Throughput uses the serialized fixture size; Ion Hash operates on parsed values.",
        "",
        "| Workload / operation | Median ms | Fixture MiB/s | Change vs main |",
        "| --- | ---: | ---: | ---: |",
    ]
    for name, metric in report["metrics"].items():
        delta = baseline.get("metrics", {}).get(name, {}).get("change_percent")
        change = "n/a" if delta is None else f"{delta:+.1f}%"
        lines.append(
            f"| {name} | {metric['median_ms']:.3f} | {metric['mib_per_second']:.2f} | {change} |"
        )
    if report.get("cli"):
        cli = report["cli"]
        delta = baseline.get("cli_peak_rss_change_percent")
        lines += [
            "",
            f"CLI `print -`: {cli['input_bytes']:,} input bytes, median {cli['median_ms']:.1f} ms, median peak RSS {cli['median_peak_rss_bytes'] / (1024 * 1024):.2f} MiB.",
        ]
        if delta is not None:
            lines.append(f"Peak RSS change vs main: {delta:+.1f}%.")
        lines.append(
            "RSS includes the process/runtime; input is prepared on disk and output is discarded."
        )
    lines += ["", *["Execution error: " + error for error in report["errors"]]]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "_build/performance")
    parser.add_argument("--items", type=int, default=5000)
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--sample-ms", type=int, default=100)
    parser.add_argument("--cli-items", type=int, default=300000)
    args = parser.parse_args()
    if min(args.items, args.samples, args.sample_ms, args.cli_items) <= 0:
        parser.error("sample and workload sizes must be positive")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "schema_version": 1,
        "status": "passed",
        "commit": os.environ.get("GITHUB_SHA")
        or command(["git", "rev-parse", "HEAD"]).strip(),
        "runner_os": os.environ.get("RUNNER_OS") or platform.system(),
        "target": "native",
        "architecture": platform.machine(),
        "toolchain": command(["moon", "version", "--all", "--no-path"]).strip(),
        "cpu": cpu_identifier(),
        "config": {
            "items": args.items,
            "samples": args.samples,
            "sample_ms": args.sample_ms,
            "cli_items": args.cli_items,
        },
        "metrics": {},
        "errors": [],
    }
    try:
        build_log = command(
            ["moon", "build", "--target", "native", "--release"], combined=True
        )
        (args.output_dir / "build.log").write_text(build_log)
        build = ROOT / "_build/native/release/build"
        driver = build / "benchmarks/benchmarks.exe"
        cli = build / "ion.exe"
        for shape in ["many", "large"]:
            modes = MODES + (
                ["write-text-incremental", "write-binary-incremental"]
                if shape == "large"
                else []
            )
            for mode in modes:
                samples = [
                    json.loads(
                        command(
                            [
                                str(driver),
                                mode,
                                shape,
                                str(args.items),
                                str(args.sample_ms),
                            ]
                        )
                    )
                    for _ in range(args.samples)
                ]
                report["metrics"][shape + "/" + mode] = summarize(samples)
        with tempfile.TemporaryDirectory(prefix="ion-benchmark-") as directory:
            source = Path(directory) / "large.ion"
            value = b'{name: "ion", values: [1, 2, 3], tag: sample}\n'
            with source.open("wb") as output:
                for _ in range(args.cli_items):
                    output.write(value)
            samples = [
                measure_cli([str(cli), "print", "-"], source)
                for _ in range(args.samples)
            ]
            report["cli"] = {
                "input_bytes": source.stat().st_size,
                "median_ms": statistics.median(s["elapsed_ms"] for s in samples),
                "median_peak_rss_bytes": statistics.median(
                    s["peak_rss_bytes"] for s in samples
                ),
                "samples": samples,
            }
        baseline = find_baseline(
            "performance-results-ubuntu-latest-native",
            "performance.json",
            lambda previous: compatible(report, previous),
        )
        report["comparison"] = compare(report, baseline)
    except (
        OSError,
        ValueError,
        KeyError,
        RuntimeError,
        subprocess.SubprocessError,
    ) as error:
        report["status"] = "failed"
        detail = (
            error.stderr
            if isinstance(error, subprocess.CalledProcessError)
            else str(error)
        )
        report["errors"].append(str(detail)[:4000])
    (args.output_dir / "performance.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    summary = render(report)
    (args.output_dir / "performance.md").write_text(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(summary)
    print(summary)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
