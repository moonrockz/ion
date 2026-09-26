# moonrockz/ion

A [MoonBit](https://www.moonbitlang.com) implementation of Amazon
[Ion](https://amazon-ion.github.io/ion-docs/) — a richly-typed, self-describing,
hierarchical data serialization format — and
[Ion Schema](https://amazon-ion.github.io/ion-schema/).

> **Status:** early. The core data model, the Ion **text** encoding, and a
> focused Ion Schema validation subset are implemented and tested. The Ion
> **binary** wire codec is the next milestone.

## Installation

```bash
moon add moonrockz/ion
```

## Packages

| Package       | Source        | Import path            | Purpose |
| ------------- | ------------- | ---------------------- | ------- |
| `@ion` (core) | `pkgs/ion`    | `moonrockz/ion/ion`    | Core data model: Ion types, values, annotations, decimals, timestamps, symbol tokens |
| `@text`       | `pkgs/text`   | `moonrockz/ion/text`   | Ion text reader and writer                              |
| `@binary`     | `pkgs/binary` | `moonrockz/ion/binary` | Ion binary type descriptors and version marker          |
| `@schema`     | `pkgs/schema` | `moonrockz/ion/schema` | Ion Schema model, loader, and validator                 |
| `ion` CLI     | `pkgs`        | `moonrockz/ion`        | `ion print`, `ion validate` — the module root package is the executable |

## Repository layout

The module's source directory is `pkgs/` (`source = "pkgs"` in [moon.mod](moon.mod)),
so the repository root holds only module metadata, tooling, and tests.

- `pkgs/` is the module **root package**, `moonrockz/ion`, and it **is the `ion`
  executable** — so the published package is runnable at the short coordinate
  `moonx moonrockz/ion`;
- `pkgs/ion/` is the `@ion` core data model (`moonrockz/ion/ion`);
- `pkgs/text`, `pkgs/binary`, and `pkgs/schema` are the remaining library
  packages.

The executable owns the module root (instead of living in a `cmd/` package) so
that `moonx` can run it as `moonrockz/ion`; library users import the core model
as `moonrockz/ion/ion`.

## Quick start

Read and re-write Ion text:

```moonbit skip nocheck
let value = @text.read_ion!("{ name: \"ion\", tags: [a, b] }")
println(@text.write_ion!(value)) // {name: "ion", tags: [a, b]}
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
let schema = @schema.Schema::load_from_text!(
  "type::{ name: person, fields: { name: { type: string, occurs: required } } }",
)
let value = @text.read_ion!("{ name: \"Ada\" }")
if schema.is_valid("person", value) {
  println("valid")
}
```

Command line (from the repository root; the CLI is the module root package):

```bash
moon run pkgs -- print data.ion
moon run pkgs -- validate schema.isl person data.ion
```

Once published, the same commands run through `moonx` at the short coordinate:

```bash
moonx moonrockz/ion version
moonx moonrockz/ion print data.ion
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

```moonbit skip nocheck
let value = @text.read_ion!("{a: 1}")               // DOM / AST
value.accept(visitor)                               // visitor
let total = value.fold(0, @ion.IonFold::default())  // fold
let tokens = @text.tokenize!("int32::12")           // CST tokens
@text.parse_with_handler!("1 2 3", handler)         // SAX (push)
```

## Design notes

- **Annotations live on the value.** Every `IonValue` carries an ordered
  annotation list plus a kind, so readers, writers, and validators reach
  annotations the same way.
- **Absence is `T?`, never a sentinel.** A `SymbolToken` has `text : String?` and
  `sid : Int?`; a decimal keeps an explicit negative-zero flag; a timestamp keeps
  an optional `TimestampOffset`.
- **Exact numbers.** Integers and decimals are exact (`BigInt`
  coefficient/exponent), so precision and signed zero round-trip through text.
- **Derived precision.** A timestamp's precision is derived from which
  components are present, not stored separately.
- **Unsupported is an error.** The schema loader raises
  `IonError::Unsupported` for constructs it does not implement, rather than
  silently ignoring them.

## Roadmap

- Ion binary wire codec, including local symbol tables and the annotation
  wrapper.
- Ion Schema: `ordered_elements`, `annotations`, `timestamp_precision`,
  `regex`, `closed::` fields, imports, and open content.
- Streaming readers over byte and character sources.
- JSON interoperability (`IonValue` ⇄ `Json`).

## Building and testing

Tooling is configured with [mise](https://mise.jdx.dev):

```bash
moon update          # install dependencies
mise run test:check  # moon check
mise run test:unit   # moon test
mise run test:all    # check + test
mise run build:native
moon fmt             # format
moon info            # regenerate package interfaces (*.mbti)
```

## License

Apache-2.0. See [LICENSE](LICENSE).
