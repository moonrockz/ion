# Ion Schema (`moonrockz/ion/schema`)

Loads [Ion Schema 2.0](https://amazon-ion.github.io/ion-schema/) schemas and
validates Ion values and documents against their types. It implements every
ISL 2.0 constraint and schema imports. ISL 1.0 is not implemented: a schema
with the `$ion_schema_1_0` version marker raises
`@ion.IonError::Unsupported`, since ISL 1.0 gives the same names other
meanings.

Constraints: `type`, `all_of`, `any_of`, `one_of`, `not`, `valid_values`,
`element` (with `distinct::`), `ordered_elements`, `contains`, `fields` (with
`occurs` and `closed::`), `field_names` (with `distinct::`), `annotations`
(standard, and simplified with `required::` and `closed::`),
`container_length`, `codepoint_length`, `byte_length`, `utf8_byte_length`,
`precision`, `exponent`, `regex`, `timestamp_precision`, `timestamp_offset`,
and `ieee754_float`.

A length is a non-negative integer or a `range::[lower, upper]` of integers,
and so are `precision` (at least 1) and `exponent` (any integer).
`timestamp_precision` takes the precision names, from `year` to
`nanosecond`.
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
`valid_values` compares a value without its annotations. `ordered_elements`
matches the elements in order, each type as many times as its `occurs`
allows; an ambiguous match is found without backtracking. `annotations`
validates the value's annotations as a list of symbols.

A document is a stream of top-level values. `validate_document` and
`is_valid_document` check one: `element`, `ordered_elements`,
`container_length`, and `contains` apply to its values, and the built-in type
`document` matches it. No other constraint applies to a document.

The loader does not reject every schema that ISL 2.0 does not allow
([#33](https://github.com/moonrockz/ion/issues/33)): it accepts `occurs`
outside `fields`, a `name` in an inline type, and an empty `fields` struct, or
one that names a field twice.

## Schema documents

A schema document has the version marker `$ion_schema_2_0`, an optional
`schema_header::{...}`, the `type::{...}` definitions, and an optional
`schema_footer::{...}`, after which nothing counts. Other top-level values are
open content, which the loader ignores, unless they are annotated with a
reserved symbol: `$ion_schema`, a symbol that starts with `$ion_schema_`, or a
symbol in lower snake case. The header, the footer, and each type may have
fields whose names are not reserved. The header's `user_reserved_fields`
declares reserved symbols, other than ISL keywords, as more such fields.
A document with no version marker is ISL 1.0 by the specification; this
loader reads it as ISL 2.0, so that a document of type definitions alone
loads.

A type reference must name a type that the schema defines or imports.
Imports name other schemas by an `id`, which the `resolver` given to
`Schema::load` turns into that schema's values, for example by reading a file
under a base directory. A header import brings in all the types of a schema,
or one type, optionally under another name with `as`; an inline import
`{ id: ..., type: ... }` refers to one type without adding it to the scope.
Types that an imported schema imports in turn are not in scope. Schemas may
import each other in a cycle, but not themselves. Without a resolver, an
import raises `Unsupported`. `types()` lists an imported type as
`<id>#<name>`.

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

## Imports

```mbt check
///|
test "import a type from another schema" {
  let schemas : Map[String, String] = {
    "common.isl": "$ion_schema_2_0 type::{ name: positive_int, type: int, valid_values: range::[1, max] }",
  }
  let resolver = (id : String) => {
    match schemas.get(id) {
      Some(text) => @text.read_ion_datagram(text)
      None => raise @ion.IonError::DataModel("no schema named " + id)
    }
  }
  let schema = @schema.Schema::load_from_text(
    (
      #|$ion_schema_2_0
      #|schema_header::{ imports: [{ id: "common.isl", type: positive_int, as: count }] }
      #|type::{ name: tally, fields: { votes: count } }
    ),
    resolver~,
  )
  assert_true(schema.is_valid("tally", @text.read_ion("{ votes: 3 }")))
  assert_true(!schema.is_valid("tally", @text.read_ion("{ votes: 0 }")))
  // Without a resolver, the import cannot load.
  let message = try
    @schema.Schema::load_from_text(
      "schema_header::{ imports: [{ id: \"common.isl\" }] }",
    )
  catch {
    error => error.message()
  } noraise {
    _ => "loaded"
  }
  inspect(
    message,
    content="the schema imports 'common.isl', but no resolver was given to load it",
  )
}
```
