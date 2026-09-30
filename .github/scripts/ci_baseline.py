"""Read reports from earlier successful main CI runs using read-only gh calls."""

import io
import json
import os
import subprocess
import zipfile


def api(endpoint):
    result = subprocess.run(
        ["gh", "api", "--allow-escape-sequences", endpoint],
        capture_output=True,
        check=False,
        timeout=30,
    )
    if result.returncode:
        raise RuntimeError(
            "GitHub API unavailable: permissions, rate limit, or connectivity"
        )
    return result.stdout


def archive_report(data, filename):
    if len(data) > 16 * 1024 * 1024:
        raise ValueError("baseline artifact is too large")
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        member = archive.getinfo(filename)
        if member.file_size > 1024 * 1024:
            raise ValueError("baseline report is too large")
        return json.loads(archive.read(member))


def find_baseline(artifact_name, filename, compatible, request=api):
    """Return the newest compatible report; absence never fails current checks."""
    repository = os.environ.get("GITHUB_REPOSITORY")
    run_id = os.environ.get("GITHUB_RUN_ID")
    unavailable = {"status": "unavailable", "reason": "Not running in GitHub Actions"}
    if not repository or not run_id:
        return unavailable
    try:
        current_id = int(run_id)
        prefix = "repos/" + repository + "/actions/"
        runs = json.loads(
            request(
                prefix
                + "workflows/ci.yml/runs?branch=main&event=push&status=success&per_page=20"
            )
        )["workflow_runs"]
        reason = "No earlier successful main run has a compatible, unexpired artifact"
        for run in sorted(runs, key=lambda run: run["id"], reverse=True):
            if (
                run["id"] >= current_id
                or run.get("head_branch") != "main"
                or run.get("conclusion") != "success"
                or run.get("event") != "push"
            ):
                continue
            artifacts = json.loads(
                request(prefix + "runs/" + str(run["id"]) + "/artifacts?per_page=100")
            )["artifacts"]
            for artifact in artifacts:
                if artifact["name"] != artifact_name or artifact.get("expired"):
                    continue
                try:
                    report = archive_report(
                        request(prefix + "artifacts/" + str(artifact["id"]) + "/zip"),
                        filename,
                    )
                    if not compatible(report):
                        continue
                except (ValueError, KeyError, zipfile.BadZipFile):
                    reason = "Earlier artifacts contain invalid or incompatible reports"
                    continue
                return {
                    "status": "available",
                    "run_id": run["id"],
                    "url": run["html_url"],
                    "commit": report.get("commit") or run["head_sha"],
                    "report": report,
                }
        unavailable["reason"] = reason
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        RuntimeError,
        subprocess.TimeoutExpired,
    ) as error:
        unavailable["reason"] = "Baseline unavailable: " + str(error)
    return unavailable


def artifact_for(report):
    runner = {
        "Linux": "ubuntu-latest",
        "Windows": "windows-latest",
        "macOS": "macos-latest",
        "Darwin": "macos-latest",
    }.get(report["runner_os"])
    return "conformance-results-" + str(runner) + "-" + report["target"]
