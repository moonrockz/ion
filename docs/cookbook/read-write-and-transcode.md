# Read, write, and transcode Ion

You have an Ion file and want readable output or a binary representation
that retains its values.

## Use the CLI

This datagram is an annotated record followed by an integer. The same text
is in [orders.ion](examples/orders.ion).

```ion
order::{id: 7, total: 19.990, placed: 2024-05-01T10:00Z, note: null.string}
42
```

Print it with indentation. `moonx moonrockz/ion` runs the published module.
`ion` is the release binary. The rest of this page uses `moonx`; drop that
prefix when `ion` is on your `PATH`. POSIX shells and PowerShell are both
shown. In PowerShell, several single-quoted strings separated by commas
become one value per line.

POSIX shell:

```sh
printf '%s\n' \
  'order::{id: 7, total: 19.990, placed: 2024-05-01T10:00Z, note: null.string}' \
  '42' |
  moonx moonrockz/ion print --pretty
```

```sh
printf '%s\n' \
  'order::{id: 7, total: 19.990, placed: 2024-05-01T10:00Z, note: null.string}' \
  '42' |
  ion print --pretty
```

PowerShell:

```powershell
'order::{id: 7, total: 19.990, placed: 2024-05-01T10:00Z, note: null.string}', '42' |
  moonx moonrockz/ion print --pretty
```

```powershell
'order::{id: 7, total: 19.990, placed: 2024-05-01T10:00Z, note: null.string}', '42' |
  ion print --pretty
```

Omitting the input file reads stdin. Pass a path, such as `orders.ion`,
when the input is a file. `-` names stdin explicitly.

Write binary and read it back. The CLI detects binary input by its version
marker. A POSIX pipe passes those bytes through unchanged:

```sh
printf '%s\n' \
  'order::{id: 7, total: 19.990, placed: 2024-05-01T10:00Z, note: null.string}' \
  '42' |
  moonx moonrockz/ion print --binary |
  moonx moonrockz/ion print
```

PowerShell rewrites bytes when it redirects a native command, so write the
binary file with `cmd /c`, then read that file:

```powershell
'order::{id: 7, total: 19.990, placed: 2024-05-01T10:00Z, note: null.string}', '42' |
  Set-Content -Encoding utf8 orders.ion
cmd /c "moonx moonrockz/ion print --binary orders.ion > orders.10n"
moonx moonrockz/ion print orders.10n
```

The output still has two top-level values, with the record's annotation,
decimal scale, timestamp, and typed null intact. Comments and source
formatting do not survive this conversion.

## Use the library

Add these imports:

```moonbit
import {
  "moonrockz/ion/text" @text,
  "moonrockz/ion/binary" @binary,
}
```

Read a datagram into an array, encode it, and compare the decoded values:

```moonbit
test "transcoding retains Ion values" {
  let input =
    #|order::{id: 7, total: 19.990, placed: 2024-05-01T10:00Z, note: null.string}
    #|42
  let values = @text.read_ion_datagram(input)
  let bytes = @binary.write_binary(values)
  let decoded = @binary.read_binary(bytes)
  assert_eq(decoded.length(), 2)
  for index, value in values {
    assert_true(decoded[index].equals(value))
  }
  let rewritten = @text.write_all(decoded)
  let reread = @text.read_ion_datagram(rewritten)
  assert_true(reread[0].equals(values[0]))
  assert_true(reread[1].equals(values[1]))
}
```

Use `read_ion` for exactly one value and `read_ion_datagram` for a whole
sequence. `write_ion` renders one value; `write_all` renders a datagram.
`write_all_pretty` adds indentation. These operations raise `IonError`
for invalid input or a value the writer cannot encode. Catch that error
at your application's input boundary, or propagate it from a raising function.

## Choose how much to hold in memory

The synchronous datagram APIs above build an array containing all values.
For large files, use `TextReader` or `BinaryReader` from the async stream
packages. Their `next()` methods yield `Some(value)` until the input ends,
when they return `None`.

The CLI's `print`, `json`, `hash`, and `validate` commands process values
this way. Memory is proportional to the largest top-level value. One huge
list is still one value. For container events and incremental output, see
the [text streaming](../../pkgs/text/stream/README.mbt.md) and
[binary streaming](../../pkgs/binary/stream/README.mbt.md) guides.

See also the [text](../../pkgs/text/README.mbt.md) and
[binary](../../pkgs/binary/README.mbt.md) package guides for symbol catalogs
and event readers.
