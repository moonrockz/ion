Feature: CLI smoke test
  `cli.mbtx smoke` (the `test:cli` task) runs the `ion` command-line tool from
  a checkout (`moon run pkgs -- <command>`) on the fixtures in tests/fixtures.
  Each check prints its title, then the output of the tool. The run stops at
  the first failed check.

  Scenario: The smoke test covers each command
    Then the smoke checks are:
      | title                                              | command                                                    | stdin                    | expect   |
      | Print an Ion fixture                               | print tests/fixtures/sample.ion                            |                          | succeeds |
      | Convert an Ion fixture to JSON                     | json tests/fixtures/sample.ion                             |                          | succeeds |
      | Stream Ion from stdin                              | hash -                                                     | tests/fixtures/sample.ion | succeeds |
      | Round-trip a fixture through Ion binary            | round trip tests/fixtures/sample.ion                       |                          | same     |
      | Convert a JSON fixture to Ion                      | fromjson tests/fixtures/sample.json                        |                          | succeeds |
      | Validate fixtures (a violation must exit non-zero) | validate tests/fixtures/person.isl person tests/fixtures/person.ion |                          | fails    |

  Scenario: The tool runs from the checkout
    Then the command for "print tests/fixtures/sample.ion" is "moon run -q pkgs -- print tests/fixtures/sample.ion"

  Scenario Outline: A check passes when the exit code meets its expectation
    When the check "<command>" that <expect> exits with <code>
    Then the check <result>

    Examples:
      | command                          | expect   | code | result                                                                            |
      | print tests/fixtures/sample.ion  | succeeds | 0    | passes                                                                            |
      | print tests/fixtures/sample.ion  | succeeds | 2    | fails with "ion print tests/fixtures/sample.ion failed with exit code 2"          |
      | validate a.isl t b.ion           | fails    | 1    | passes                                                                            |
      | validate a.isl t b.ion           | fails    | 0    | fails with "ion validate a.isl t b.ion unexpectedly succeeded"                    |

  Scenario Outline: A binary round trip must print the same text as the fixture
    When the text print is "<text>" and the print of the binary copy is "<binary>"
    Then the round trip of "tests/fixtures/sample.ion" <result>

    Examples:
      | text      | binary    | result                                                                                   |
      | {a: 1}    | {a: 1}    | passes                                                                                   |
      | {a: 1}    | {a: 2}    | fails with "the binary round trip of tests/fixtures/sample.ion changed the printed text" |
