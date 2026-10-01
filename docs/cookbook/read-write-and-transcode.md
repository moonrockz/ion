# Read, write, and transcode Ion

You have an Ion file and want readable output or a binary representation
that retains its values.

## Use the CLI

The supplied [orders.ion](examples/orders.ion) contains an annotated record
and a second top-level integer. Print it with indentation:

```sh
moon run pkgs -- print --pretty docs/cookbook/examples/orders.ion
```

Write binary to a scratch file and read it back:

```sh
mkdir -p .dev/out
moon run pkgs -- print --binary docs/cookbook/examples/orders.ion > .dev/out/orders.10n
moon run pkgs -- print .dev/out/orders.10n
```

The CLI detects binary input by its version marker. The output still has
two top-level values, with the record's annotation, decimal scale,
timestamp, and typed null intact. Comments and source formatting do not
survive this conversion.

Omit the input filename or use `-` to read stdin. This pipeline prints the
binary result as text without a temporary file:

```sh
moon run pkgs -- print --binary docs/cookbook/examples/orders.ion |
  moon run pkgs -- print -
```

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
