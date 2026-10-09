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
async fn operation(mode : String, fixture : Fixture) -> Int {
  let values = fixture.values
  let text = fixture.text
  let binary = fixture.binary
  let text_bytes = fixture.text_bytes
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
    "equals" => {
      let mut count = 0
      for index, value in values {
        if value.equals(fixture.copies[index]) {
          count += 1
        }
      }
      count
    }
    "fold" =>
      @ion.fold_values(values, 0, {
        ..@ion.IonFold::default(),
        visit_value: (count, _) => Continue(count + 1),
      })
    "visitor" => {
      let counter : ValueCounter = { count: 0, }
      @ion.accept_values(values, counter)
      counter.count
    }
    "events" => @text.IonReader::from_values(values).remaining().length()
    "dispatch" => {
      let counter : EventCounter = { count: 0, }
      @text.dispatch_values(values, counter)
      counter.count
    }
    "write-text-pretty" => @utf8.encode(@text.write_all_pretty(values)).length()
    "to-json" => {
      let mut count = 0
      for value in values {
        ignore(@json.to_json(value))
        count += 1
      }
      count
    }
    "to-ion" => {
      let mut count = 0
      for json in fixture.json {
        ignore(@json.to_ion(json))
        count += 1
      }
      count
    }
    "resolve" => {
      let table = @ion.SymbolTable::system()
      let mut count = 0
      for value in values {
        ignore(table.resolve(value))
        count += 1
      }
      count
    }
    "localize" => {
      let table = @ion.SymbolTable::for_values(fixture.resolved)
      let mut count = 0
      for value in fixture.resolved {
        ignore(table.localize_for_text(value))
        count += 1
      }
      count
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
  let values = fixture_values(shape, items)
  let text = @text.write_all(values)
  let binary = @binary.write_binary(values)
  let fixture : Fixture = {
    values,
    copies: fixture_values(shape, items),
    resolved: values.map(value => @ion.SymbolTable::system().resolve(value)),
    json: values.map(@json.to_json),
    text,
    binary,
    text_bytes: @utf8.encode(text),
  }
  let expected = operation(mode, fixture)
  let start = @async.now()
  let mut iterations = 0
  let mut elapsed = 0
  while elapsed < minimum_ms {
    let actual = operation(mode, fixture)
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

///|
/// One value nested 100 levels deep (list, struct and sexp in turn), below
/// the reader limit so every mode can read it back.
fn deep_fixture_value(index : Int) -> @ion.IonValue {
  let mut value = @ion.IonValue::int(index)
  for level = 99; level >= 0; level = level - 1 {
    value = match level % 3 {
      0 => @ion.IonValue::list([value])
      1 => @ion.IonValue::from_fields([@ion.Field::new("name", value)])
      _ => @ion.IonValue::sexp([value])
    }
  }
  value
}

///|
/// One value with every scalar type, annotations, an S-expression with
/// operators, and symbols known only by a system symbol ID.
fn mixed_fixture_value(index : Int) -> @ion.IonValue {
  let sid = @ion.SymbolToken::from_sid
  @ion.IonValue::from_fields([
    @ion.Field::new("int", @ion.IonValue::int(index)),
    @ion.Field::new(
      "big",
      @ion.IonValue::big_int(
        BigInt::from_int(index) * BigInt::from_int64(1_000_000_000_000L),
      ),
    ),
    @ion.Field::new("float", @ion.IonValue::float(index.to_double() / 3.0)),
    @ion.Field::new(
      "decimal",
      @ion.IonValue::decimal(@ion.Decimal::new(BigInt::from_int(index), -2)),
    ),
    @ion.Field::new(
      "timestamp",
      @ion.IonValue::timestamp(
        @ion.Timestamp::new(year=2026, month=Some(10), day=Some(8)),
      ),
    ),
    @ion.Field::from_token(sid(5), @ion.IonValue::symbol_token(sid(7))),
    @ion.Field::new("string", @ion.IonValue::string("value \{index}")),
    @ion.Field::new("clob", @ion.IonValue::clob(b"clob")),
    @ion.Field::new("blob", @ion.IonValue::blob(b"\x00\x01\x02")),
    @ion.Field::new(
      "nulls",
      @ion.IonValue::list([
        @ion.IonValue::untyped_null(),
        @ion.IonValue::typed_null(Struct),
      ]),
    ),
    @ion.Field::new(
      "sexp",
      @ion.IonValue::sexp([
        @ion.IonValue::symbol("+"),
        @ion.IonValue::int(1),
        @ion.IonValue::symbol("x"),
      ]),
    ),
    @ion.Field::new(
      "annotated",
      @ion.IonValue::list([@ion.IonValue::bool(true)]).with_annotations([
        @ion.SymbolToken::new("tag"),
        sid(4),
      ]),
    ),
  ])
}

///|
/// The values of a benchmark shape: `many` small structs, one `large` list,
/// `deep` values nested 100 levels, or `mixed` values of every type.
fn fixture_values(
  shape : String,
  items : Int,
) -> Array[@ion.IonValue] raise @ion.IonError {
  match shape {
    "many" =>
      Array::make(
        items,
        @text.read_ion("{name: \"ion\", values: [1, 2, 3], tag: sample}"),
      )
    "large" => [@ion.IonValue::list(Array::makei(items, @ion.IonValue::int))]
    "deep" => Array::makei(items / 5, deep_fixture_value)
    "mixed" => Array::makei(items / 5, mixed_fixture_value)
    _ => raise @ion.IonError::DataModel("unknown benchmark shape")
  }
}

///|
/// Everything a mode needs, prepared before the timed loop.
struct Fixture {
  values : Array[@ion.IonValue]
  /// A second, separately built copy of `values`, for `equals`.
  copies : Array[@ion.IonValue]
  /// `values` with text for every symbol, for `localize`: a symbol known only
  /// by a system ID has no matching writer context.
  resolved : Array[@ion.IonValue]
  json : Array[Json]
  text : String
  binary : Bytes
  text_bytes : Bytes
}

///|
struct ValueCounter {
  mut count : Int
}

///|
impl @ion.IonVisitor for ValueCounter with fn visit_value(self, _value) {
  self.count += 1
}

///|
struct EventCounter {
  mut count : Int
}

///|
impl @text.IonHandler for EventCounter with fn on_scalar(self, _value) {
  self.count += 1
}

///|
impl @text.IonHandler for EventCounter with fn on_list_start(self) {
  self.count += 1
}

///|
impl @text.IonHandler for EventCounter with fn on_sexp_start(self) {
  self.count += 1
}

///|
impl @text.IonHandler for EventCounter with fn on_struct_start(self) {
  self.count += 1
}
