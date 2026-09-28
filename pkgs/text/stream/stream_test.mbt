// Black-box tests for the streaming Ion text readers.
//
// Text travels through an in-memory async pipe, so the streaming path is
// exercised end to end without touching the file system.

///|
/// An in-memory async reader over `bytes`, delivered in chunks of `chunk`.
fn reader_of(bytes : Bytes, chunk? : Int = 4096) -> @io.MemoryReader {
  @io.MemoryReader(async fn(writer) {
    let mut offset = 0
    while offset < bytes.length() {
      let end = if offset + chunk < bytes.length() {
        offset + chunk
      } else {
        bytes.length()
      }
      writer.write(bytes[offset:end].to_owned())
      offset = end
    }
  })
}

///|
/// A streaming value reader over `text`, encoded as UTF-8.
fn text_reader(text : String, chunk? : Int = 4096) -> @stream.TextReader {
  @stream.TextReader::new(reader_of(@utf8.encode(text), chunk~))
}

///|
/// Every value a streaming reader produces.
async fn read_all(reader : @stream.TextReader) -> Array[@ion.IonValue] {
  let values : Array[@ion.IonValue] = []
  let mut done = false
  while !done {
    match reader.next() {
      Some(value) => values.push(value)
      None => done = true
    }
  }
  values
}

///|
/// Whether streaming `text` in chunks of `chunk` octets yields the values the
/// sync reader parses from the whole text.
async fn assert_streams_like_sync(text : String, chunk : Int) -> Unit {
  let expected = @text.read_ion_datagram(text)
  let actual = read_all(text_reader(text, chunk~))
  assert_eq(actual.length(), expected.length())
  for index in 0..<expected.length() {
    assert_true(actual[index].equals(expected[index]))
  }
}

///|
/// Whether reading `text` to the end raises an error.
async fn fails(reader : @stream.TextReader) -> Bool {
  let mut failed = false
  ignore(
    read_all(reader) catch {
      _ => {
        failed = true
        []
      }
    },
  )
  failed
}

///|
/// A document whose values are hard to frame: each one could still grow if
/// the text were cut right after it.
let tricky : String =
  #|$ion_1_0 1 -2 3.5 4e0 2007-01-01T nan +inf null null.int true
  #|abc a :: b 'quoted' "str" '''long''' /* c */ '''er''' 'x'
  #|{a: 1, 'b': [2, (+ 3 -4)], c: {{ aGVsbG8= }}, d: {{ "clob" }}}
  #|(a <= b // comment
  #|  ) [] {} "é ✓ 😀" 'ünïcödé' // end
  #|

///|
async test "a stream of values is read one at a time" {
  let reader = text_reader("1 [2] {a: 3} ann::4 'five'")
  let values = @text.read_ion_datagram("1 [2] {a: 3} ann::4 'five'")
  let read_back = read_all(reader)
  assert_eq(read_back.length(), values.length())
  for index in 0..<values.length() {
    assert_true(read_back[index].equals(values[index]))
  }
}

///|
async test "values split across reads are still parsed" {
  // One octet at a time, so every token and every multi-octet UTF-8
  // character is split across reads.
  assert_streams_like_sync(tricky, 1)
}

///|
async test "every chunk size yields the values of the whole text" {
  for chunk in 1..<24 {
    assert_streams_like_sync(tricky, chunk)
  }
  assert_streams_like_sync(tricky, 4096)
}

///|
async test "an empty stream yields no values" {
  assert_eq(read_all(text_reader("")).length(), 0)
  assert_eq(
    read_all(text_reader("  // only a comment\n /* and another */ ")).length(),
    0,
  )
}

///|
async test "a closed value is read before the stream sends more" {
  @async.with_task_group(async fn(group) {
    let (read, write) = @io.pipe()
    defer read.close()
    // The writer stays open, so the reader sees no end of the stream.
    defer write.close()
    group.spawn_bg(async fn() { write.write(@utf8.encode("{a: 1}\n")) })
    let reader = @stream.TextReader::new(read)
    let value = @async.with_timeout(1000, async fn() { reader.next() })
    assert_true(value.unwrap().equals(@text.read_ion("{a: 1}")))
  })
}

///|
async test "a truncated value is reported" {
  assert_true(fails(text_reader("[1, 2", chunk=2)))
  assert_true(fails(text_reader("1 '''open", chunk=3)))
}

///|
async test "a syntax error is reported" {
  assert_true(fails(text_reader("1 ] 2")))
}

///|
async test "octets that are not UTF-8 are reported" {
  let reader = @stream.TextReader::new(reader_of(b"1 \xFF 2"))
  assert_true(fails(reader))
}

///|
async test "a stream that ends inside a UTF-8 character is reported" {
  let encoded = @utf8.encode("\"é")
  let truncated = encoded[:encoded.length() - 1].to_owned()
  assert_true(fails(@stream.TextReader::new(reader_of(truncated, chunk=1))))
}

///|
/// Every event a streaming event reader produces, as text.
async fn event_names(reader : @stream.TextEventReader) -> Array[String] {
  let names : Array[String] = []
  let mut done = false
  while !done {
    match reader.next() {
      Some(event) => names.push(event.to_text())
      None => done = true
    }
  }
  names
}

///|
async test "the event reader matches the sync event reader" {
  for chunk in [1, 5, 4096] {
    let reader = @stream.TextEventReader::new(
      reader_of(@utf8.encode(tricky), chunk~),
    )
    let expected = @text.IonReader::from_text(tricky)
      .remaining()
      .map(fn(event) { event.to_text() })
    assert_eq(event_names(reader), expected)
  }
}

///|
async test "the event reader frames an empty stream as a document" {
  let reader = @stream.TextEventReader::new(reader_of(Bytes::new(0)))
  assert_eq(event_names(reader), ["DocumentStart", "DocumentEnd"])
}

///|
/// A writer that collects every octet written to it.
struct Collector {
  mut bytes : Bytes
}

///|
impl @io.Writer for Collector with fn write_once(self, data, offset~, len~) {
  self.bytes = self.bytes + data[offset:offset + len].to_owned()
  len
}

///|
async test "the async writer produces the octets of the sync writer" {
  let values = @text.read_ion_datagram(tricky)
  let compact = { bytes: Bytes::new(0), }
  @stream.write_all(compact, values)
  assert_eq(compact.bytes, @utf8.encode(@text.write_all(values)))
  let pretty = { bytes: Bytes::new(0), }
  @stream.write_all(pretty, values, pretty=true)
  assert_eq(pretty.bytes, @utf8.encode(@text.write_all_pretty(values)))
}

///|
async test "a text writer writes one value at a time" {
  let values = @text.read_ion_datagram("1 [2] {a: 3} 'a b' \"é\"")
  let collector = { bytes: Bytes::new(0), }
  let writer = @stream.TextWriter::new(collector)
  for value in values {
    writer.write(value)
  }
  assert_eq(collector.bytes, @utf8.encode(@text.write_all(values)))
}

///|
async test "the async writer round-trips through the async reader" {
  let values = @text.read_ion_datagram(tricky)
  for pretty in [false, true] {
    let collector = { bytes: Bytes::new(0), }
    @stream.write_all(collector, values, pretty~)
    let read_back = read_all(
      @stream.TextReader::new(reader_of(collector.bytes, chunk=3)),
    )
    assert_eq(read_back.length(), values.length())
    for index in 0..<values.length() {
      assert_true(read_back[index].equals(values[index]))
    }
  }
}
