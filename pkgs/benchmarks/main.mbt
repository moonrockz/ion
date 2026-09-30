///|
struct CountingSink {
  mut count : Int
}

///|
impl @io.Writer for CountingSink with fn write_once(self, _data, offset~, len~) {
  ignore(offset)
  self.count += len
  len
}

///|
fn source(bytes : Bytes) -> @io.MemoryReader {
  @io.MemoryReader(async fn(writer) { writer.write(bytes) })
}

///|
async fn operation(
  mode : String,
  values : Array[@ion.IonValue],
  text : String,
  binary : Bytes,
  text_bytes : Bytes,
) -> Int {
  match mode {
    "read-text-sync" => @text.read_ion_datagram(text).length()
    "read-binary-sync" => @binary.read_binary(binary).length()
    "read-text-stream" => {
      let input = source(text_bytes)
      defer input.close()
      let reader = @text_stream.TextReader::new(input)
      let mut count = 0
      while reader.next() is Some(_) {
        count += 1
      }
      count
    }
    "read-binary-stream" => {
      let input = source(binary)
      defer input.close()
      let reader = @binary_stream.BinaryReader::new(input)
      let mut count = 0
      while reader.next() is Some(_) {
        count += 1
      }
      count
    }
    "write-text-sync" => @utf8.encode(@text.write_all(values)).length()
    "write-binary-sync" => @binary.write_binary(values).length()
    "write-text-stream" => {
      let sink = CountingSink::{ count: 0, }
      @text_stream.write_all(sink, values)
      sink.count
    }
    "write-binary-stream" => {
      let sink = CountingSink::{ count: 0, }
      @binary_stream.write_all(sink, values)
      sink.count
    }
    "hash" => {
      let mut count = 0
      for value in values {
        count += @hash.ion_hash(value).length()
      }
      count
    }
    "write-text-incremental" => {
      let sink = CountingSink::{ count: 0, }
      let writer = @text_stream.IncrementalWriter::new(sink)
      writer.step_in(List)
      for
        index in 0..<(match values[0].kind() {
          List(items) => items.length()
          _ => 0
        }) {
        writer.write_int(index)
      }
      writer.step_out()
      writer.finish()
      sink.count
    }
    "write-binary-incremental" => {
      let sink = CountingSink::{ count: 0, }
      let writer = @binary_stream.IncrementalWriter::new(sink)
      writer.step_in(List)
      for
        index in 0..<(match values[0].kind() {
          List(items) => items.length()
          _ => 0
        }) {
        writer.write_int(index)
      }
      writer.step_out()
      writer.finish()
      sink.count
    }
    _ => raise @ion.IonError::DataModel("unknown benchmark mode")
  }
}

///|
async fn main {
  let args = @env.args()
  let mode = args[1]
  let shape = args[2]
  let items = positive_int(args[3])
  let minimum_ms = positive_int(args[4])
  let values = if shape == "many" {
    let value = @text.read_ion(
      "{name: \"ion\", values: [1, 2, 3], tag: sample}",
    )
    Array::make(items, value)
  } else {
    [@ion.IonValue::list(Array::makei(items, @ion.IonValue::int))]
  }
  let text = @text.write_all(values)
  let binary = @binary.write_binary(values)
  let text_bytes = @utf8.encode(text)
  let expected = operation(mode, values, text, binary, text_bytes)
  let start = @async.now()
  let mut iterations = 0
  let mut elapsed = 0
  while elapsed < minimum_ms {
    let actual = operation(mode, values, text, binary, text_bytes)
    if actual != expected {
      raise @ion.IonError::DataModel("unstable benchmark output")
    }
    iterations += 1
    elapsed = (@async.now() - start).to_int()
  }
  let bytes = if mode.contains("binary") {
    binary.length()
  } else {
    @utf8.encode(text).length()
  }
  println(
    {
      "iterations": iterations,
      "elapsed_ms": elapsed,
      "input_bytes": bytes,
      "checksum": expected,
    }
    .to_json()
    .stringify(),
  )
}

///|
fn positive_int(text : String) -> Int raise @ion.IonError {
  let mut number = 0
  for c in text {
    if c < '0' || c > '9' {
      raise @ion.IonError::DataModel("expected positive integer")
    }
    number = number * 10 + c.to_int() - 48
  }
  if number <= 0 {
    raise @ion.IonError::DataModel("expected positive integer")
  }
  number
}
