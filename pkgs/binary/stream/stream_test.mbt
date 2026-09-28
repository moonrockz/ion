// Black-box tests for the streaming Ion binary reader and writer.
//
// Values travel through an in-memory async pipe, so the streaming path is
// exercised end to end without touching the file system.

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
/// Every value a streaming reader produces.
async fn read_all(reader : @stream.BinaryReader) -> Array[@ion.IonValue] {
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
async test "a stream of values is read one at a time" {
  let values = @text.read_ion_datagram("1 [2] {a: 3} ann::4 'five'")
  let reader = @stream.BinaryReader::new(
    reader_of(@binary.write_binary(values)),
  )
  let read_back = read_all(reader)
  assert_eq(read_back.length(), values.length())
  for index in 0..<values.length() {
    assert_true(read_back[index].equals(values[index]))
  }
}

///|
async test "the async writer produces the same octets as the sync encoder" {
  let values = @text.read_ion_datagram("1 [2] {a: 3} 'a b' ann::[true]")
  let collector = { bytes: Bytes::new(0), }
  @stream.write_all(collector, values)
  assert_eq(collector.bytes, @binary.write_binary(values))
}

///|
async test "the async writer round-trips through the async reader" {
  let values = @text.read_ion_datagram(
    "{name: \"ion\", tags: [a, b]} ann::[1, 2] (x y) 'z z'",
  )
  let collector = { bytes: Bytes::new(0), }
  @stream.write_all(collector, values)
  let read_back = read_all(
    @stream.BinaryReader::new(reader_of(collector.bytes)),
  )
  assert_eq(read_back.length(), values.length())
  for index in 0..<values.length() {
    assert_true(read_back[index].equals(values[index]))
  }
}

///|
async test "a value split across reads is still decoded" {
  let values = @text.read_ion_datagram("[1, [2, 3], {a: 4}] 'symbol' \"text\"")
  let encoded = @binary.write_binary(values)
  // One octet at a time, so every value is framed across several reads.
  let reader = @stream.BinaryReader::new(reader_of(encoded, chunk=1))
  let read_back = read_all(reader)
  assert_eq(read_back.length(), values.length())
  for index in 0..<values.length() {
    assert_true(read_back[index].equals(values[index]))
  }
}

///|
async test "an empty stream yields no values" {
  let reader = @stream.BinaryReader::new(reader_of(Bytes::new(0)))
  assert_eq(read_all(reader).length(), 0)
}

///|
async test "a truncated value is reported" {
  let values = @text.read_ion_datagram("[1, 2, 3]")
  let encoded = @binary.write_binary(values)
  let truncated = encoded[:encoded.length() - 1].to_owned()
  let reader = @stream.BinaryReader::new(reader_of(truncated))
  let mut failed = false
  ignore(
    read_all(reader) catch {
      _ => {
        failed = true
        []
      }
    },
  )
  assert_true(failed)
}

///|
async test "a large value and many small ones arrive in small reads" {
  let items : Array[@ion.IonValue] = []
  for i in 0..<20000 {
    items.push(@ion.IonValue::int(i))
  }
  let values = [@ion.IonValue::list(items)]
  for i in 0..<2000 {
    values.push(
      @ion.IonValue::from_fields([@ion.Field::new("id", @ion.IonValue::int(i))]),
    )
  }
  for chunk in [7, 4096] {
    let read_back = read_all(
      @stream.BinaryReader::new(reader_of(@binary.write_binary(values), chunk~)),
    )
    assert_eq(read_back.length(), values.length())
    for index in 0..<values.length() {
      assert_true(read_back[index].equals(values[index]))
    }
  }
}
