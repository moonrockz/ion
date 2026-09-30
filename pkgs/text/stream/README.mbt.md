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

## Writing containers incrementally

`IncrementalWriter` writes each scalar and delimiter immediately. You can
build a large container without retaining its `IonValue` tree. The writer
keeps the nesting stack, pending metadata, and symbol context; transient
memory also includes the current scalar. A sink that collects bytes retains
its own output.

```mbt check
///|
async test "write a container without a tree" {
  let sink : Collected = { written: b"", }
  let writer = @stream.IncrementalWriter::new(sink)
  writer.step_in(Struct)
  writer.set_field_name(@ion.SymbolToken::new("items"))
  writer.set_annotations([@ion.SymbolToken::new("tag")])
  writer.step_in(List)
  for item in 0..<3 {
    writer.write_int(item)
  }
  writer.step_out()
  writer.step_out()
  writer.finish()
  assert_eq(@utf8.decode(sink.written), "{items: tag::[0, 1, 2]}")
}
```

`step_in` accepts `List`, `Sexp`, and `Struct`. Set a field name before each
struct value. Annotations apply to the next scalar or container; `write(value)`
adds them before that value's existing annotations. `write` accepts any Ion
scalar, including decimals, timestamps, blobs, and typed nulls, or a finished
subtree. Convenience methods write integers, strings, booleans, and nulls.
`pretty=true` produces the batch writer's indentation.

Supply `symbols` before writing unknown local IDs or imports, for example
`@ion.SymbolTable::for_values([value])`. The writer emits that context before
its first value. Keep the context exclusive to the writer after construction.
Context placement can differ from batch output across multiple top-level
values, while preserving Ion equivalence.

`finish` checks that containers are closed and metadata is consumed. Sequence
errors before output leave the writer usable after correction. Output failure
or cancellation makes it unusable because bytes may have reached the sink.
Calls on the same writer must be sequential. The caller owns sink flushing.
