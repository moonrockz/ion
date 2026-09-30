# Streaming Ion binary (`moonrockz/ion/binary/stream`)

Runs the Ion binary codec over `moonbitlang/async` byte sources and sinks.

- `BinaryReader` pulls one `IonValue` at a time from any `&@io.Reader`. Each
  value is framed by its own descriptor and length and decoded once it has
  fully arrived, so memory stays proportional to the largest value rather
  than to the stream. Version markers and local symbol tables update the
  reader's symbol table and are not returned.
- `BinaryEventReader` pulls the same `@text.IonEvent`s as the text event
  readers. It holds one top-level value's events at a time and decodes a
  container in full before emitting its events. `prefix` and `catalog` work
  as they do on `BinaryReader`.
- `write_all` writes a datagram to any `&@io.Writer`: the version marker, a
  local symbol table when one is needed, and then each value in turn. It
  builds the symbol table from all the values first.
- `BinaryWriter` writes one value at a time without knowing the values
  ahead: it declares each new symbol text once, in a local symbol table that
  appends to the ones before (`imports: $ion_symbol_table`).

```mbt check
///|
struct Sink {
  mut written : Bytes
}

///|
impl @io.Writer for Sink with fn write_once(self, data, offset~, len~) {
  self.written = self.written + data[offset:offset + len].to_owned()
  len
}

///|
async test "write a datagram and read it back one value at a time" {
  let values = @text.read_ion_datagram(
    "{ id: 1, tags: [new] } { id: 2, tags: [] } done",
  )
  let sink : Sink = { written: b"", }
  @stream.write_all(sink, values)
  // The same octets as the sync writer.
  assert_eq(sink.written, @binary.write_binary(values))
  // Deliver the octets in pieces of three, splitting every value.
  let source = @io.MemoryReader(async fn(writer) {
    let mut offset = 0
    while offset < sink.written.length() {
      let end = @cmp.minimum(offset + 3, sink.written.length())
      writer.write(sink.written[offset:end].to_owned())
      offset = end
    }
  })
  let reader = @stream.BinaryReader::new(source)
  let read : Array[String] = []
  while reader.next() is Some(value) {
    read.push(@text.write_ion(value))
  }
  debug_inspect(
    read,
    content=(
      #|["{id: 1, tags: [new]}", "{id: 2, tags: []}", "done"]
    ),
  )
}
```

A stream that ends inside a value raises an `@ion.IonError` at its end.

```mbt check
///|
async test "read binary events from an async source" {
  let bytes = @binary.write_binary(@text.read_ion_datagram("tag::[1]"))
  let source = @io.MemoryReader(async fn(writer) { writer.write(bytes) })
  defer source.close()
  let reader = @stream.BinaryEventReader::new(source)
  let names : Array[String] = []
  while reader.next() is Some(event) {
    names.push(event.to_text())
  }
  debug_inspect(
    names,
    content=(
      #|[
      #|  "DocumentStart",
      #|  "Annotation(tag)",
      #|  "ListStart",
      #|  "Scalar(int)",
      #|  "ListEnd",
      #|  "DocumentEnd",
      #|]
    ),
  )
}
```

`BinaryWriter` suits a stream whose values are not known ahead, such as the
output of `ion print --binary`:

```mbt check
///|
async test "write values one at a time" {
  let sink : Sink = { written: b"", }
  let writer = @stream.BinaryWriter::new(sink)
  for text in ["{ id: 1, tags: [new] }", "{ id: 2, tags: [new, sale] }"] {
    writer.write(@text.read_ion(text))
  }
  inspect(
    @text.write_all(@binary.read_binary(sink.written)),
    content=(
      #|{id: 1, tags: [new]}
      #|{id: 2, tags: [new, sale]}
    ),
  )
}
```
