Feature: Conformance summary
  `ci.mbtx conformance` reads the CONFORMANCE records that the conformance
  tests print, checks them, and publishes a JSON report and a Markdown
  summary. Each record is one line: `CONFORMANCE ` and a JSON object with the
  suite name, the nine counts and the details. The summary never claims a
  pass that the records do not prove.

  Scenario: Known failures, skips and N/A cases are not passes
    Given every suite reports 10 passed cases
    And suite "isl-1.0" has passed set to 8
    And suite "isl-1.0" has known_failures set to 2
    And suite "isl-1.0" has files set to 3
    And suite "ion-dsl" has passed set to 6
    And suite "ion-dsl" has skipped set to 2
    And suite "ion-dsl" has not_applicable set to 2
    And suite "ion-dsl" has out_of_scope set to 4
    And suite "ion-hash" has passed set to 9
    And suite "ion-hash" has skipped set to 1
    When the wasm tests exit with code 0
    Then the status is "passed"
    And the summary is:
      """
      ## Corpus conformance

      Result: **passed**. Target: `wasm`.
      Runner OS: Linux.
      Test command exit code: 0.

      | Corpus | Unit | Total | Passed | Skipped | Known failures | N/A | Unexpected | Stale exclusions | Status |
      | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
      | Ion 1.0 corpus | files | 10 | 10 | 0 | 0 | 0 | 0 | 0 | Passed |
      | Ion readers and writers | checks | 10 | 10 | 0 | 0 | 0 | 0 | 0 | Passed |
      | Ion conformance DSL | cases | 10 | 6 | 2 | 0 | 2 | 0 | 0 | Passed |
      | Ion Schema 1.0 | cases | 10 | 8 | 0 | 2 | 0 | 0 | 0 | Passed |
      | Ion Schema 2.0 | cases | 10 | 10 | 0 | 0 | 0 | 0 | 0 | Passed |
      | Ion Hash identity serialization | cases | 10 | 9 | 1 | 0 | 0 | 0 | 0 | Passed |

      Counts use each runner's unit; they are not a combined test total.
      Known failures and skipped cases are excluded from passes. N/A cases do not apply to Ion 1.0.
      Stale exclusions fail the suite even when their cases pass.

      ### Corpus revisions

      Commit: `unavailable`.

      - ion-tests: `unavailable`.
      - ion-schema-tests: `unavailable`.
      - ion-hash-fixture-sha256: `unavailable`.

      <details>
      <summary>Ion conformance DSL details</summary>

      Ion 1.1 test forms not run: 4.

      </details>

      <details>
      <summary>Ion Schema 1.0 details</summary>

      Files: 3.

      </details>

      The conformance-results artifact contains this summary, JSON counts, and the full test log.
      """

  Scenario: Failure counts and details survive a failed test command
    Given every suite reports 10 passed cases
    And suite "ion-files" has passed set to 9
    And suite "ion-files" has unexpected set to 1
    And suite "ion-files" has details set to ["bad/input.ion: accepted"]
    When the wasm tests exit with code 2
    Then the status is "failed"
    And the summary contains:
      """
      | Ion 1.0 corpus | files | 10 | 9 | 0 | 0 | 0 | 1 | 0 | Failed |
      """
    And the summary contains:
      """
      - bad/input.ion: accepted
      """

  Scenario: A stale exclusion fails the suite even when every case passes
    Given every suite reports 10 passed cases
    And suite "ion-dsl" has stale set to 1
    When the wasm tests exit with code 0
    Then the status is "failed"

  Scenario: A failed test command fails the report even when the corpora pass
    Given every suite reports 10 passed cases
    When the wasm tests exit with code 1
    Then the status is "failed"

  Scenario: A missing suite makes the report incomplete
    Given every suite reports 10 passed cases
    And suite "ion-readers" reports nothing
    When the wasm tests exit with code 0
    Then the status is "incomplete"
    And the errors are:
      """
      no result reported for ion-readers
      """
    And the summary contains:
      """
      | Ion readers and writers | checks | - | - | - | - | - | - | - | Not reported |
      """

  Scenario: A missing exit code does not claim success
    Given every suite reports 10 passed cases
    When the wasm tests report no exit code
    Then the status is "incomplete"
    And the errors are:
      """
      test command did not report an exit code
      """
    And the summary contains:
      """
      Test command exit code: None.
      """

  Scenario: Tests that never ran give one error for each suite and the exit code
    Given an empty test log
    When the wasm tests report no exit code
    Then the status is "incomplete"
    And the errors are:
      """
      no result reported for ion-files
      no result reported for ion-readers
      no result reported for ion-dsl
      no result reported for isl-1.0
      no result reported for isl-2.0
      no result reported for ion-hash
      test command did not report an exit code
      """

  Scenario: wasm-gc reports the disabled corpora as excluded
    Given an empty test log
    And suite "ion-hash" reports 10 passed cases
    When the wasm-gc tests exit with code 0
    Then the status is "passed"
    And 5 suites are excluded
    And the summary contains:
      """
      | Ion 1.0 corpus | files | - | - | - | - | - | - | - | Excluded |
      """
    And the summary contains:
      """
      ### Target exclusions

      - The conformance package is disabled on wasm-gc because of the upstream BigInt conversion bug: https://github.com/moonrockz/ion/issues/13
      """
    And the summary does not contain "Not reported"

  Scenario: wasm-gc still requires the Ion Hash suite
    Given an empty test log
    When the wasm-gc tests exit with code 0
    Then the status is "incomplete"
    And the errors are:
      """
      no result reported for ion-hash
      """

  Scenario: A corpus that runs again on wasm-gc needs its exclusion removed
    Given every suite reports 10 passed cases
    When the wasm-gc tests exit with code 0
    Then the status is "incomplete"
    And the errors are:
      """
      excluded suite reported results; remove its target exclusion: ion-files
      excluded suite reported results; remove its target exclusion: ion-readers
      excluded suite reported results; remove its target exclusion: ion-dsl
      excluded suite reported results; remove its target exclusion: isl-1.0
      excluded suite reported results; remove its target exclusion: isl-2.0
      """

  Scenario Outline: An invalid record makes the report incomplete
    Given every suite reports 10 passed cases
    And suite "ion-files" has <key> set to <value>
    When the wasm tests exit with code 0
    Then the status is "incomplete"
    And an error contains "<error>"

    Examples:
      | key     | value        | error                               |
      | suite   | "unknown"    | unknown corpus suite                |
      | passed  | -1           | invalid count passed for ion-files  |
      | passed  | 2.5          | invalid count passed for ion-files  |
      | total   | true         | invalid count total for ion-files   |
      | files   | null         | invalid count files for ion-files   |
      | passed  | 9            | counts do not add up for ion-files  |
      | details | "not a list" | invalid details for ion-files       |
      | details | [1]          | invalid details for ion-files       |

  Scenario: A record that is not JSON makes the report incomplete
    Given every suite reports 10 passed cases
    And suite "ion-files" reports nothing
    And the log also contains:
      """
      CONFORMANCE not json
      """
    When the wasm tests exit with code 0
    Then the status is "incomplete"
    And the errors are:
      """
      invalid JSON: Invalid character 'o' at line 1, column 1
      no result reported for ion-files
      """

  Scenario: A record that is not a JSON object names no known suite
    Given every suite reports 10 passed cases
    And the log also contains:
      """
      CONFORMANCE ["ion-files"]
      """
    When the wasm tests exit with code 0
    Then the status is "incomplete"
    And the errors are:
      """
      unknown corpus suite
      """

  Scenario: A duplicate record is rejected
    Given every suite reports 10 passed cases
    And suite "ion-files" reports 10 passed cases again
    When the wasm tests exit with code 0
    Then the status is "incomplete"
    And the errors are:
      """
      duplicate result for ion-files
      """

  Scenario: Other output and records with Windows line ends are read
    Given an empty test log
    And the log also contains:
      """
      this line has CONFORMANCE {} but not at the start
      """
    And suite "ion-hash" reports 10 passed cases with a Windows line end
    When the wasm-gc tests exit with code 0
    Then the status is "passed"

  Scenario: Details are escaped for Markdown tables and HTML
    Given every suite reports 10 passed cases
    And suite "ion-dsl" has details set to ["<script> | multiline\nreason & more"]
    When the wasm tests exit with code 0
    Then the summary contains:
      """
      - &lt;script&gt; &#124; multiline reason &amp; more
      """
    And the summary does not contain "<script>"

  Scenario: The JSON report keeps the layout of the Python report
    Older reports on main are baselines for new runs, so the field names,
    their order and the ASCII escapes stay the same.

    Given an empty test log
    And the log also contains:
      """
      noise
      CONFORMANCE {"suite": "ion-hash", "total": 10, "passed": 9, "skipped": 0, "known_failures": 0, "not_applicable": 0, "unexpected": 1, "stale": 0, "files": 0, "out_of_scope": 0, "details": ["bad/input.ion: accepted", "café 😀 → <x>"]}
      """
    When the wasm-gc tests exit with code 2
    Then the JSON report is:
      """
      {
        "schema_version": 1,
        "status": "failed",
        "test_exit_code": 2,
        "target": "wasm-gc",
        "runner_os": "Linux",
        "excluded_suites": {
          "ion-files": "The conformance package is disabled on wasm-gc because of the upstream BigInt conversion bug: https://github.com/moonrockz/ion/issues/13",
          "ion-readers": "The conformance package is disabled on wasm-gc because of the upstream BigInt conversion bug: https://github.com/moonrockz/ion/issues/13",
          "ion-dsl": "The conformance package is disabled on wasm-gc because of the upstream BigInt conversion bug: https://github.com/moonrockz/ion/issues/13",
          "isl-1.0": "The conformance package is disabled on wasm-gc because of the upstream BigInt conversion bug: https://github.com/moonrockz/ion/issues/13",
          "isl-2.0": "The conformance package is disabled on wasm-gc because of the upstream BigInt conversion bug: https://github.com/moonrockz/ion/issues/13"
        },
        "commit": null,
        "corpora": {
          "ion-tests": null,
          "ion-schema-tests": null,
          "ion-hash-fixture-sha256": null
        },
        "suites": {
          "ion-hash": {
            "suite": "ion-hash",
            "total": 10,
            "passed": 9,
            "skipped": 0,
            "known_failures": 0,
            "not_applicable": 0,
            "unexpected": 1,
            "stale": 0,
            "files": 0,
            "out_of_scope": 0,
            "details": [
              "bad/input.ion: accepted",
              "caf\u00e9 \ud83d\ude00 \u2192 <x>"
            ]
          }
        },
        "errors": []
      }
      """
    And the summary is:
      """
      ## Corpus conformance

      Result: **failed**. Target: `wasm-gc`.
      Runner OS: Linux.
      Test command exit code: 2.

      | Corpus | Unit | Total | Passed | Skipped | Known failures | N/A | Unexpected | Stale exclusions | Status |
      | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
      | Ion 1.0 corpus | files | - | - | - | - | - | - | - | Excluded |
      | Ion readers and writers | checks | - | - | - | - | - | - | - | Excluded |
      | Ion conformance DSL | cases | - | - | - | - | - | - | - | Excluded |
      | Ion Schema 1.0 | cases | - | - | - | - | - | - | - | Excluded |
      | Ion Schema 2.0 | cases | - | - | - | - | - | - | - | Excluded |
      | Ion Hash identity serialization | cases | 10 | 9 | 0 | 0 | 0 | 1 | 0 | Failed |

      Counts use each runner's unit; they are not a combined test total.
      Known failures and skipped cases are excluded from passes. N/A cases do not apply to Ion 1.0.
      Stale exclusions fail the suite even when their cases pass.

      ### Corpus revisions

      Commit: `unavailable`.

      - ion-tests: `unavailable`.
      - ion-schema-tests: `unavailable`.
      - ion-hash-fixture-sha256: `unavailable`.

      ### Target exclusions

      - The conformance package is disabled on wasm-gc because of the upstream BigInt conversion bug: https://github.com/moonrockz/ion/issues/13

      <details>
      <summary>Ion Hash identity serialization details</summary>


      - bad/input.ion: accepted
      - café 😀 → &lt;x&gt;

      </details>

      The conformance-results artifact contains this summary, JSON counts, and the full test log.
      """

  Scenario: The summary says when no baseline is available
    Given every suite reports 10 passed cases
    And no baseline is available because "Not running in GitHub Actions"
    When the wasm tests exit with code 0
    Then the summary contains:
      """
      ### Change from successful main baseline

      Baseline unavailable: Not running in GitHub Actions.

      The conformance-results artifact contains this summary, JSON counts, and the full test log.
      """
    And the JSON report contains:
      """
        "comparison": {
          "status": "unavailable",
          "reason": "Not running in GitHub Actions"
        }
      """

  Scenario Outline: The runner OS names the baseline artifact
    Then the artifact for runner OS "<os>" and target <target> is "<artifact>"

    Examples:
      | os      | target  | artifact                                  |
      | Linux   | wasm    | conformance-results-ubuntu-latest-wasm    |
      | Windows | native  | conformance-results-windows-latest-native |
      | macOS   | wasm-gc | conformance-results-macos-latest-wasm-gc  |
      | Darwin  | js      | conformance-results-macos-latest-js       |

  Scenario: A runner OS without a CI runner has no baseline artifact
    Then the runner OS "Plan9" has no baseline artifact

  Scenario: The conformance arguments name the log, the exit code, the target and the output directory
    When I parse the conformance arguments:
      """
      out/moon-test.log
      --exit-code
      2
      --target
      wasm-gc
      --output-dir
      out
      """
    Then the log path is "out/moon-test.log"
    And the exit code is 2
    And the target is wasm-gc
    And the output directory is "out"

  Scenario: An empty exit code means that the tests did not run
    When I parse the conformance arguments:
      """
      moon-test.log
      --exit-code

      --output-dir
      out
      """
    Then there is no exit code
    And the target is wasm

  Scenario Outline: Bad conformance arguments are rejected
    When I parse the conformance arguments "<arguments>"
    Then the conformance arguments are rejected with "<message>"

    Examples:
      | arguments                                       | message                                                 |
      | --exit-code 0 --output-dir out                  | conformance: <log> is required                          |
      | moon-test.log --output-dir out                  | conformance: --exit-code is required                    |
      | moon-test.log --exit-code 0                     | conformance: --output-dir is required                   |
      | moon-test.log --exit-code two --output-dir out  | conformance: --exit-code must be an integer or empty: two |
      | moon-test.log --exit-code 0 --output-dir out --target x | conformance: unknown target x                   |
      | moon-test.log extra --exit-code 0 --output-dir out | conformance: unknown argument extra                  |
