Feature: Git hooks installation
  `hooks.mbtx install` (the `hooks:install` task) installs the lefthook git
  hooks from lefthook.yml. lefthook owns the hooks and calls `bd hooks run`.
  `bd init` can point core.hooksPath at .beads/hooks, so the install removes
  that override first: `lefthook install --reset-hooks-path` is not enough,
  because lefthook 2.1.1 writes the hooks into the old path before it unsets it.

  Scenario: The install removes the hooks path override, then runs lefthook
    Then the install commands are:
      """
      git config --local --unset core.hooksPath
      lefthook install
      """

  Scenario Outline: Removing the override fails only on a git error
    When git exits with <code> while removing the override
    Then the override step <result>

    Examples:
      | code | result                                                              |
      | 0    | succeeds                                                            |
      | 5    | succeeds                                                            |
      | 1    | fails with "git config --unset core.hooksPath failed with exit code 1" |
      | 128  | fails with "git config --unset core.hooksPath failed with exit code 128" |
