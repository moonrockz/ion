Feature: CI test run
  `ci.mbtx test` runs `moon test` for one target. It copies the merged
  stdout and stderr of moon to the console and to a log file as the output
  arrives, writes the exit code to GITHUB_OUTPUT when it is set, and exits
  with the exit code of moon.

  Scenario: The target is wasm when no target is given
    When I parse the test arguments "--log out/moon-test.log"
    Then the commands are:
      """
      moon test --target wasm
      """
    And the log file is "out/moon-test.log"
    And the log directory is "out"

  Scenario: The tests run for the given target
    When I parse the test arguments "--target native --log moon-test.log"
    Then the commands are:
      """
      moon test --target native
      """
    And the log has no parent directory

  Scenario: Coverage cleans old coverage data and instruments the tests
    When I parse the test arguments "--target wasm --coverage --log moon-test.log"
    Then the commands are:
      """
      moon coverage clean
      moon test --target wasm --enable-coverage
      """

  Scenario: The tests run without coverage when the flag is absent
    When I parse the test arguments "--target wasm-gc --log moon-test.log"
    Then the commands are:
      """
      moon test --target wasm-gc
      """

  Scenario: The log file is required
    When I parse the test arguments "--target wasm"
    Then the arguments are rejected with "test: --log <file> is required"

  Scenario: An unknown target is rejected
    When I parse the test arguments "--target wasm64 --log moon-test.log"
    Then the arguments are rejected with "test: unknown target wasm64"

  Scenario: An unknown argument is rejected
    When I parse the test arguments "--log moon-test.log --verbose"
    Then the arguments are rejected with "test: unknown argument --verbose"

  Scenario Outline: GITHUB_OUTPUT receives the exit code of moon
    Then the GitHub output for exit code <code> is "exit_code=<code>"

    Examples:
      | code |
      | 0    |
      | 2    |
