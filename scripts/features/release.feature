Feature: Release tooling
  The Release workflow decides the version (`release plan`), writes the
  mooncakes.io credentials (`release credentials`), collects the CLI binaries
  (`release assets`), tags the commit (`release tag`) and makes the GitHub
  release notes with git-cliff (`release notes`).

  Scenario Outline: Choose the next version from git-cliff
    Given git-cliff exits with <code> and prints "<stdout>"
    Then the next version is "<version>"

    Examples:
      | code | stdout  | version     |
      | 0    | v0.4.0  | 0.4.0       |
      | 0    | 0.4.0   | 0.4.0       |
      | 0    | v1.0.0-rc.1 | 1.0.0-rc.1 |
      | 1    | v0.4.0  | 0.1.0       |
      | 127  |         | 0.1.0       |
      | 0    |         | 0.1.0       |

  Scenario Outline: Plan a release run
    Given the event is "<event>"
    And the ref type is "<ref type>" and the ref name is "<ref name>"
    And git-cliff computes the version "<computed>"
    And moon.mod has the version "<module>"
    And the tag for the version exists: "<tag exists>"
    When I plan the release
    Then the plan outputs are "<outputs>"

    Examples:
      | event             | ref type | ref name    | computed | module      | tag exists | outputs                                                  |
      | push              | tag      | v0.4.0      | 9.9.9    | 0.4.0       | yes        | version=0.4.0 prerelease=false tag_exists=true          |
      | push              | tag      | 0.4.0       | 9.9.9    | 0.4.0       | yes        | version=0.4.0 prerelease=false tag_exists=true          |
      | workflow_dispatch | branch   | main        | 0.4.0    | 0.4.0       | no         | version=0.4.0 prerelease=false tag_exists=false         |
      | workflow_dispatch | tag      | v0.4.0      | 9.9.9    | 0.4.0       | yes        | error: releases run only from main (current: v0.4.0)    |
      | workflow_dispatch | branch   | main        | 1.0.0-rc.1 | 1.0.0-rc.1 | no        | version=1.0.0-rc.1 prerelease=true tag_exists=false     |
      | push              | tag      | v1.0.0-rc.1 | 9.9.9    | 1.0.0-rc.1  | yes        | version=1.0.0-rc.1 prerelease=true tag_exists=true      |

  Scenario: A manual run off main is rejected
    Given the event is "workflow_dispatch"
    And the ref type is "branch" and the ref name is "feature/x"
    When I plan the release
    Then planning fails with "releases run only from main (current: feature/x)"

  Scenario: A version that differs from moon.mod is rejected
    Given the event is "push"
    And the ref type is "tag" and the ref name is "v0.5.0"
    And moon.mod has the version "0.4.0"
    When I plan the release
    Then planning fails with "moon.mod has version 0.4.0, but the release is 0.5.0"

  Scenario: A moon.mod without a version is rejected
    Given the event is "workflow_dispatch"
    And the ref type is "branch" and the ref name is "main"
    And git-cliff computes the version "0.4.0"
    And moon.mod has no version
    When I plan the release
    Then planning fails with "moon.mod has no version, but the release is 0.4.0"

  Scenario: The plan outputs for GITHUB_OUTPUT
    Given the event is "push"
    And the ref type is "tag" and the ref name is "v0.4.0-beta.2"
    And moon.mod has the version "0.4.0-beta.2"
    And the tag for the version exists: "yes"
    When I plan the release
    Then the plan output lines are:
      """
      version=0.4.0-beta.2
      prerelease=true
      tag_exists=true
      """

  Scenario Outline: Read the version from moon.mod
    Given the moon.mod line '<line>'
    Then the module version is "<version>"

    Examples:
      | line                 | version |
      | version = "0.3.1"    | 0.3.1   |
      | version="0.3.1"      | 0.3.1   |
      | version = "1.0.0-rc" | 1.0.0-rc |
      | name = "moonrockz/ion" | none  |
      | version = 0.3.1      | none    |

  Scenario Outline: Choose the git-cliff arguments for the release notes
    When I make the notes for version "<version>" and the tag exists: "<tag exists>"
    Then git-cliff runs with "<arguments>"

    Examples:
      | version | tag exists | arguments                                       |
      |         | no         | --latest --strip header                         |
      | 0.4.0   | yes        | --latest --strip header                         |
      | v0.4.0  | yes        | --latest --strip header                         |
      | 0.4.0   | no         | --unreleased --tag v0.4.0 --strip header        |
      | v0.4.0  | no         | --unreleased --tag v0.4.0 --strip header        |

  Scenario Outline: Name the release tag
    When I tag the version "<version>"
    Then the tag is "<tag>"

    Examples:
      | version    | tag         |
      | 0.4.0      | v0.4.0      |
      | v0.4.0     | v0.4.0      |
      | 1.0.0-rc.1 | v1.0.0-rc.1 |

  Scenario: Tag and push the release
    When I tag the version "0.4.0"
    Then the commands are:
      """
      git tag -a v0.4.0 -m Release v0.4.0
      git push origin v0.4.0
      """

  Scenario: Plain token
    Given the token is "abc123"
    When I render the credentials
    Then the credentials file is:
      """
      {"token": "abc123"}
      """

  Scenario: Token with characters that JSON must escape
    Given the token is 'a"b\c'
    When I render the credentials
    Then the credentials file is:
      """
      {"token": "a\"b\\c"}
      """

  Scenario Outline: A missing token is rejected
    Given <token>
    When I render the credentials
    Then rendering fails with "MOONCAKES_USER_TOKEN is not set"

    Examples:
      | token                |
      | no token is set      |
      | the token is ""      |

  Scenario: Map the build artifacts to the release assets
    Then the release assets are:
      | source                                  | target                         | executable |
      | artifacts/ion-linux-amd64/ion.exe       | release/ion-linux-amd64        | yes        |
      | artifacts/ion-macos-arm64/ion.exe       | release/ion-macos-arm64        | yes        |
      | artifacts/ion-windows-amd64.exe/ion.exe | release/ion-windows-amd64.exe  | no         |

  Scenario: Missing build artifacts are rejected
    Given the build artifact "artifacts/ion-macos-arm64/ion.exe" is missing
    And the build artifact "artifacts/ion-windows-amd64.exe/ion.exe" is missing
    When I check the build artifacts
    Then the check fails with "missing build artifacts: artifacts/ion-macos-arm64/ion.exe, artifacts/ion-windows-amd64.exe/ion.exe"

  Scenario: All build artifacts are present
    When I check the build artifacts
    Then the check passes

  Scenario Outline: List a release asset
    Then the listing of "<name>" with <size> bytes is "<line>"

    Examples:
      | name                  | size    | line                                |
      | ion-linux-amd64       | 4194304 | ion-linux-amd64 (4194304 bytes)     |
      | ion-windows-amd64.exe | 12      | ion-windows-amd64.exe (12 bytes)    |

  Scenario Outline: Read the command line
    When I read the arguments "<arguments>"
    Then the command is "<command>"

    Examples:
      | arguments     | command        |
      | version       | version        |
      | plan          | plan           |
      | notes         | notes          |
      | notes 0.4.0   | notes 0.4.0    |
      | tag 0.4.0     | tag 0.4.0      |
      | credentials   | credentials    |
      | assets        | assets         |
      |               | usage          |
      | tag           | usage          |
      | notes a b     | usage          |
      | publish       | usage          |
