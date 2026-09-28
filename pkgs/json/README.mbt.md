# JSON interoperability (`moonrockz/ion/json`)

Converts between the Ion data model and MoonBit's core `Json`, in both
directions. JSON is a strict subset of Ion, so the two directions are not
inverses: JSON to Ion keeps everything, and Ion to JSON drops what JSON cannot
say.

| Direction | Values | Text |
| --- | --- | --- |
| JSON to Ion | `to_ion` | `read_json` |
| Ion to JSON | `to_json` | `write_json` |

## JSON to Ion

`to_ion` follows the Ion cookbook's
[JSON-to-Ion rules](https://amazon-ion.github.io/ion-docs/guides/cookbook.html#migrating-json-data-to-ion).
A number becomes an Ion `int`, `decimal`, or `float` by its spelling, and a
large integer keeps every digit.

```mbt check
///|
test "read JSON as Ion" {
  let value = @json.read_json(
    "{\"id\": 12345678901234567890, \"price\": 1.50, \"ratio\": 1e-7, \"tags\": [\"a\", null]}",
  )
  inspect(
    @text.write_ion(value),
    content=(
      #|{id: 12345678901234567890, price: 15d-1, ratio: 1e-7, tags: ["a", null]}
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
