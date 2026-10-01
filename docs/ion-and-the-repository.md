# Ion and the repository

## Read an Ion value

Ion has a data model and two encodings, text and binary. This example is
Ion text:

```ion
order::{
  id: 7,
  status: shipped,
  total: 19.990,
  placed: 2024-05-01T10:00Z,
  note: null.string,
  items: ["book", "pen"],
}
```

`order::` is an annotation. `shipped` is a symbol; `"shipped"` would be a
string. `19.990` is an exact decimal with a retained scale, while `19.990e0`
would be a floating-point value. `placed` is a timestamp, and `null.string`
is a typed null. The struct's field order has no meaning. A list's element
order does.

An annotation labels a value but does not enforce a type. A schema can
check that label and the value's contents. Reading Ion and validating an
application's data are separate operations.

An Ion datagram is a sequence of top-level values. It needs no enclosing
list. For example, `{id: 1} {id: 2}` contains two values; `[{id: 1}, {id: 2}]`
contains one list value. The CLI processes each top-level value separately.

Text and binary represent the same Ion data model. Transcoding preserves
values but discards comments, whitespace, and choices such as hexadecimal
integer spelling. Use the text package's tokenizer and concrete syntax
tree when you need to retain source syntax. See the
[Ion specification](https://amazon-ion.github.io/ion-docs/docs/spec.html)
for the complete format.

## Choose a package

Add the library to your MoonBit module:

```sh
moon add moonrockz/ion
```

Import only the packages you use in your package's `moon.pkg`. For example:

```moonbit
import {
  "moonrockz/ion/ion" @ion,
  "moonrockz/ion/text" @text,
}
```

All codecs use `@ion.IonValue`. A value holds its annotations and an
`IonValueKind`, which you can inspect with `value.kind()` and exhaustive
pattern matching. Integers and decimals retain exact values; converting them
to machine integers or floating point is a separate decision.

| Import path | Use it for | Checked examples |
| --- | --- | --- |
| `moonrockz/ion/ion` | Values, fields, symbols, decimals, timestamps, traversal | [Data model](../pkgs/ion/README.mbt.md) |
| `moonrockz/ion/text` | Text parsing, rendering, tokens, syntax trees, events | [Text](../pkgs/text/README.mbt.md) |
| `moonrockz/ion/binary` | Binary parsing and rendering | [Binary](../pkgs/binary/README.mbt.md) |
| `moonrockz/ion/text/stream` | Async text readers and writers | [Text streaming](../pkgs/text/stream/README.mbt.md) |
| `moonrockz/ion/binary/stream` | Async binary readers and writers | [Binary streaming](../pkgs/binary/stream/README.mbt.md) |
| `moonrockz/ion/schema` | Ion Schema 1.0 and 2.0 loading and validation | [Schema](../pkgs/schema/README.mbt.md) |
| `moonrockz/ion/json` | JSON import and export | [JSON](../pkgs/json/README.mbt.md) |
| `moonrockz/ion/hash` | Encoding-independent Ion Hash over SHA-256 | [Hash](../pkgs/hash/README.mbt.md) |
| `moonrockz/ion/cli` | Run commands with your own input and output streams | [CLI library](../pkgs/cli/README.mbt.md) |

The module root, `moonrockz/ion`, is the executable. The core data model's
import path includes the final `/ion`.

## Run the tools from a checkout

Install the MoonBit toolchain and mise before running the repository tasks.
From the repository root:

```sh
mise run setup
mise run test:all
mise run build:native
```

`setup` fetches dependencies and the pinned upstream test-data submodules.
`test:all` type-checks the packages and runs unit, executable documentation,
snapshot, property, and conformance tests. `build:native` builds the CLI.
Use `mise tasks` to see the other operations.

The cookbook uses `moon run pkgs -- <command>` to run this checkout's CLI.
For example:

```sh
moon run pkgs -- print --pretty docs/cookbook/examples/people.ion
moon run pkgs -- help validate
```

With the published module, use `moonx moonrockz/ion <command>`. With an
installed executable, use `ion <command>`. These all reach the same command
interface; see the [CLI reference](../pkgs/README.md).

## Find the implementation and tests

The module sets `source = "pkgs"` in [moon.mod](../moon.mod).

| Directory | Contents |
| --- | --- |
| `pkgs/` | The executable and library packages |
| `pkgs/conformance/` | Tests against the upstream Ion and Ion Schema suites |
| `tests/ion-tests/` | Upstream Ion corpus as a Git submodule |
| `tests/ion-schema-tests/` | Upstream schema corpus as a Git submodule |
| `tests/fixtures/` | Golden files and existing examples |
| `docs/cookbook/` | Task guides and their runnable example files |
| `mise-tasks/`, `.mise.toml` | Build, test, and release tasks |

Each package's `pkg.generated.mbti` lists its public signatures. Its
`README.mbt.md` contains examples run by `moon test`. Blackbox tests in
`*_test.mbt` show the APIs as callers use them.

This repository implements Ion 1.0. Ion Schema 2.0 is a schema-language
version, and does not mean Ion 2.0 data.
