Feature: Baseline from an earlier main run
  The conformance summary compares the current report with the report of
  the newest earlier CI run on main that succeeded. The lookup uses
  read-only `gh` calls. It never fails the current run: when no baseline is
  available, the summary says why.

  Scenario: Only earlier successful pushes to main are candidate runs, newest first
    Given the current workflow run is 50
    And the workflow runs:
      | id | head_branch | conclusion | event        |
      | 47 | main        | success    | push         |
      | 51 | main        | success    | push         |
      | 50 | main        | success    | push         |
      | 49 | main        | success    | push         |
      | 48 | feature     | success    | push         |
      | 46 | main        | failure    | push         |
      | 45 | main        | success    | pull_request |
    Then the candidate runs are "49, 47"

  Scenario: Only unexpired artifacts with the report name are candidates
    Given the artifacts:
      | id | name                                    | expired |
      | 1  | conformance-results-ubuntu-latest-wasm  | false   |
      | 2  | conformance-results-ubuntu-latest-wasm  | true    |
      | 3  | conformance-results-windows-latest-wasm | false   |
      | 4  | conformance-results-ubuntu-latest-wasm  | false   |
    Then the candidate artifacts named "conformance-results-ubuntu-latest-wasm" are "1, 4"

  Scenario: The search skips newer runs, expired artifacts and incompatible reports
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    And the successful main runs 51, 50, 49, 48, 47 each have a passing report
    And the artifact of run 49 is expired
    And the report of run 48 has runner_os set to "Windows"
    When I search for the baseline
    Then the baseline is run 47 at commit "before"
    And the baseline URL is "https://github.com/owner/repo/actions/runs/47"
    And the requests are:
      """
      list workflow runs
      list artifacts of run 49
      list artifacts of run 48
      download artifact 48 of run 48
      list artifacts of run 47
      download artifact 47 of run 47
      """

  Scenario: Run ids larger than 32 bits are read exactly
    Given every suite reports 10 passed cases
    And CI runs workflow run "36900023900" of "owner/repo"
    And the successful main runs 36900023825 each have a passing report
    When I search for the baseline
    Then the baseline is run 36900023825 at commit "before"
    And the requests are:
      """
      list workflow runs
      list artifacts of run 36900023825
      download artifact 36900023825 of run 36900023825
      """

  Scenario: The commit of the run stands in for a report without a commit
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    And the successful main runs 49 each have a passing report
    And the report of run 49 has commit set to null
    When I search for the baseline
    Then the baseline is run 49 at commit "head-49"

  Scenario: An artifact over 16 MiB is not downloaded
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    And the successful main runs 49 each have a passing report
    And the artifact of run 49 has 16777217 bytes
    When I search for the baseline
    Then the baseline is unavailable because "Earlier artifacts contain invalid or incompatible reports"
    And the requests are:
      """
      list workflow runs
      list artifacts of run 49
      """

  Scenario: An artifact of exactly 16 MiB is downloaded
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    And the successful main runs 49 each have a passing report
    And the artifact of run 49 has 16777216 bytes
    When I search for the baseline
    Then the baseline is run 49 at commit "before"

  Scenario Outline: An unreadable report is skipped and named as the reason
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    And the successful main runs 49 each have a passing report
    And the report of run 49 <problem>
    When I search for the baseline
    Then the baseline is unavailable because "Earlier artifacts contain invalid or incompatible reports"

    Examples:
      | problem                |
      | is missing             |
      | is over 1 MiB          |
      | is not JSON            |
      | is not UTF-8           |

  Scenario: Only incompatible reports leave no baseline
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    And the successful main runs 49 each have a passing report
    And the report of run 49 has target set to "native"
    When I search for the baseline
    Then the baseline is unavailable because "No earlier successful main run has a compatible, unexpired artifact"

  Scenario: No earlier run leaves no baseline
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    When I search for the baseline
    Then the baseline is unavailable because "No earlier successful main run has a compatible, unexpired artifact"
    And the requests are:
      """
      list workflow runs
      """

  Scenario: Outside GitHub Actions there is no baseline
    Given every suite reports 10 passed cases
    When I search for the baseline
    Then the baseline is unavailable because "Not running in GitHub Actions"
    And the requests are:
      """
      """

  Scenario: A run id that is not a number gives no baseline
    Given every suite reports 10 passed cases
    And CI runs workflow run "latest" of "owner/repo"
    When I search for the baseline
    Then the baseline is unavailable because "Baseline unavailable: GITHUB_RUN_ID is not a number: latest"

  Scenario: Missing permissions do not fail the current run
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    And the GitHub API fails
    When I search for the baseline
    Then the baseline is unavailable because "Baseline unavailable: GitHub API unavailable: permissions, rate limit, or connectivity"
    When the wasm tests exit with code 0
    And I compare the reports
    Then the comparison is the unavailable baseline
    And the status is "passed"

  Scenario: A failed download does not fail the current run
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    And the successful main runs 49 each have a passing report
    And the download of run 49 fails
    When I search for the baseline
    Then the baseline is unavailable because "Baseline unavailable: GitHub API unavailable: permissions, rate limit, or connectivity"

  Scenario: A run listing without workflow runs gives no baseline
    Given every suite reports 10 passed cases
    And CI runs workflow run 50 of "owner/repo"
    And the run listing is {"message": "Not Found"}
    When I search for the baseline
    Then the baseline is unavailable because "Baseline unavailable: the workflow run listing is not valid"

  Scenario: Counts, revisions and missing suites stay distinct
    Given every suite reports 10 passed cases
    And suite "ion-files" has total set to 12
    And suite "ion-files" has passed set to 11
    And suite "ion-files" has unexpected set to 1
    And suite "ion-files" has out_of_scope set to 3
    And suite "isl-1.0" has passed set to 9
    And suite "isl-1.0" has known_failures set to 1
    And suite "ion-readers" reports nothing
    And the baseline is the passing report of run 49 at commit "before"
    When the wasm tests exit with code 0
    And the ion-tests revision changes to "new-corpus"
    And the report excludes "ion-dsl" because "reason"
    And I compare the reports
    Then the "ion-files" delta of passed is 1
    And the "ion-files" delta of unexpected is 1
    And the "isl-1.0" delta of known_failures is 1
    And suite "ion-readers" went from reported to missing
    And suite "ion-dsl" went from reported to excluded
    And the exclusion of "ion-dsl" changed
    And the corpus changes are "ion-tests"
    And the comparison summary is:
      """
      ### Change from successful main baseline

      Baseline: [run 49](https://github.com/owner/repo/actions/runs/49), commit `before`.

      Corpus revisions changed: ion-tests. Count changes may include added or removed corpus cases.

      - ion-tests: `unavailable` → `new-corpus`.

      Each delta compares the same OS, target, suite, and unit. Positive counts are increases, not necessarily improvements.

      | Corpus | Unit | Δ Total | Δ Passed | Δ Skipped | Δ Known failures | Δ N/A | Δ Unexpected | Δ Stale | Suite state |
      | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
      | Ion 1.0 corpus | files | +2 | +1 | +0 | +0 | +0 | +1 | +0 | reported → reported |
      | Ion readers and writers | checks | - | - | - | - | - | - | - | reported → missing |
      | Ion conformance DSL | cases | - | - | - | - | - | - | - | reported → excluded; exclusion changed |
      | Ion Schema 1.0 | cases | +0 | -1 | +0 | +1 | +0 | +0 | +0 | reported → reported |
      | Ion Schema 2.0 | cases | +0 | +0 | +0 | +0 | +0 | +0 | +0 | reported → reported |
      | Ion Hash identity serialization | cases | +0 | +0 | +0 | +0 | +0 | +0 | +0 | reported → reported |

      Ion 1.0 corpus: Δ corpus files +0; Δ out-of-scope files/forms +3.
      """
    And the comparison JSON is:
      """
      {
        "status": "available",
        "run_id": 49,
        "url": "https://github.com/owner/repo/actions/runs/49",
        "commit": "before",
        "current_commit": null,
        "baseline_corpora": {
          "ion-tests": null,
          "ion-schema-tests": null,
          "ion-hash-fixture-sha256": null
        },
        "current_corpora": {
          "ion-tests": "new-corpus",
          "ion-schema-tests": null,
          "ion-hash-fixture-sha256": null
        },
        "corpus_changes": [
          "ion-tests"
        ],
        "suites": {
          "ion-files": {
            "baseline_state": "reported",
            "current_state": "reported",
            "delta": {
              "total": 2,
              "passed": 1,
              "skipped": 0,
              "known_failures": 0,
              "not_applicable": 0,
              "unexpected": 1,
              "stale": 0,
              "files": 0,
              "out_of_scope": 3
            },
            "exclusion_changed": false
          },
          "ion-readers": {
            "baseline_state": "reported",
            "current_state": "missing",
            "delta": null,
            "exclusion_changed": false
          },
          "ion-dsl": {
            "baseline_state": "reported",
            "current_state": "excluded",
            "delta": null,
            "exclusion_changed": true
          },
          "isl-1.0": {
            "baseline_state": "reported",
            "current_state": "reported",
            "delta": {
              "total": 0,
              "passed": -1,
              "skipped": 0,
              "known_failures": 1,
              "not_applicable": 0,
              "unexpected": 0,
              "stale": 0,
              "files": 0,
              "out_of_scope": 0
            },
            "exclusion_changed": false
          },
          "isl-2.0": {
            "baseline_state": "reported",
            "current_state": "reported",
            "delta": {
              "total": 0,
              "passed": 0,
              "skipped": 0,
              "known_failures": 0,
              "not_applicable": 0,
              "unexpected": 0,
              "stale": 0,
              "files": 0,
              "out_of_scope": 0
            },
            "exclusion_changed": false
          },
          "ion-hash": {
            "baseline_state": "reported",
            "current_state": "reported",
            "delta": {
              "total": 0,
              "passed": 0,
              "skipped": 0,
              "known_failures": 0,
              "not_applicable": 0,
              "unexpected": 0,
              "stale": 0,
              "files": 0,
              "out_of_scope": 0
            },
            "exclusion_changed": false
          }
        }
      }
      """

  Scenario: A passing report of the same runner and target is compatible
    Given every suite reports 10 passed cases
    And the baseline is the passing report of run 49 at commit "before"
    When the wasm tests exit with code 0
    Then the baseline report is compatible

  Scenario Outline: An incompatible or incomplete baseline is rejected
    Given every suite reports 10 passed cases
    And the baseline is the passing report of run 49 at commit "before"
    And the baseline report has <key> set to <value>
    When the wasm tests exit with code 0
    Then the baseline report is incompatible

    Examples:
      | key             | value                        |
      | runner_os       | "Windows"                    |
      | target          | "native"                     |
      | status          | "incomplete"                 |
      | schema_version  | 99                           |
      | suites          | {}                           |
      | test_exit_code  | 1                            |
      | test_exit_code  | null                         |
      | errors          | ["no result reported"]       |
      | corpora         | []                           |
      | excluded_suites | null                         |
