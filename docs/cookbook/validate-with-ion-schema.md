# Validate data with Ion Schema

Parsing proves that input is Ion. Use a schema to check the record shape
your application expects.

## Define a record type

The supplied [person.isl](examples/person.isl) defines a non-null struct:

```ion
$ion_schema_2_0
type::{
  name: person,
  type: struct,
  fields: closed::{
    name: {type: string, occurs: required},
    born: {type: int},
  },
}
```

`name` must occur once. `born` may occur zero or one times. `closed::`
rejects every field not listed here. Plain `string` and `int` reject nulls
in ISL 2.0. Those choices make both missing fields and unexpected fields
visible to the caller. See the
[ISL 2.0 fields constraint](https://amazon-ion.github.io/ion-schema/docs/isl-2-0/spec.html#fields).

Always include the schema version marker. This library treats a schema
without one as ISL 1.0, whose null and closed-content rules differ.

## Validate with the CLI

Save the schema above as `person.isl`. The same document is
[person.isl](examples/person.isl). `validate` reads the schema from that
path. The values to check can be a pipe; omitting the input file reads
stdin. [people.ion](examples/people.ion) is the same two records in a file.

`moonx moonrockz/ion` runs the published module. `ion` is the release
binary. The rest of this page uses `moonx`; drop that prefix when `ion` is
on your `PATH`. In PowerShell, commas between single-quoted strings put one
value on each line.

POSIX shell:

```sh
printf '%s\n' '{name: "Ada", born: 1815}' '{name: "Grace", born: 1906}' |
  moonx moonrockz/ion validate person.isl person
```

```sh
printf '%s\n' '{name: "Ada", born: 1815}' '{name: "Grace", born: 1906}' |
  ion validate person.isl person
```

PowerShell:

```powershell
'{name: "Ada", born: 1815}', '{name: "Grace", born: 1906}' |
  moonx moonrockz/ion validate person.isl person
```

```powershell
'{name: "Ada", born: 1815}', '{name: "Grace", born: 1906}' |
  ion validate person.isl person
```

Valid data produces no output and exits with status 0. Try a bad record:

```sh
printf '%s\n' '{name: 42}' |
  moonx moonrockz/ion validate person.isl person
```

```powershell
'{name: 42}' | moonx moonrockz/ion validate person.isl person
```

The command reports on stderr and exits with status 1:

```text
value 0: $.name: expected one of [string] but found int
1 of 1 value(s) failed validation
```

Value indexes start at zero. Status 1 also covers parsing and I/O errors;
status 2 means invalid command arguments. Check the diagnostic as well as
the exit status when displaying an error to a user.

## Validate with the library

Add these imports:

```moonbit
import {
  "moonrockz/ion/text" @text,
  "moonrockz/ion/schema" @schema,
}
```

Load the schema once, then reuse it:

```moonbit
test "report a field that violates a schema" {
  let definition =
    #|$ion_schema_2_0
    #|type::{
    #|  name: person,
    #|  type: struct,
    #|  fields: closed::{
    #|    name: {type: string, occurs: required},
    #|    born: {type: int},
    #|  },
    #|}
  let schema = @schema.Schema::load_from_text(definition)
  let value = @text.read_ion("{name: \"Ada\", born: 1815}")
  assert_true(schema.is_valid("person", value))
  let violations = schema.validate("person", @text.read_ion("{name: 42}"))
  assert_eq(violations.length(), 1)
  assert_eq(violations[0].path(), "$.name")
  assert_eq(violations[0].message(), "expected one of [string] but found int")
}
```

`validate` returns an empty array when the value is valid. Each violation
has a `path()` and `message()`. `is_valid` returns only a boolean. Schema
loading and Ion parsing can raise `IonError`; handle those failures
separately from a valid Ion value that fails the schema. If the type name
comes from a caller, check `schema.find(name)` before validation.

The CLI validates individual values. To constrain the complete datagram,
define a type with `type: document` and use `validate_document` or
`is_valid_document` in the library. This lets you enforce constraints such
as the number and order of top-level values.

## Share types between schemas

The CLI loads imports relative to the schema file's directory. Set
`--schema-root <dir>` to choose another base directory. In the library,
pass a `resolver` to `Schema::load_from_text`; it maps a schema ID to its
parsed Ion values. An import without a resolver raises `Unsupported`.
See the [schema package guide](../../pkgs/schema/README.mbt.md#imports)
for a complete resolver example.

Next, use the same constraints to
[model algebraic data types](algebraic-data-types.md).
