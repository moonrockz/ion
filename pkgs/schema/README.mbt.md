# Ion Schema (`moonrockz/ion/schema`)

Loads [Ion Schema 2.0](https://amazon-ion.github.io/ion-schema/) type
definitions and validates Ion values against them. It covers a focused subset
of the language; a construct it does not implement raises
`@ion.IonError::Unsupported` when the schema loads, rather than being ignored.

Supported constraints: `type`, `fields` (with `occurs`, `required`, and
`optional`), `element`, `valid_values` (a list of values), `container_length`
and `codepoint_length` (an integer or a `range::[min, max]`), `contains`,
`all_of`, `any_of`, `one_of`, `not`, `nothing`, `$any`, and `$null_or::`. The
module README's roadmap lists what is missing, including `valid_values`
ranges and `exclusive::` range bounds.

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
      "type::{ name: code, type: string, regex: \"^[A-Z]+$\" }",
    )
  catch {
    error => error.message()
  } noraise {
    _ => "loaded"
  }
  inspect(message, content="unsupported Ion Schema constraint: regex")
}
```
