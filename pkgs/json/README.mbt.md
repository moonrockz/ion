# JSON interoperability (`moonrockz/ion/json`)

Converts between the Ion data model and MoonBit's core `Json`, in both
directions. JSON is a strict subset of Ion, so the two directions are not
inverses: JSON to Ion keeps everything, and Ion to JSON drops what JSON cannot
say.

| Direction | Values | Text |
| --- | --- | --- |
| JSON to Ion | `Ion(json)` | `read_json` |
| Ion to JSON | `to_json` | `write_json` |

## JSON to Ion

`Ion(json)` follows the Ion cookbook's
[JSON-to-Ion rules](https://amazon-ion.github.io/ion-docs/guides/cookbook.html#migrating-json-data-to-ion).
A number becomes an Ion `int`, `decimal`, or `float` by its spelling, and a
large integer keeps every digit.

`@json.Ion` and `@json.ToIon` re-export the core data model's constructor and
conversion trait. `@ion.Ion(json)` constructs the same value without importing
this package. The old `@json.to_ion(json)` function remains available with a
deprecation warning.

```mbt check
///|
test "construct Ion from JSON" {
  let value = @json.Ion(Json({ "ready": true }))
  inspect(@text.write_ion(value), content="{ready: true}")
}
```

```mbt check
///|
test "read JSON as Ion" {
  let value = @json.read_json(
    "{\"id\": 12345678901234567890, \"price\": 1.50, \"ratio\": 1e-7, \"tags\": [\"a\", null]}",
  )
  inspect(
    @text.write_ion(value),
    content=(
      #|{id: 12345678901234567890, price: 1.5, ratio: 1e-7, tags: ["a", null]}
    ),
  )
}
```

## Ion to JSON

`to_json` follows the cookbook's
[down-conversion](https://amazon-ion.github.io/ion-docs/guides/cookbook.html#down-converting-to-json):
typed nulls become `null`, timestamps and symbols become strings, a blob
becomes Base64, s-expressions become arrays, and annotations are dropped.
`write_json` takes an `indent` for multi-line output.

```mbt check
///|
test "write Ion as JSON" {
  let value = @text.read_ion(
    "order::{ id: 7, placed: 2024-05-01T10:00Z, status: shipped, items: (a b), data: {{ aGk= }}, note: null.string }",
  )
  inspect(
    @json.write_json(value),
    content=(
      #|{"id":7,"placed":"2024-05-01T10:00Z","status":"shipped","items":["a","b"],"data":"aGk=","note":null}
    ),
  )
  inspect(
    @json.write_json(@text.read_ion("{ a: [1, 2] }"), indent=2),
    content=(
      #|{
      #|  "a": [
      #|    1,
      #|    2
      #|  ]
      #|}
    ),
  )
}
```

A value JSON cannot represent raises `@ion.IonError::Unsupported` rather than
inventing one:

```mbt check
///|
test "a symbol with unknown text has no JSON form" {
  let message = try @json.to_json(@text.read_ion("$0")) catch {
    error => error.message()
  } noraise {
    _ => "converted"
  }
  inspect(
    message,
    content="a symbol known only by symbol ID 0 has no text to convert to JSON",
  )
}
```

## Optional fuel

`read_json` accepts unrestricted array and object nesting by default.
Pass `fuel=Limited(@core.Budget(128))` to bound simultaneously open
containers. Exhaustion raises `IonError::FuelExhausted`. Scalar tokens
retain core JSON's number and Unicode decoding semantics.
