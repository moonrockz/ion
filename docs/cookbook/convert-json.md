# Convert between Ion and JSON

Use JSON conversion to exchange data with a consumer that accepts JSON.
Keep an Ion copy when you need annotations, symbols, typed nulls, or exact
decimal scale later.

## Use the CLI

Import one JSON document from stdin. `moonx moonrockz/ion` runs the
published module. `ion` is the release binary. The rest of this page uses
`moonx`; drop that prefix when `ion` is on your `PATH`.

POSIX shell:

```sh
printf '%s\n' '{"id":7,"status":"shipped","note":null}' |
  moonx moonrockz/ion fromjson
```

```sh
printf '%s\n' '{"id":7,"status":"shipped","note":null}' |
  ion fromjson
```

PowerShell:

```powershell
'{"id":7,"status":"shipped","note":null}' | moonx moonrockz/ion fromjson
```

```powershell
'{"id":7,"status":"shipped","note":null}' | ion fromjson
```

The output is:

```ion
{id: 7, status: "shipped", note: null}
```

Export two Ion records. The same values are in
[people.ion](examples/people.ion):

```sh
printf '%s\n' '{name: "Ada", born: 1815}' '{name: "Grace", born: 1906}' |
  moonx moonrockz/ion json
```

```powershell
'{name: "Ada", born: 1815}', '{name: "Grace", born: 1906}' |
  moonx moonrockz/ion json
```

This writes a JSON value on each line:

```json
{"name":"Ada","born":1815}
{"name":"Grace","born":1906}
```

That output is a sequence of JSON documents. `fromjson` accepts one JSON
document, so use an Ion list and export it as a JSON array when a receiver
needs the entire collection in one document.

## Use the library

Add these imports:

```moonbit
import {
  "moonrockz/ion/text" @text,
  "moonrockz/ion/json" @json,
}
```

This round trip deliberately shows what changes:

```moonbit
test "JSON export changes Ion-specific values" {
  let value = @text.read_ion(
    "order::{id: 7, status: shipped, note: null.string}",
  )
  let output = @json.write_json(value)
  assert_eq(output, "{\"id\":7,\"status\":\"shipped\",\"note\":null}")
  let imported = @json.read_json(output)
  assert_true(!imported.equals(value))
  assert_eq(
    @text.write_ion(imported),
    "{id: 7, status: \"shipped\", note: null}",
  )
}
```

`read_json` and `write_json` operate on text. `to_ion` and `to_json` convert
between `IonValue` and MoonBit's core `Json` without an intermediate string.

## Decide whether the conversion fits your data

| Ion content | JSON export |
| --- | --- |
| Annotations | Dropped |
| Symbol or timestamp | String |
| Any typed null | `null` |
| Decimal or integer | JSON number with retained numeric precision on export |
| `nan`, `+inf`, `-inf` | `null` |
| S-expression | Array |
| Blob | Base64 string |
| Clob | Latin-1 string |

A JSON consumer may round large numbers even if the emitted text is exact.
On import, this library classifies a number as an Ion integer, decimal, or
float using the representation retained by MoonBit's JSON parser. Decimal
trailing zeros need not survive: JSON `1.50` can become Ion `1.5`.
Structs with repeated field names also need an application policy before
export, because JSON consumers disagree about duplicate object keys.

A symbol known only by its ID has no text to export and raises
`IonError::Unsupported`. Supply a shared symbol catalog when reading data
that requires one. See the [JSON package guide](../../pkgs/json/README.mbt.md)
for the conversion rules and checked edge cases.
