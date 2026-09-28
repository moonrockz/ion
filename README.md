# moonrockz/ion

A [MoonBit](https://www.moonbitlang.com) implementation of Amazon
[Ion](https://amazon-ion.github.io/ion-docs/) — a richly-typed, self-describing,
hierarchical data serialization format — and
[Ion Schema](https://amazon-ion.github.io/ion-schema/).

> **Status:** early. The core data model, the Ion **text** and Ion **binary**
> encodings, **Ion Hash** (Ion Hash 1.0 over SHA-256), a focused Ion Schema
> validation subset, and **JSON interoperability** are implemented and tested,
> with asynchronous streaming readers and writers for both encodings over
> `moonbitlang/async`.

## Installation

```bash
moon add moonrockz/ion
```

## Packages

Each package has a README with checked examples, linked below.

| Package       | Source        | Import path            | Purpose |
| ------------- | ------------- | ---------------------- | ------- |
| `@ion` (core) | [`pkgs/ion`](pkgs/ion/README.md)    | `moonrockz/ion/ion`    | Core data model: Ion types, values, annotations, decimals, timestamps, symbol tokens |
| `@text`       | [`pkgs/text`](pkgs/text/README.md)   | `moonrockz/ion/text`   | Ion text reader and writer                              |
| `@text/stream` | [`pkgs/text/stream`](pkgs/text/stream/README.md) | `moonrockz/ion/text/stream` | Ion text readers and writers over asynchronous IO (`moonbitlang/async`) |
| `@hash`       | [`pkgs/hash`](pkgs/hash/README.md)   | `moonrockz/ion/hash`   | Ion Hash 1.0: an encoding-independent hash of an Ion value |
| `@binary`     | [`pkgs/binary`](pkgs/binary/README.md) | `moonrockz/ion/binary` | Ion binary codec: values, containers, annotations, and local symbol tables |
| `@binary/stream` | [`pkgs/binary/stream`](pkgs/binary/stream/README.md) | `moonrockz/ion/binary/stream` | The Ion binary codec over asynchronous IO (`moonbitlang/async`) |
| `@schema`     | [`pkgs/schema`](pkgs/schema/README.md) | `moonrockz/ion/schema` | Ion Schema model, loader, and validator                 |
| `@json`       | [`pkgs/json`](pkgs/json/README.md)   | `moonrockz/ion/json`   | JSON interoperability: `IonValue` ⇄ core `Json`          |
| `ion` CLI     | [`pkgs`](pkgs/README.md) | `moonrockz/ion`        | `ion print`, `ion json`, `ion fromjson`, `ion hash`, `ion validate` — the module root package is the executable |

## Repository layout

The module's source directory is `pkgs/` (`source = "pkgs"` in [moon.mod](moon.mod)),
so the repository root holds only module metadata, tooling, and tests.

- `pkgs/` is the module **root package**, `moonrockz/ion`, and it **is the `ion`
  executable** — so the published package is runnable at the short coordinate
  `moonx moonrockz/ion`;
- `pkgs/ion/` is the `@ion` core data model (`moonrockz/ion/ion`);
- `pkgs/text` (with the async `pkgs/text/stream`), `pkgs/hash`, `pkgs/binary`
  (with the async `pkgs/binary/stream`), `pkgs/json`, and `pkgs/schema` are the
  remaining library packages.

The executable owns the module root (instead of living in a `cmd/` package) so
that `moonx` can run it as `moonrockz/ion`; library users import the core model
as `moonrockz/ion/ion`.

## Quick start

Read and re-write Ion text:

```moonbit skip nocheck
let value = @text.read_ion("{ name: \"ion\", tags: [a, b] }")
println(@text.write_ion(value)) // {name: "ion", tags: [a, b]}
```

Read and write Ion **binary**:

```moonbit skip nocheck
let values = @text.read_ion_datagram("{ name: \"ion\" } 42")
let bytes = @binary.write_binary(values) // Ion binary, with a local symbol table
let decoded = @binary.read_binary(bytes) // back to the same values
```

Convert between Ion and JSON:

```moonbit skip nocheck
let value = @text.read_ion("{ name: \"ion\", tags: [a, b] }")
let json = @json.to_json(value) // {"name":"ion","tags":["a","b"]}
let ion = @json.to_ion(json)     // back to the Ion data model
```

Build a value programmatically:

```moonbit skip nocheck
let value = @ion.IonValue::from_fields([
  @ion.Field::new("name", @ion.IonValue::string("ion")),
  @ion.Field::new("tags", @ion.IonValue::list([
    @ion.IonValue::symbol("a"),
    @ion.IonValue::symbol("b"),
  ])),
])
```

Validate a value against an Ion Schema type:

```moonbit skip nocheck
let schema = @schema.Schema::load_from_text(
  "type::{ name: person, fields: { name: { type: string, occurs: required } } }",
)
let value = @text.read_ion("{ name: \"Ada\" }")
if schema.is_valid("person", value) {
  println("valid")
}
```

Command line (from the repository root; the CLI is the module root package):

```bash
moon run pkgs -- print data.ion
moon run pkgs -- hash data.ion
moon run pkgs -- validate schema.isl person data.ion
```

`print`, `json`, `hash`, and `validate` stream their Ion input (text or
binary, from a file or from stdin with `-`) through `@text/stream` and
`@binary/stream`: each value is read, handled, and dropped in turn, so memory
stays proportional to the largest value rather than to the input. An error
stops the command after the values before it are handled. The CLI builds for
the `native` and `wasm` targets, which `moonbitlang/async` supports.

Once published, the same commands run through `moonx` at the short coordinate:

```bash
moonx moonrockz/ion version
moonx moonrockz/ion print data.ion
moonx moonrockz/ion hash data.ion
moonx moonrockz/ion validate schema.isl person data.ion
```

## Parsing APIs

Like the moonrockz `gherkin` project, Ion offers four ways to consume a
document, over both a **CST** (concrete syntax) and an **AST** (the `IonValue`
data model):

| API | Entry points | Description |
| --- | --- | --- |
| CST | `@text.tokenize`, `@text.parse_cst` | A lossless token stream, and a syntax tree that keeps tokens and source spans |
| DOM (AST) | `@text.read_ion`, `@text.read_ion_datagram` | Build the `IonValue` tree for random access |
| Visitor | `@ion.IonVisitor` + `IonValue::accept` | Depth-first traversal; override only what you need |
| Fold | `@ion.IonFold` + `IonValue::fold` | Thread an accumulator with `Continue` / `SkipChildren` / `Stop` |
| SAX | `@text.IonReader` (pull) and `@text.IonHandler` + `@text.parse_with_handler` (push) | A flat `IonEvent` stream without building the DOM |
| Binary | `@binary.read_binary`, `@binary.write_binary`, `@binary/stream` | The Ion **binary** codec, with local symbol tables and an async streaming reader and writer |
| Streaming text | `@text/stream.TextReader` (values), `@text/stream.TextEventReader` (events), `@text/stream.TextWriter` | Ion **text** over async byte sources and sinks, one top-level value at a time |

```moonbit skip nocheck
let value = @text.read_ion("{a: 1}")               // DOM / AST
value.accept(visitor)                              // visitor
let total = value.fold(0, @ion.IonFold::default()) // fold
let tokens = @text.tokenize("int32::12")           // CST tokens
@text.parse_with_handler("1 2 3", handler)         // SAX (push)
```

### Streaming Ion text

`@text/stream` reads and writes Ion text over `moonbitlang/async` byte
sources and sinks. The reader decodes the UTF-8 as it arrives and parses one
top-level value at a time, so memory stays proportional to the largest value,
not to the stream:

```moonbit skip nocheck
let reader = @stream.TextReader::new(source) // moonrockz/ion/text/stream; any &@io.Reader
while reader.next() is Some(value) {
  println(@text.write_ion(value))
}
let writer = @stream.TextWriter::new(sink) // any &@io.Writer
writer.write(value)                        // one value per line
@stream.write_all(sink, values, pretty=true)
```

`TextReader` yields the values that `@text.read_ion_datagram` returns for the
whole text, and `TextEventReader` yields the events that `@text.IonReader`
returns for it. `TextWriter` and `write_all` write the UTF-8 octets of
`@text.write_all` (or `@text.write_all_pretty`), one value at a time.

Text has no length prefix, so a value is settled when it closes with `]`, `)`,
`}`, or `"`. Any other value, such as a number or a symbol, is settled only
when the text after it shows where it ends. The reader reads each code unit
once to track containers, strings, comments, and lobs, and it parses only when
the text is back at the top level between values. Thus a large value costs
time linear in its length. Until the stream ends, a value that does not parse
is taken to be cut short, and the reader reads on. Thus a malformed value is
reported only at the end of the stream, and the reader holds the text from
that value on until then. `@text.read_ion_prefix` is the parsing step on its
own, for a caller that feeds text in some other way.

## Ion Hash

`@hash` implements [Ion Hash 1.0](https://amazon-ion.github.io/ion-hash/docs/spec.html)
over SHA-256: a value is serialized to a canonical byte sequence that does not
depend on the encoding or on symbol IDs, then hashed. Struct fields are
unordered, so their hashes are sorted, and timestamps are normalized to UTC.

```moonbit skip nocheck
let value = @text.read_ion("{ name: \"ion\", tags: [a, b] }")
let digest = @hash.ion_hash_hex(value) // lowercase SHA-256
let bytes = @hash.ion_hash(value)      // 32 raw bytes
```

The digest function is pluggable, as the specification requires:
`@hash.ion_hash_with(value, h)` accepts any `h : (Array[Byte]) -> Array[Byte]`
for both the final digest and the struct field hashes. Passing the identity
function yields the serialization `s(value)` itself.

The implementation is checked against the official
[conformance suite](https://github.com/amazon-ion/ion-hash-test):
`pkgs/hash/conformance_test.mbt` replays `tests/fixtures/ion_hash_tests.ion`
and compares the serialization byte for byte, for both the text (`ion`) and
the binary (`10n`) cases.

## JSON interoperability

`@json` converts between the Ion data model and MoonBit's core `Json` type, in
both directions. JSON is a strict subset of Ion, so the two directions are not
inverses:

```moonbit skip nocheck
let value = @text.read_ion("{ data: annot::{time: 1969-07-20T20:18Z}, n: 1.50 }")
let json = @json.to_json(value) // {"data":{"time":"1969-07-20T20:18Z"},"n":1.50}
let ion = @json.to_ion(json)     // back into the Ion data model
```

- **JSON to Ion** is faithful in the sense that a JSON value converted to Ion
  and back is the same JSON value, and it follows the cookbook's
  [JSON-to-Ion rules](https://amazon-ion.github.io/ion-docs/guides/cookbook.html#migrating-json-data-to-ion):
  `null`, booleans, strings, arrays, and objects map to the matching Ion
  values, and a number becomes an Ion `int`, `decimal`, or `float` according to
  its spelling. The spelling core kept in `repr` wins when present — core keeps
  an integer literal above 2^53 - 1 and any literal that overflows a `Double` —
  so large integers survive exactly; otherwise the number's shortest round-trip
  spelling decides, so `1.50` becomes the Ion decimal `1.5` and `1e-7` an Ion
  float.
- **Ion to JSON** is lossy and follows the Ion cookbook's
  [down-conversion process](https://amazon-ion.github.io/ion-docs/guides/cookbook.html#down-converting-to-json):
  a null of any type becomes `null`; integers and decimals keep their precision;
  `nan` and `±inf` become `null`; timestamps and symbols become strings; a clob
  becomes a Latin-1 string and a blob a Base64 string; lists and s-expressions
  become arrays; a struct becomes an object; annotations are dropped. A symbol
  known only by symbol ID has no text, so converting it raises
  `IonError::Unsupported` rather than inventing one.

`@json.read_json` and `@json.write_json` wrap the same rules for JSON text:

```moonbit skip nocheck
let value = @json.read_json("{\"a\": [1, 2]}") // {a: [1, 2]}
let text = @json.write_json(value)               // {"a":[1,2]}
```

The CLI exposes both directions: `ion json [file]` reads Ion (text or binary)
and prints JSON, and `ion fromjson [file]` reads JSON and prints Ion text.

## Design notes

- **Annotations live on the value.** Every `IonValue` carries an ordered
  annotation list plus a kind, so readers, writers, and validators reach
  annotations the same way.
- **Absence is `T?`, never a sentinel.** A `SymbolToken` has `text : String?` and
  `sid : Int?`; a decimal keeps an explicit negative-zero flag; a timestamp keeps
  an optional `TimestampOffset`.
- **Exact numbers.** Integers and decimals are exact (`BigInt`
  coefficient/exponent), so precision and signed zero round-trip through text.
- **Decimal arithmetic is opt-in.** `add`/`subtract`/`multiply`/`compare`/
  `to_double` and conversion go through `moonbitlang/x/decimal`, whose decimal is
  normalized and caps the scale, so those helpers document what they drop; the
  value type itself keeps Ion's exact scale and signed zero.
- **Derived precision.** A timestamp's precision is derived from which
  components are present, not stored separately.
- **One symbol table for both encodings.** `@ion.SymbolTable` holds the
  symbols in effect in a stream. The text and binary readers apply a version
  marker (`$ion_1_0` unquoted at the top level, or the binary marker) and a
  top-level `$ion_symbol_table::{...}` struct to it instead of returning them,
  and resolve each symbol ID against it. A symbol ID beyond the table is an
  error; one whose slot has no text keeps only its ID, and the writers keep
  that ID by reserving it in the symbol table they write.
- **Unsupported is an error.** The schema loader raises
  `IonError::Unsupported` for constructs it does not implement, rather than
  silently ignoring them.

## Roadmap

Each item is a [GitHub issue](https://github.com/moonrockz/ion/issues);
test-suite work carries the
[`testing`](https://github.com/moonrockz/ion/issues?q=is%3Aissue+label%3Atesting)
label.

- Shared symbol tables ([#2](https://github.com/moonrockz/ion/issues/2)):
  there is no catalog, so an import resolves as a table the catalog does not
  hold, reserving `max_id` symbol IDs with unknown text. A catalog API would
  give those symbols their text.
- Ion Schema ([#5](https://github.com/moonrockz/ion/issues/5)):
  `ordered_elements`, `annotations`, `timestamp_precision`, `regex`,
  `closed::` fields, imports, open content, the decimal `precision`/`exponent`
  constraints, `valid_values` ranges, and `exclusive::` range bounds. The
  [Cookbook](https://amazon-ion.github.io/ion-schema/docs/cookbook/)'s
  `logical-relationships` page is already covered by
  `tests/fixtures/cookbook-logical-relationships.isl`; the other pages need
  the constraints above.
- UTF-16 and UTF-32 Ion text ([#6](https://github.com/moonrockz/ion/issues/6)):
  the text readers take decoded strings, and the CLI and stream readers decode
  only UTF-8, so the two ion-tests files in those encodings are skipped.
- Ion 1.1 ([#7](https://github.com/moonrockz/ion/issues/7)): only Ion 1.0 is
  implemented.
- Ion binary output from the CLI ([#8](https://github.com/moonrockz/ion/issues/8)).
- An incremental writer that writes containers without building them first
  ([#9](https://github.com/moonrockz/ion/issues/9)).
- An event reader for Ion binary ([#10](https://github.com/moonrockz/ion/issues/10)).

## Building and testing

Tooling is configured with [mise](https://mise.jdx.dev):

```bash
mise run setup       # fetch the ion-tests submodule and install dependencies
mise run test:check  # moon check
mise run test:unit   # moon test (unit, doc, snapshot, conformance, QuickCheck)
mise run test:all    # check + test
mise run build:native
moon fmt             # format
moon info            # regenerate package interfaces (*.mbti)
moon test --update   # refresh the golden fixtures' recorded output
```

The official [ion-tests](https://github.com/amazon-ion/ion-tests) suite is a
git submodule at `tests/ion-tests`. `mise run setup` fetches it, and
`mise run test:unit` fetches it first when it is missing; without mise, run
`git submodule update --init` (or clone with `--recurse-submodules`).
`pkgs/conformance` runs every Ion 1.0 file in it: each `good` file must read
and survive a round trip through both writers, each `bad` file must fail, and
the `equivs` and `non-equivs` sequences must compare as their directory says.
The two files skipped, each with its reason, are listed in
`pkgs/conformance/ion_tests_test.mbt`; a skipped file that starts to pass fails
the test.

Besides the example and snapshot tests, several packages carry property tests
(`property_test.mbt`) using the built-in QuickCheck: text round-trips, decimal
and timestamp rendering, binary type descriptors, Ion Hash invariances, and the
JSON conversions are checked over generated inputs, with counterexamples shrunk
to a minimal case.

## License

Apache-2.0. See [LICENSE](LICENSE).
