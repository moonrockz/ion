///|
async fn write_tree(
  writer : @stream.IncrementalWriter,
  value : @ion.IonValue,
) -> Unit {
  writer.set_annotations(value.annotations())
  match value.kind() {
    List(items) | Sexp(items) => {
      writer.step_in(value.ion_type())
      for item in items {
        write_tree(writer, item)
      }
      writer.step_out()
    }
    Struct(fields) => {
      writer.step_in(Struct)
      for field in fields {
        writer.set_field_name(field.name())
        write_tree(writer, field.value())
      }
      writer.step_out()
    }
    _ => writer.write(value.with_annotations([]))
  }
}

///|
async test "incremental nested containers match batch output" {
  let values = @text.read_ion_datagram(
    "ann::[{a: (foo + 2), a: [], 'a b': null.struct}, -0e0, -0d2, 2007-01-01T, {{aGVsbG8=}}, {{\"clob\"}}, true, \"é\"]",
  )
  for pretty in [false, true] {
    let sink = Collector::{ bytes: b"", }
    let writer = @stream.IncrementalWriter::new(sink, pretty~)
    for value in values {
      write_tree(writer, value)
    }
    writer.finish()
    let expected = if pretty {
      @text.write_all_pretty(values)
    } else {
      @text.write_all(values)
    }
    assert_eq(sink.bytes, @utf8.encode(expected))
  }
}

///|
async test "text emits an open large list immediately" {
  let sink = Collector::{ bytes: b"", }
  let writer = @stream.IncrementalWriter::new(sink)
  writer.step_in(List)
  assert_eq(sink.bytes, b"[")
  for index in 0..<100 {
    writer.write_int(index)
  }
  assert_true(sink.bytes.length() > 300)
  assert_false(sink.bytes[sink.bytes.length() - 1] == 0x5D)
  writer.step_out()
  writer.finish()
  assert_true(
    @text.read_ion(@utf8.decode(sink.bytes)).equals(
      @ion.IonValue::list(Array::makei(100, @ion.IonValue::int)),
    ),
  )
}

///|
async test "incremental writers preserve unknown symbols in declared context" {
  let value = @text.read_ion(
    "$ion_symbol_table::{imports:[{name:\"shared\",version:2,max_id:2}],symbols:[null]} $10::{$11:[$12,$0]}",
  )
  let sink = Collector::{ bytes: b"", }
  let writer = @stream.IncrementalWriter::new(
    sink,
    symbols=@ion.SymbolTable::for_values([value]),
  )
  write_tree(writer, value)
  writer.finish()
  let actual = @text.read_ion(@utf8.decode(sink.bytes))
  assert_true(actual.equals(value))
}

///|
async test "incremental writer sequence errors are recoverable before output" {
  let sink = Collector::{ bytes: b"", }
  let writer = @stream.IncrementalWriter::new(sink)
  let mut errors = 0
  writer.step_out() catch {
    _ => errors += 1
  }
  writer.step_in(Int) catch {
    _ => errors += 1
  }
  writer.set_field_name(@ion.SymbolToken::new("outside")) catch {
    _ => errors += 1
  }
  writer.step_in(Struct)
  writer.finish() catch {
    _ => errors += 1
  }
  writer.write_int(1) catch {
    _ => errors += 1
  }
  writer.set_field_name(@ion.SymbolToken::new("a"))
  writer.set_field_name(@ion.SymbolToken::new("b")) catch {
    _ => errors += 1
  }
  writer.step_out() catch {
    _ => errors += 1
  }
  writer.set_annotations([@ion.SymbolToken::from_sid(100)])
  writer.write_int(2) catch {
    _ => errors += 1
  }
  writer.set_annotations([])
  writer.write_int(2)
  writer.step_out()
  writer.finish()
  writer.write_bool(true) catch {
    _ => errors += 1
  }
  assert_eq(errors, 9)
  assert_true(
    @text.read_ion(@utf8.decode(sink.bytes)).equals(@text.read_ion("{a:2}")),
  )
}

///|
struct BrokenSink {}

///|
impl @io.Writer for BrokenSink with fn write_once(_self, _data, offset~, len~) {
  ignore(offset)
  ignore(len)
  raise @ion.IonError::DataModel("sink failed")
}

///|
async test "output failure prevents reuse" {
  let writer = @stream.IncrementalWriter::new(BrokenSink::{ })
  let mut errors = 0
  writer.write_int(1) catch {
    _ => errors += 1
  }
  writer.write_int(2) catch {
    _ => errors += 1
  }
  writer.finish() catch {
    _ => errors += 1
  }
  assert_eq(errors, 3)
}

///|
async test "cancellation during output prevents reuse" {
  let (read, write) = @io.pipe()
  defer read.close()
  defer write.close()
  let writer = @stream.IncrementalWriter::new(write)
  let mut errors = 0
  // No consumer: output blocks until the deadline cancels it.
  @async.with_timeout(10, async fn() { writer.write_int(1) }) catch {
    _ => errors += 1
  }
  writer.write_int(2) catch {
    _ => errors += 1
  }
  assert_eq(errors, 2)
}

///|
async test "concurrent use is rejected while a sink write is pending" {
  @async.with_task_group(async fn(group) {
    let (read, write) = @io.pipe()
    defer read.close()
    defer write.close()
    let writer = @stream.IncrementalWriter::new(write)
    let task = group.spawn(async fn() { writer.write_int(1) })
    @async.sleep(1)
    let rejected = try writer.set_annotations([]) catch {
      _ => true
    } noraise {
      _ => false
    }
    assert_true(rejected)
    let buffer : FixedArray[Byte] = FixedArray::make(4096, 0)
    assert_true(read.read(buffer) > 0)
    task.wait()
    writer.finish()
  })
}
