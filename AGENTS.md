# Agentic Instructions

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Overview

This module (`moonrockz/ion`) is a MoonBit implementation of the
[Amazon Ion](https://amazon-ion.github.io/ion-docs/) data format. It is
**primarily a library**; the `ion` CLI is a thin wrapper over it. It provides:

- **Data model** -- the Ion 1.0 value types, typed nulls, annotations, exact
  decimals, timestamps with precision, and symbol tokens
- **Text and binary encodings** -- readers (DOM, streaming, event), writers
  (sync, async, incremental) and round trips between them
- **Ion Schema** -- ISL 1.0 and ISL 2.0 loading and validation
- **Ion Hash** and **JSON** conversion
- **CLI** -- `ion print | json | fromjson | hash | validate`

### Architecture Summary

```
moonrockz/ion
├── pkgs/                 # Package sources (moon.mod: source = "pkgs")
│   ├── main.mbt          # The `ion` executable; runs @cli
│   ├── ion/              # Core data model
│   ├── text/             # Ion text reader, writer, tokenizer, CST
│   ├── binary/           # Ion binary reader and writer
│   ├── schema/           # Ion Schema loader and validator
│   ├── hash/             # Ion Hash
│   ├── json/             # JSON <-> Ion conversion
│   ├── cli/              # CLI commands
│   ├── conformance/      # Upstream conformance suites (test-only)
│   └── benchmarks/       # Benchmarks
├── tests/
│   ├── ion-tests/        # Submodule: amazon-ion/ion-tests
│   ├── ion-schema-tests/ # Submodule: amazon-ion/ion-schema-tests
│   └── fixtures/         # Golden fixtures and examples
├── .beads/               # Issue tracking (bd)
├── .dev/                 # Gitignored working area
└── mise-tasks/           # File-based mise tasks
```

## Project Principles

- **Specification compliance comes first.** ion is 0.x. When compliance and
  API compatibility conflict, choose compliance and make the breaking change.
  Do not add compatibility modes or flags that keep non-compliant behavior.
  Mark the commit as breaking (`!`).
- **Ion 1.0 only.** Do not start Ion 1.1 work until the upstream Ion 1.1
  specification is final.

## Library Dependencies

Treat `moonbitlang/core`, `moonbitlang/x` and `moonbitlang/async` as the
MoonBit core library. Look in them first before you write a helper or add a
third-party dependency. `moonbitlang/core` ships with the toolchain; keep `x`
and `async` on their latest release when you bump the toolchain.

Org test libraries, added to a package's test imports when a test first needs
them:

| Module | Purpose |
|--------|---------|
| `moonbitlang/core/quickcheck` | Property-based tests (in use) |
| [moonrockz/moonspec](https://mooncakes.io/docs/moonrockz/moonspec) | BDD: Gherkin features with step definitions |
| [moonrockz/expect](https://mooncakes.io/docs/moonrockz/expect) | Fluent assertions: `@expect.expect(actual).to_equal(expected)` |

Use `import { ... } for "test"` (or `for "wbtest"`) in `moon.pkg` for
test-only dependencies.

## Design Philosophy

This project follows **functional design principles**. These are
non-negotiable:

- **Algebraic data types (ADTs)**: Model domain concepts with enums (sum
  types) and structs (product types).
- **Make invalid states unrepresentable**: Design types so that illegal
  combinations cannot be constructed. The type system prevents a state that
  must not exist, not a runtime check.
- **Avoid primitive obsession**: Do not use a raw `String`, `Int` or `Bool`
  where a domain type is correct (for example `SymbolToken`, `Timestamp`,
  `IonType`).
- **Prefer immutability**: Use `mut` only when mutation is necessary and
  local. Return new values.
- **Pattern matching over conditionals**: Use exhaustive `match` on enums.
- **Composition over inheritance**: Compose small, focused functions and
  types.
- **Total functions**: Handle all inputs. Use `Option`, `Result` or `raise`
  with a typed `suberror`. Reserve `abort` for states that the type system
  cannot prevent and that are truly impossible.

## Coding Convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.
- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.
- Never encode absence or failure as a sentinel value of the payload's own
  type: no `""` for "no file", no `0`/`-1` for "unknown", no helper that
  aborts when a value is missing. Absence is `T?` (or a dedicated enum
  variant), and every caller handles it as its own branch. This applies on the
  wire too: a JSON field that can be absent is optional or a tagged variant,
  never an empty string the decoder has to recognize. Do not fold unrelated
  errors into the "missing" case either — a stat that fails for any reason
  other than the file being absent must not read as "deleted"; carry the
  failure so the UI can tell the two apart.
- Use `derive(Debug)` (not `derive(Show)`) for data types; `assert_eq` needs
  `Debug`. Implement `Show` by hand only for real text formats.

## Testing

The test suite has two jobs:

1. **Prove the library is correct** -- comprehensive coverage of behavior,
   edge cases and the Ion specifications.
2. **Document the library** -- a reader learns how to use each API, and which
   constraints the library imposes or adheres to, by reading its tests.

Write every test for both jobs. Give each test a name that states the
behavior or constraint (`"decimal keeps negative zero"`, not `"test 3"`).
Write blackbox tests (`*_test.mbt`) through the public API, the way a library
user calls it. Use whitebox tests (`*_wbtest.mbt`) only for internals that the
public API cannot reach. In blackbox tests, qualify names from the package
under test (for example `@text.read_ion_datagram`).

### Test-Driven Development (TDD)

This project practices **strict TDD**. Write tests **before** implementation
code.

1. **Red**: Write a failing test that describes the behavior. Run it. Confirm
   it fails for the correct reason.
2. **Green**: Write the **minimum** code that makes the test pass.
3. **Refactor**: Clean up while all tests stay green.

- Never write implementation code without a failing test first.
- Keep each cycle small: one function, one edge case, one enum variant.
- A bug fix starts with a test that reproduces the bug.
- Use `#declaration_only` to sketch a public API before you implement it.
  Write tests against the declared signatures, then replace each declaration
  as its tests go green:

  ```moonbit
  #declaration_only
  pub fn read_ion_datagram(
    text : StringView,
    catalog? : @ion.Catalog,
  ) -> Array[@ion.IonValue] raise @ion.IonError {
    ...
  }
  ```

### Test Layers

Pick the layer that makes the behavior clearest to a reader. One change often
needs more than one layer.

| Layer | Where | Use it for |
|-------|-------|------------|
| Executable docs | `pkgs/<pkg>/README.mbt.md` (`mbt` code blocks run in `moon test`) | How to use each package. Every public API that a user starts from has a working example here. |
| Example tests | `*_test.mbt` | One behavior or constraint per test, with explicit inputs and expected results. |
| Snapshot tests | `inspect(value, content=...)`; golden fixtures in `tests/fixtures/` (for example `pkgs/text/fixture_test.mbt`) | Large or structured output: rendered text, event traces, diagnostics. Review every snapshot diff; refresh with `moon test --update`. |
| Property tests | `property_test.mbt` with `@quickcheck.check` | Laws over generated inputs: round trips (text, binary, JSON), equivalence, hash invariance, ordering. Prefer a property when the rule holds for all inputs. |
| BDD features | Gherkin `.feature` files run by moonspec | Behavior that reads best as scenarios: CLI commands, schema validation, user-visible workflows. Write the feature first, then drop down to unit tests. |
| Conformance | `pkgs/conformance/` over `tests/ion-tests` and `tests/ion-schema-tests` | Compliance with the upstream suites. This is the compliance gate. |

Assertions:

- Prefer `assert_eq` or `assert_true(x is Pattern(...))` for stable,
  well-defined results. In new tests you may use `@expect` for readable
  assertions; existing `assert_eq` tests stay.
- Use snapshots to record output that is large or that a reader must see.
- Use `moon coverage analyze > uncovered.log` (or `mise run test:coverage`) to
  find code without tests.

Conformance rules:

- Keep the upstream suites passing. Do not change a conformance expectation to
  make a test pass.
- A skip or known failure needs a reason and a tracked bd issue. A skipped case
  that starts to pass fails the run, so the skip lists stay accurate.
- Update the pinned submodule revisions on purpose, in their own commit.

### Completing a Change

A change is not done until:

- Its tests were written first and now pass at every relevant layer.
- The conformance suites pass.
- `moon info && moon fmt` leave no unexpected diff (check the `.mbti` files).

## Conventional Commits

All commit messages MUST follow
**[Conventional Commits](https://www.conventionalcommits.org)**:

```
type(scope): description
```

| Type | Purpose | Changelog section | Version bump |
|------|---------|-------------------|--------------|
| `feat` | New feature | Added | MINOR |
| `fix` | Bug fix | Fixed | PATCH |
| `refactor` | Code restructuring | Changed | - |
| `perf` | Performance improvement | Performance | - |
| `docs` | Documentation only | Documentation | - |
| `test` | Adding or updating tests | (skipped) | - |
| `build` | Build system changes | (skipped) | - |
| `ci` | CI/CD configuration | (skipped) | - |
| `chore` | Maintenance tasks | (skipped) | - |
| `style` | Code formatting (no logic) | (skipped) | - |

Breaking changes: add `!` after the type (`feat(text)!: ...`) or a
`BREAKING CHANGE:` footer.

Scopes: `ion`, `text`, `binary`, `schema`, `hash`, `json`, `cli`,
`conformance`, `benchmarks`, `ci`, `build`, `release`, `beads`.

`CHANGELOG.md` is generated by git-cliff (`mise run release:changelog`).
Never edit it by hand.

## Mise Tasks

Run all build, test and release operations with `mise run <task>`. Run
`mise tasks` to list them.

| Task | Purpose |
|------|---------|
| `setup` | Fetch the submodules and the MoonBit dependencies |
| `hooks:install` | Install the git hooks (lefthook) |
| `test:check` | `moon check` |
| `test:unit` | `moon test` (unit, doc, snapshot, property, conformance) |
| `test:all` | Check and test |
| `test:coverage` | Instrumented wasm tests and coverage reports |
| `build:native` | Native CLI binary |
| `build:wasm` | wasm release build |
| `bench` | Native release benchmarks and CLI peak RSS |
| `release:*` | Version, changelog, notes, credentials, assets |

Org rules:

- Tasks are **file-based scripts** in `mise-tasks/` with `#MISE` metadata.
  Use subdirectories for namespaces: `mise-tasks/hooks/install` is
  `hooks:install`.
- `.mise.toml` holds only `[tools]`. Do not add inline `[tasks]`.
- GitHub workflows call `mise run <task>`, not inline shell scripts. If a
  workflow needs a new operation, create a task for it first.

ion still defines most tasks inline in `.mise.toml`; moving them is tracked in
bd. Put every new task in `mise-tasks/`.

## Scripts

Project tooling logic is written in MoonBit, not bash, Python, `jq` or `awk`.

- Put tooling logic in standalone scripts: `scripts/<name>.mbtx`.
- Keep each mise task a one-line launcher:
  `exec moon run -q --target wasm scripts/<name>.mbtx -- <args>`.
- In a script, put logic in pure functions. `async fn main` does only I/O.
- Specify each script's behavior in `scripts/features/<name>.feature`, run by
  moonspec from an `async test` in the script.
- Pin module imports in each script to the versions the module uses.
- A task that calls one command can stay bash.

ion's CI tooling is still Python in `.github/scripts/`; porting it is tracked
in bd. Do not add new Python or bash tooling logic. See `moonrockz/krueger`
`scripts/` for the pattern.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Use `mise run test:unit` for tests and `moon test --update` to refresh
  snapshots.

- Git hooks (lefthook): pre-commit runs `moon fmt --check` and `moon check`;
  pre-push runs `mise run test:all`. Both also run the bd hooks.

## The `.dev/` Working Area

`.dev/` is a gitignored scratch area for AI-assisted development: temporary
scripts, agent and script outputs, and working documents. Nothing in it is
committed. Layout:

- Specs from the superpowers `brainstorming` skill:
  `.dev/docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- Plans from the superpowers `writing-plans` skill:
  `.dev/docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.md`
- Scratch scripts and their outputs: `.dev/scripts/`, `.dev/out/`

This layout overrides the default location of any skill or tool. Never place
specs, plans or other working documents under `docs/`, and never `git add`
anything under `.dev/`. When a design is final and meant for readers, write it
up in a committed location on purpose.

## Release Process

- Publishes to **mooncakes.io** first, then **GitHub Releases**.
- Trigger: push a tag `v*`, or run the release workflow (workflow_dispatch).
- Requires the `MOONCAKES_USER_TOKEN` org secret.
- Pre-publish: `mise run release:pre-check` (`moon fmt --check`, `moon check`,
  `moon test`).
- Tags and releases are **immutable**: never force-push a tag, never delete
  and recreate a release. Fix a bad release with a new patch release.

## Work Tracking

**bd (beads) is the primary tracker for all work.** GitHub Issues are the
public intake for reports from outside contributors.

- Track every task, bug, feature and epic in bd. Do NOT use markdown TODO
  lists or other tracking methods.
- Mirror each GitHub issue into bd with `--external-ref gh-<number>`, and keep
  the two in step: when the bd issue closes, close the GitHub issue.
- A pull request that resolves a GitHub issue says `Closes #<number>` in its
  body. Name the bd issue in the body too.
- Work lands on `main` through pull requests (squash merge). Branch first;
  do not push to `main`.

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT
use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: syncs through a Dolt remote on the Git origin
  (`refs/dolt/data`), separate from source branches
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:ion-123 --json
bd create "Issue title" --description="..." --external-ref gh-46 --json   # mirror a GitHub issue
```

**Claim and update:**

```bash
bd update ion-42 --status in_progress --json
bd update ion-42 --priority 1 --json
```

**Complete work:**

```bash
bd close ion-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task**: `bd update <id> --status in_progress`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Storage and Sync

- bd stores issues in an embedded Dolt database at `.beads/embeddeddolt/`
  (not committed).
- Git worktrees share the database of the main checkout. Do not create a
  database inside a worktree.
- Cross-machine sync uses a Dolt remote on the GitHub origin. Dolt keeps issue
  history under `refs/dolt/data`, separate from source branches:
  - `bd sync` — pull, check for conflicts, and push in one step.
  - `bd dolt pull` / `bd dolt push` — the individual steps.
- Issue changes need no commit or pull request: `bd sync` publishes them to
  `refs/dolt/data`.
- `.beads/issues.jsonl` is a passive export (`bd export -o .beads/issues.jsonl`)
  for viewers and interchange. It is gitignored; do not commit it.

### Setup on a Fresh Clone

```bash
mise run setup          # submodules and MoonBit dependencies
bd bootstrap            # clones refs/dolt/data from origin and wires the Dolt remote
mise run hooks:install  # installs lefthook git hooks (these call `bd hooks run <hook>`)
git config beads.role maintainer   # or contributor
```

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT duplicate tracking systems (GitHub issues are mirrored, not tracked twice)

<!-- END BEADS INTEGRATION -->

## Landing the Plane (Session Completion)

When you end a work session, complete ALL steps below. Work is NOT complete
until the pushes succeed.

1. **File issues for remaining work** in bd.
2. **Run quality gates** if code changed: `mise run test:all`,
   `moon info && moon fmt`.
3. **Update issue status**: close finished work, update in-progress items.
4. **Push** (mandatory):
   ```bash
   bd sync                  # publish issue changes to refs/dolt/data
   git pull --rebase
   git push                 # your branch; open or update its pull request
   git status               # MUST show "up to date with origin"
   ```
5. **Clean up**: clear stashes, prune merged branches.
6. **Hand off**: give context for the next session.

Never stop before pushing; that leaves work stranded on one machine. If a push
fails, resolve the cause and retry.
