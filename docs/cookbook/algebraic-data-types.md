# Model algebraic data types with Ion Schema

You want to store domain data whose shape depends on the variant, and
reject combinations such as a circle with a rectangle's width.

An algebraic data type combines products and sums. A product holds all
of its components, as a record does. A sum selects one variant and that
variant's payload. In Ion, use structs for products, an explicit tag for
the selected variant, and Ion Schema to validate the allowed combinations.

This recipe uses ISL 2.0. The complete runnable schema is
[algebraic-types.isl](examples/algebraic-types.isl). It includes every type
below, so you can run the examples without assembling the fragments.

## Define a product with a struct

A point has two decimal coordinates:

```ion
$ion_schema_2_0
type::{
  name: point,
  type: struct,
  fields: closed::{
    x: {type: decimal, occurs: required},
    y: {type: decimal, occurs: required},
    label: {type: $null_or::string},
  },
}
```

These are valid points:

```ion
{x: 0.0, y: 1.0}
{x: 0.0, y: 1.0, label: "start"}
{x: 0.0, y: 1.0, label: null}
```

`occurs: required` requires exactly one occurrence of each coordinate.
Ion structs allow repeated field names, so occurrence counts matter even
when your language's record type has only one slot per field. `closed::`
rejects extra fields such as `z`.

| Input | Why it fails |
| --- | --- |
| `{x: 0.0}` | Missing `y` |
| `{x: 0.0, x: 1.0, y: 2.0}` | Repeated `x` |
| `{x: 0, y: 1.0}` | `x` is an integer, not a decimal |
| `{x: 0.0, y: 1.0, z: 2.0}` | Unknown field |
| `null.struct` | `struct` requires a non-null value |

### Distinguish optional fields from null values

`label` has no `occurs`, so it may be absent or occur once. Its
`$null_or::string` type permits either a string or untyped `null` when
present. It rejects `null.string`.

These are separate choices:

| Field definition | Allowed states |
| --- | --- |
| `{type: string}` | Absent, or a non-null string |
| `{type: string, occurs: required}` | One non-null string |
| `{type: $null_or::string}` | Absent, a string, or untyped `null` |
| `{type: $string, occurs: required}` | One string or `null.string` |

Choose which states your domain needs. A missing label and an explicitly
null label remain distinguishable in the Ion record.

## Define a sum with disjoint tags

Suppose the domain has `Circle(center, radius)` and
`Rectangle(width, height)`. Give each variant its own closed record type:

```ion
type::{
  name: positive_decimal,
  type: decimal,
  valid_values: range::[exclusive::0., max],
}

type::{
  name: circle,
  type: struct,
  fields: closed::{
    kind: {type: symbol, valid_values: [circle], occurs: required},
    center: {type: point, occurs: required},
    radius: {type: positive_decimal, occurs: required},
  },
}

type::{
  name: rectangle,
  type: struct,
  fields: closed::{
    kind: {type: symbol, valid_values: [rectangle], occurs: required},
    width: {type: positive_decimal, occurs: required},
    height: {type: positive_decimal, occurs: required},
  },
}

type::{name: shape, one_of: [circle, rectangle]}
```

