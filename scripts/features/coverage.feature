Feature: Coverage report
  The coverage script turns Moon's coverage exports into a JSON report and a
  Markdown summary. Line coverage comes from the Coveralls export; the point
  totals come from Moon's text summary. A report is "passed" only when the
  tests passed and every export is complete and valid.

  Background:
    Given the project has the focused source files
    And the runner OS is "Linux"
    And the commit is "tested-commit"

  Scenario: Line coverage excludes uninstrumented lines and keeps points separate
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "passed"
    And the line coverage is 12 of 18
    And the point coverage is 12 of 24
    And file "pkgs/text/handler.mbt" has the uncovered lines "[2]"
    And package "pkgs/ion" has the line coverage 4 of 6
    And the summary is:
      """
      ## Code coverage

      Status: **passed**. Target: `wasm`. OS: Linux.

      Commit: `tested-commit`.

      Line coverage comes from Moon's Coveralls output; comments and uninstrumented lines are excluded. Moon's summary counts execution points, which can include several points on one line. These percentages are separate measures.

      | Measure | Covered / total | Coverage |
      | --- | ---: | ---: |
      | Executable lines | 12 / 18 | 66.67% |
      | Moon instrumentation points | 12 / 24 | 50.00% |

      ### Package line coverage

      | Package | Covered / total | Coverage |
      | --- | ---: | ---: |
      | pkgs/ion | 4 / 6 | 66.67% |
      | pkgs/json | 2 / 3 | 66.67% |
      | pkgs/schema | 4 / 6 | 66.67% |
      | pkgs/text | 2 / 3 | 66.67% |

      ### Focused files

      | File | Covered / total | Line coverage |
      | --- | ---: | ---: |
      | pkgs/text/handler.mbt | 2 / 3 | 66.67% |
      | pkgs/ion/fold.mbt | 2 / 3 | 66.67% |
      | pkgs/ion/visitor.mbt | 2 / 3 | 66.67% |
      | pkgs/json/to_ion.mbt | 2 / 3 | 66.67% |
      | pkgs/schema/load.mbt | 2 / 3 | 66.67% |
      | pkgs/schema/validate.mbt | 2 / 3 | 66.67% |

      Coverage percentages are informational. The coverage-results artifact includes HTML source views, Coveralls JSON, Cobertura XML, raw point totals, and per-file line counts with uncovered line numbers.
      """

  Scenario: The JSON report keeps its published field names
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the JSON report is:
      """
      {
        "schema_version": 1,
        "status": "passed",
        "target": "wasm",
        "runner_os": "Linux",
        "commit": "tested-commit",
        "test_exit_code": 0,
        "files": {
          "pkgs/text/handler.mbt": {
            "covered": 2,
            "total": 3,
            "percent": 66.66666666666667,
            "uncovered_lines": [
              2
            ],
            "source_digest": "digest"
          },
          "pkgs/ion/fold.mbt": {
            "covered": 2,
            "total": 3,
            "percent": 66.66666666666667,
            "uncovered_lines": [
              2
            ],
            "source_digest": "digest"
          },
          "pkgs/ion/visitor.mbt": {
            "covered": 2,
            "total": 3,
            "percent": 66.66666666666667,
            "uncovered_lines": [
              2
            ],
            "source_digest": "digest"
          },
          "pkgs/json/to_ion.mbt": {
            "covered": 2,
            "total": 3,
            "percent": 66.66666666666667,
            "uncovered_lines": [
              2
            ],
            "source_digest": "digest"
          },
          "pkgs/schema/load.mbt": {
            "covered": 2,
            "total": 3,
            "percent": 66.66666666666667,
            "uncovered_lines": [
              2
            ],
            "source_digest": "digest"
          },
          "pkgs/schema/validate.mbt": {
            "covered": 2,
            "total": 3,
            "percent": 66.66666666666667,
            "uncovered_lines": [
              2
            ],
            "source_digest": "digest"
          }
        },
        "packages": {
          "pkgs/text": {
            "covered": 2,
            "total": 3,
            "percent": 66.66666666666667
          },
          "pkgs/ion": {
            "covered": 4,
            "total": 6,
            "percent": 66.66666666666667
          },
          "pkgs/json": {
            "covered": 2,
            "total": 3,
            "percent": 66.66666666666667
          },
          "pkgs/schema": {
            "covered": 4,
            "total": 6,
            "percent": 66.66666666666667
          }
        },
        "errors": [],
        "lines": {
          "covered": 12,
          "total": 18,
          "percent": 66.66666666666667
        },
        "points": {
          "covered": 12,
          "total": 24,
          "percent": 50.0
        }
      }
      """

  Scenario Outline: A failed or missing test exit code makes the report partial
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "<argument>"
    When I build the coverage report
    Then the status is "partial"
    And the first error is "Instrumented tests failed or did not report an exit code; coverage is partial"
    And the summary contains "- Instrumented tests failed or did not report an exit code; coverage is partial"

    Examples:
      | argument |
      | 2        |
      |          |

  Scenario: An empty export cannot claim success
    Given the Coveralls report is '{}'
    And Moon reports the point summary ""
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "unavailable"
    And the summary is:
      """
      ## Code coverage

      Status: **unavailable**. Target: `wasm`. OS: Linux.

      Commit: `tested-commit`.

      Line coverage comes from Moon's Coveralls output; comments and uninstrumented lines are excluded. Moon's summary counts execution points, which can include several points on one line. These percentages are separate measures.


      ### Package line coverage

      | Package | Covered / total | Coverage |
      | --- | ---: | ---: |

      ### Focused files

      | File | Covered / total | Line coverage |
      | --- | ---: | ---: |

      Reporting errors:

      - no instrumented source files reported

      Coverage percentages are informational. The coverage-results artifact includes HTML source views, Coveralls JSON, Cobertura XML, raw point totals, and per-file line counts with uncovered line numbers.
      """

  Scenario Outline: Missing or malformed source lists cannot claim success
    Given the Coveralls report is '<report>'
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "unavailable"
    And the first error is "<error>"

    Examples:
      | report                 | error                                  |
      | {}                     | no instrumented source files reported  |
      | []                     | no instrumented source files reported  |
      | {"source_files": []}   | no instrumented source files reported  |
      | {"source_files": null} | no instrumented source files reported  |
      | {"source_files": [null]} | coverage source is not an object     |
      | {"source_files": [{}]} | coverage source has no name            |

  Scenario: A missing Coveralls report cannot claim success
    Given there is no Coveralls report
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "unavailable"
    And the first error is "no instrumented source files reported"

  Scenario Outline: Line hits must be null or non-negative integers
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And line 3 of "pkgs/text/handler.mbt" reports the hit count '<hits>'
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "unavailable"
    And the first error is "invalid line hits for pkgs/text/handler.mbt"

    Examples:
      | hits  |
      | -1    |
      | true  |
      | 0.5   |
      | "one" |

  Scenario Outline: Moon must report valid instrumentation-point totals
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And Moon reports the point summary "<summary>"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "partial"
    And the first error is "Moon did not report valid instrumentation-point totals"

    Examples:
      | summary      |
      |              |
      | Total: 25/24 |
      | Total: 0/0   |
      | Total: 1/x   |

  Scenario: The point total line can follow other summary lines
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And Moon reports the point summary:
      """
      pkgs/ion/fold.mbt: 3/4
      Total: 12/24
      """
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "passed"
    And the point coverage is 12 of 24

  Scenario: Every focused file must be instrumented
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    But the Coveralls report leaves out "pkgs/text/handler.mbt"
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "partial"
    And the first error is "focused source was not instrumented: pkgs/text/handler.mbt"

  Scenario Outline: Coverage sources must be project files
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And the first Coveralls source is named '<name>'
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "unavailable"
    And the first error is "coverage source is not a project file: <shown>"

    Examples:
      | name                    | shown                 |
      | "/etc/passwd"           | /etc/passwd           |
      | "pkgs/../../escape.mbt" | pkgs/../../escape.mbt |
      | "other/dependency.mbt"  | other/dependency.mbt  |
      | "pkgs/missing.mbt"      | pkgs/missing.mbt      |
      | 3                       | 3                     |

  Scenario: A source may appear only once
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And the Coveralls report lists "pkgs/text/handler.mbt" again
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "partial"
    And the first error is "duplicate coverage source: pkgs/text/handler.mbt"

  Scenario: A source with no executable lines cannot claim success
    Given the Coveralls report lists every focused file with the line hits "[null, null]"
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "partial"
    And the first error is "no executable source lines reported"
    And the summary contains "| Executable lines | 0 / 0 | n/a |"

  Scenario: Errors in the summary escape HTML
    Given the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And the first Coveralls source is named '"<x>"'
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the summary contains "- coverage source is not a project file: &lt;x&gt;"

  Scenario: Table rows escape HTML and pipes
    Given the project also has the file "pkgs/a|b<c>/x.mbt"
    And the Coveralls report lists every focused file with the line hits "[null, 0, 1, 2]"
    And the Coveralls report also lists "pkgs/a|b<c>/x.mbt" with the line hits "[1]"
    And Moon reports the point summary "Total: 12/24"
    And the test exit code argument is "0"
    When I build the coverage report
    Then the status is "passed"
    And the summary contains "| pkgs/a&#124;b&lt;c&gt; | 1 / 1 | 100.00% |"

  Scenario: Successful exports publish a passing report
    Given the Moon exports succeed
    When I summarize the exports with the test exit code argument "0"
    Then the exit status is 0
    And the status is "passed"
    And the JSON report commit is "tested-commit"

  Scenario: A failed HTML export fails the summary
    Given the Moon exports succeed
    But the html export fails with "missing traces"
    When I summarize the exports with the test exit code argument "0"
    Then the exit status is 1
    And the status is "partial"
    And the summary contains "- html report failed: missing traces"

  Scenario: Failed tests fail the summary
    Given the Moon exports succeed
    When I summarize the exports with the test exit code argument "2"
    Then the exit status is 1
    And the status is "partial"

  Scenario: A failed Coveralls export leaves no line coverage
    Given the Moon exports succeed
    But the coveralls export fails with "no traces"
    When I summarize the exports with the test exit code argument "0"
    Then the exit status is 1
    And the status is "unavailable"
    And the summary contains "- no instrumented source files reported"
    And the summary contains "- coveralls report failed: no traces"

  Scenario: A Coveralls export that is not JSON is a failed export
    Given the Moon exports succeed
    But the coveralls export writes "not json"
    When I summarize the exports with the test exit code argument "0"
    Then the exit status is 1
    And the status is "unavailable"
    And the summary contains "- coveralls report failed: "

  Scenario: A local run names no commit
    Given there is no commit
    And the Moon exports succeed
    When I summarize the exports with the test exit code argument "0"
    Then the exit status is 0
    And the JSON report commit is null
    And the summary contains "Commit: `local working tree`."
