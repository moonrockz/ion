# Agentic Instructions

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:  
[https://github.com/moonbitlang/skills](https://github.com/moonbitlang/skills)

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`, the order of each block is irrelevant. In some refactorings, you can process block by block independently.
- Try to keep deprecated blocks in file called `deprecated.mbt` in each  
directory.
- Never encode absence or failure as a sentinel value of the payload's owntype: no `""` for "no file", no `0`/`-1` for "unknown", no helper that aborts when a value is missing. Absence is `T?` (or a dedicated enum variant), and every caller handles it as its own branch. This applies on the wire too: a JSON field that can be absent is optional or a tagged variant, never an empty string the decoder has to recognize. Do not fold unrelated errors into the "missing" case either — a stat that fails for any reason other than the file being absent must not read as "deleted"; carry the failure so the UI can tell the two apart.

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

- Use `moon test` for package- or workspace-scoped MoonBit tests. MoonBit
  supports snapshot testing; when changes affect outputs, run
  `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. Use snapshot tests to record current
  behavior. For solid, well-defined results (e.g. scientific computations),
  prefer assertion tests. You can use `moon coverage analyze > uncovered.log` to
  see which parts of your code are not covered by tests.