The variants require different symbol tags, so a value cannot match both.
`one_of` requires exactly one match. `any_of` requires at least one match
and also accepts overlapping branches. Use `one_of` here to express an
unambiguous variant choice. These constraints follow the
[ISL 2.0 specification](https://amazon-ion.github.io/ion-schema/docs/isl-2-0/spec.html#one_of).

The [shapes.ion](examples/shapes.ion) file contains:

```ion
{kind: circle, center: {x: 0.0, y: 0.0}, radius: 2.5}
{kind: rectangle, width: 3.0, height: 4.0}
```

Validate it from the repository root:

```sh
moon run pkgs -- validate docs/cookbook/examples/algebraic-types.isl shape docs/cookbook/examples/shapes.ion
```

The command exits with status 0. Now run the deliberate failures:

```sh
moon run pkgs -- validate docs/cookbook/examples/algebraic-types.isl shape docs/cookbook/examples/invalid-shapes.ion
```

It exits with status 1. That file tests an unknown tag, missing radius,
mixed payloads, a string tag, an integer dimension, a zero dimension, and
a duplicate tag. A `one_of` failure may report the overall branch mismatch;
validate against `circle` or `rectangle` directly when you want diagnostics
for a known variant's fields.

## Use symbols for payload-free variants

An enumeration needs no record wrapper:

```ion
type::{name: color, type: symbol, valid_values: [red, green, blue]}
```

`red` passes. `"red"`, `purple`, and `null.symbol` fail. This type places
no restriction on annotations, so `paint::red` also passes. Add
`annotations: closed::[]` if the domain requires unannotated values.

## Use annotations when the tag belongs on the payload

An annotation can identify a variant without wrapping its payload in a
struct. For `Option[Int]`, choose `none` or `some::42`:

```ion
type::{
  name: none_int,
  type: symbol,
  valid_values: [none],
  annotations: closed::[],
}

type::{
  name: some_int,
  type: int,
  annotations: {ordered_elements: [{valid_values: [some], occurs: required}]},
}

type::{name: option_int, one_of: [none_int, some_int]}
```

`none`, `some::42`, and `some::0` pass. Plain `42`, `some::null.int`,
`some::"42"`, `some::some::42`, and `other::some::42` fail.
The `ordered_elements` constraint requires exactly one annotation, `some`.
The bare `none` branch rejects all annotations. An annotation by itself
does not check anything; these schema constraints make the tag meaningful.

This representation retains the difference between absence and a real
zero. A field tag is easier to carry through JSON because JSON export
drops annotations. Exporting `some::42` yields only `42`. See
[JSON conversion](convert-json.md) before choosing annotation tags for
data that crosses a JSON boundary.

## Recurse through child values

For a tree with integer leaves and branches containing child trees:

```ion
type::{
  name: leaf,
  type: struct,
  fields: closed::{
    kind: {type: symbol, valid_values: [leaf], occurs: required},
    value: {type: int, occurs: required},
  },
}

type::{
  name: branch,
  type: struct,
  fields: closed::{
    kind: {type: symbol, valid_values: [branch], occurs: required},
    children: {type: list, element: tree, occurs: required},
  },
}

type::{name: tree, one_of: [leaf, branch]}
```

The branch references `tree` through its list elements. An empty branch
is valid; add `container_length: range::[1, max]` to the `children` field
if your domain requires at least one child.

```sh
moon run pkgs -- validate docs/cookbook/examples/algebraic-types.isl tree docs/cookbook/examples/trees.ion
```

Every child must be a valid tree. A nested leaf with `value: "1"` fails.
Recursion must descend into child values. A definition such as
`type::{name: loop, type: loop}` never consumes a child and this library
reports a cyclic schema type reference during validation. Ion values are
trees; graph references need a separate application-level ID representation.

## Validate at the library boundary

In a checkout, read the supplied schema using the repository's filesystem
dependency. In your own module, add `moonbitlang/x` if you use the same
file-loading approach. Add these imports:

```moonbit
import {
  "moonbitlang/x/fs" @fs,
  "moonrockz/ion/text" @text,
  "moonrockz/ion/schema" @schema,
}
```

```moonbit
test "validate a shape before decoding the domain value" {
  let schema = @schema.Schema::load_from_text(
    @fs.read_file_to_string("docs/cookbook/examples/algebraic-types.isl"),
  )
  let value = @text.read_ion(
    "{kind: circle, center: {x: 0.0, y: 0.0}, radius: 2.5}",
  )
  assert_true(schema.is_valid("shape", value))
  assert_true(!schema.is_valid("shape", @text.read_ion("{kind: circle}")))
}
```

In an application, load once and use `schema.validate("shape", value)`
to retain diagnostics. Decode accepted records into a MoonBit enum, then
use exhaustive matching on that enum. The schema checks serialized values
at runtime; it does not generate MoonBit types or prevent a caller from
constructing an invalid `IonValue`. Keep the application's ADT and its
decoder responsible for the domain's in-memory invariants.

The [schema package guide](../../pkgs/schema/README.mbt.md) documents
constraint semantics and recursion behavior. The recipe's accepted and
rejected examples are checked in
[user_cookbook_test.mbt](../../pkgs/schema/user_cookbook_test.mbt).
