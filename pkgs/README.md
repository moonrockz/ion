# The `ion` command-line tool (`moonrockz/ion`)

The module's root package is the `ion` executable, so a published version
runs as `moonx moonrockz/ion`. The commands themselves live in
[`moonrockz/ion/cli`](cli/README.md), which this package runs with the
process's arguments and standard streams. From a checkout, run it with
`moon run pkgs -- <command>`, or build a native binary with
`mise run build:native`.

```
ion print [--binary | --pretty] [file|-]        Ion text or binary in; Ion text, pretty text, or binary out
ion json [file|-]                               Ion text or binary in, JSON out
ion fromjson [file|-]                           JSON in, Ion text out
ion hash [file|-]                               Ion Hash (SHA-256) of each value
ion validate <schema-file> <type-name> [file|-] validate each value
ion version                                     also `ion --version` or `ion -V`
ion help [command]                              also `ion --help` or `ion <command> --help`
```

`--catalog <file>`, before or after the command and as many times as needed,
names an Ion file of `$ion_shared_symbol_table::{...}` structs; imports of
those shared tables in the input then resolve to their symbols' text.

`validate` loads the schemas that the schema file imports. An import's `id`
is a path relative to the schema file's directory, or to the directory that
`--schema-root <dir>` names.

A missing file argument, or `-`, reads stdin. Ion input may be text or binary;
the Ion binary version marker at its start decides.

## Examples

```bash
$ cat people.ion
{ name: "Ada", born: 1815 } { name: 42 }

$ ion print people.ion
{name: "Ada", born: 1815}
{name: 42}

$ ion print --binary people.ion > people.10n
$ ion print people.10n
{name: "Ada", born: 1815}
{name: 42}

$ ion json people.ion
{"name":"Ada","born":1815}
{"name":42}

$ echo '{"a": [1, 2.5]}' | ion fromjson
{a: [1, 25d-1]}

$ ion hash people.ion
5d2dbea37f03297ad83be8aa10f162c10e0c1e90fd950ce7b4972093774cdf2a
be93d3daaf4fe159a03cfe8e4b0c02394de41c4b2a690257f4d194e0ba1fc21e

$ cat person.isl
type::{ name: person, type: struct, fields: { name: { type: string, occurs: required }, born: int } }

$ ion validate person.isl person people.ion
value 1: $.name: expected one of [string] but found int
1 of 2 value(s) failed validation
$ echo $?
1
```

## Behavior

- `print`, `json`, `hash`, and `validate` stream their Ion input through
  `moonrockz/ion/text/stream` and `moonrockz/ion/binary/stream`: each value
  is read, handled, and dropped in turn, so memory stays proportional to the
  largest value, not to the input.
- `print --binary` writes each value as it arrives, declaring each new symbol
  text once, in a local symbol table that appends to the ones before.
- An error stops a command after the values before it are handled, prints a
  message to stderr, and exits with status 1. So does a validation failure.
  Arguments that do not make a command print an error and the help of the
  command they concern to stderr, and exit with status 2.
- [`moonbitlang/core/argparse`](https://mooncakes.io/docs/moonbitlang/core/argparse)
  parses the arguments.
- `fromjson` reads its whole input, since a JSON document is one value.
- The tool builds for the `native` and `wasm` targets, which
  `moonbitlang/async` supports for files and stdin.
