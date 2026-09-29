# Ion Schema (`moonrockz/ion/schema`)

Loads [Ion Schema 2.0](https://amazon-ion.github.io/ion-schema/) type
definitions and validates Ion values against them. It covers a focused subset
of the language; a construct it does not implement raises
`@ion.IonError::Unsupported` when the schema loads, rather than being ignored.

Supported constraints: `type`, `fields` (with `occurs`, `required`, and
`optional`), `element`, `valid_values`, `container_length` and
`codepoint_length`, `contains`, `regex`, `all_of`, `any_of`, `one_of`, `not`,
and `$null_or::`. The module README's roadmap lists what is missing.

A length is a non-negative integer or a `range::[lower, upper]` of integers.
`valid_values` takes a list of values and ranges, or one range. A range there
is of numbers or of timestamps. Numbers compare by their exact value, whatever
their Ion type, so `1`, `1.0`, and `1e0` are all in `range::[1, 1]`.
Timestamps compare by the instant they name. In any range, a bound can be
`exclusive::`, and `min` or `max` leaves that end open.

`regex` takes the ISL 2.0 subset of ECMA 262 regular expressions, and a
string or symbol is valid when the expression matches any part of it. `\d`,
`\s`, and `\w` are the ASCII classes `[0-9]`, `[ \f\n\r\t]`, and
`[A-Za-z0-9_]`. The flag `i::` ignores case for ASCII letters only, and `m::`
makes `^` and `$` match at line breaks. A construct outside the subset, such
as a backreference or a lazy quantifier, is an error. Matching runs a Pike VM,
which takes time linear in the input, so no expression makes it backtrack
without end. `Regex` is public, so the same expressions can be used on their
own.

Types follow ISL 2.0. A core type such as `int` or `struct` matches only the
non-null values of its Ion type, and `$int` or `$struct` also matches its
typed null. `text`, `lob`, `number`, and `any` cover several Ion types, and
`$text`, `$lob`, `$number`, and `$any` add their nulls. `$null` matches
`null.null`, `nothing` matches no value, and `$null_or::T` matches `null.null`
or a value of `T`. `type` takes a type name or an inline type; a list of core
types is also accepted, which ISL 2.0 does not allow. `element` constrains the
elements of a list or S-expression, or the field values of a struct.
`valid_values` compares a value without its annotations. A schema with the
`$ion_schema_1_0` version marker raises `Unsupported`, since ISL 1.0 gives
these names other meanings.

The loader does not reject every schema that ISL 2.0 does not allow: it does
not check, for example, that a referenced type exists or that type names are
unique.

## Schema documents

A schema document has the version marker `$ion_schema_2_0`, an optional
`schema_header::{...}`, the `type::{...}` definitions, and an optional
`schema_footer::{...}`, after which nothing counts. Other top-level values are
open content, which the loader ignores, unless they are annotated with a
reserved symbol: `$ion_schema`, a symbol that starts with `$ion_schema_`, or a
symbol in lower snake case. The header, the footer, and each type may have
fields whose names are not reserved. The header's `user_reserved_fields`
declares reserved symbols, other than ISL keywords, as more such fields.
Header `imports` raise `Unsupported`. A document with no version marker is ISL
1.0 by the specification; this loader reads it as ISL 2.0, so that a document
of type definitions alone loads.

## Validating values

`Schema::load_from_text` reads the `type::{...}` definitions of a schema
document. `is_valid` answers yes or no, and `validate` lists each violation
with the path to the value that broke it.

```mbt check
///|
test "validate records against a type" {
  let definition =
    #|type::{
    #|  name: person,
    #|  type: struct,
    #|  fields: {
    #|    name: { type: string, occurs: required, codepoint_length: range::[1, 40] },
    #|    role: { valid_values: [admin, member, guest] },
    #|    tags: { type: list, element: symbol },
    #|  },
    #|}
  let schema = @schema.Schema::load_from_text(definition)
  assert_true(
    schema.is_valid("person", @text.read_ion("{ name: \"Ada\", role: admin }")),
  )
  let violations = schema.validate(
    "person",
    @text.read_ion("{ role: owner, tags: [a, \"b\"] }"),
  )
  let report = violations
    .map(violation => violation.path() + ": " + violation.message())
    .join("\n")
  inspect(
    report,
    content=(
      #|$.name: field occurs 0 time(s)
      #|$.role: value is not one of the allowed values
      #|$.tags[1]: expected one of [symbol] but found string
    ),
  )
}
```

## Unsupported constructs

A schema that uses a constraint outside the subset fails to load, so a
validation never passes because a rule was skipped.

```mbt check
///|
test "an unsupported constraint is an error" {
  let message = try
    @schema.Schema::load_from_text(
      "type::{ name: pair, ordered_elements: [int, string] }",
    )
  catch {
    error => error.message()
  } noraise {
    _ => "loaded"
  }
  inspect(
    message,
    content="unsupported Ion Schema constraint: ordered_elements",
  )
}
```
