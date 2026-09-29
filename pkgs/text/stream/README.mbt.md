# Streaming Ion text (`moonrockz/ion/text/stream`)

Reads and writes Ion text over `moonbitlang/async` byte sources and sinks, one
top-level value at a time, so memory stays proportional to the largest value
rather than to the stream.

- `TextReader` pulls `IonValue`s from any `&@io.Reader`, decoding the text as
  it arrives, including characters split across reads. Its first octets show
  the encoding: UTF-8, UTF-16, or UTF-32, with or without a byte order mark
  (see `@text.detect_encoding`).
- `TextEventReader` pulls the `@text.IonEvent` stream instead.
- `TextWriter` and `write_all` encode values as UTF-8 text to any
  `&@io.Writer`.

The reader yields the values `@text.read_ion_datagram` returns for the whole
text, applying version markers and local symbol tables as they arrive. It
reads each code unit once to track containers, strings, comments, and lobs,
and parses only when the text is back at the top level between values, so a
large value costs time linear in its length.

## Reading

`next` returns `None` at the end of the stream. The examples feed the readers
from an in-memory pipe; a file, a socket, or stdin works the same way.

```mbt check
///|
async test "read values one at a time" {
  let source = @io.MemoryReader(async fn(writer) {
    // One octet at a time, which splits every value and the two octets of `ü`.
    let text = @utf8.encode("{ city: \"Zürich\" } [1, 2] 'last'")
    for index in 0..<text.length() {
      writer.write(text[index:index + 1].to_owned())
    }
  })
  let reader = @stream.TextReader::new(source)
  let read : Array[String] = []
  while reader.next() is Some(value) {
    read.push(@text.write_ion(value))
  }
  debug_inspect(
    read,
    content=(
      #|["{city: \"Zürich\"}", "[1, 2]", "last"]
    ),
  )
}

///|
async test "read events" {
  let source = @io.MemoryReader(async fn(writer) {
    writer.write(@utf8.encode("a::1 [2]"))
  })
  let reader = @stream.TextEventReader::new(source)
  let events : Array[String] = []
  while reader.next() is Some(event) {
    events.push(event.to_text())
  }
  debug_inspect(
    events,
    content=(
      #|[
      #|  "DocumentStart",
      #|  "Annotation(a)",
      #|  "Scalar(int)",
      #|  "ListStart",
      #|  "Scalar(int)",
      #|  "ListEnd",
      #|  "DocumentEnd",
      #|]
    ),
  )
}
```

A value that closes with `]`, `)`, `}`, or `"` is settled as soon as it
arrives. A number or a symbol could still continue, so it is settled when the
text after it shows where it ends, or at the end of the stream. A malformed
value is reported only at the end of the stream, since until then it may
just be cut short.

## Writing

The octets are the UTF-8 encoding of `@text.write_all`, or of
`@text.write_all_pretty` with `pretty=true`. A buffered sink is flushed by its
owner.

```mbt check
///|
struct Collected {
  mut written : Bytes
}

///|
impl @io.Writer for Collected with fn write_once(self, data, offset~, len~) {
  self.written = self.written + data[offset:offset + len].to_owned()
  len
}

///|
async test "write values one at a time" {
  let sink : Collected = { written: b"", }
  let writer = @stream.TextWriter::new(sink)
  writer.write(@text.read_ion("{ id: 1 }"))
  writer.write(@text.read_ion("{ id: 2 }"))
  inspect(
    @utf8.decode(sink.written),
    content=(
      #|{id: 1}
      #|{id: 2}
    ),
  )
}
```
