# JSON interoperability (`moonrockz/ion/json`)

Converts between the Ion data model and MoonBit's core `Json`, in both
directions. JSON is a strict subset of Ion, so the two directions are not
inverses: JSON to Ion keeps everything, and Ion to JSON drops what JSON cannot
say.

| Direction | Values | Text |
| --- | --- | --- |
| JSON to Ion | `Ion(json)` | `read_json` |
| Ion to JSON | `to_json` | `write_json` |
| `ToJson` type to Ion | `to_ion_via_json` | |
| Ion to `FromJson` type | `from_ion_via_json` | |

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
    content=(
      #|$: symbol $0 has no known text
    ),
  )
}
```

## Types with core JSON codecs

`to_ion_via_json` and `from_ion_via_json` give any type with core `ToJson`
and `FromJson` its Ion codecs through its JSON form. They are re-exported from
the core package, with `FromIon` and `FromIonError`; see its README for a
derived type and for the decode rules. A failure raises `FromIonError`: a
symbol with no text raises `MissingSymbolText`, and a `FromJson` failure
raises `JsonDecode` with core's message and the path in Ion field names and
list indexes.

```mbt check
///|
test "decode a FromJson type from Ion" {
  let value = @text.read_ion("{a: [1, 2], b: []}")
  let decoded : Map[String, Array[Int32]] = @json.from_ion_via_json(value)
  assert_eq(decoded.to_array(), [("a", [1, 2]), ("b", [])])
  let wrong = @text.read_ion("{a: [1, x]}")
  let message = try
    (@json.from_ion_via_json(wrong) : Map[String, Array[Int32]])
  catch {
    error => error.message()
  } noraise {
    _ => "decoded"
  }
  inspect(message, content="$.a[1]: Int::from_json: expected number")
}
```

## Optional fuel

`read_json` accepts unrestricted array and object nesting by default.
Pass `fuel=Limited(@core.Budget(128))` to bound simultaneously open
containers. Exhaustion raises `IonError::FuelExhausted`. Scalar tokens
retain core JSON's number and Unicode decoding semantics.
