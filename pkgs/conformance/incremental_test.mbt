// Exercise step-in/out, metadata and scalar writes against every good corpus file.

///|
async fn write_text_tree(
  writer : @text_stream.IncrementalWriter,
  value : @ion.IonValue,
) -> Unit {
  writer.set_annotations(value.annotations())
  match value.kind() {
    List(items) | Sexp(items) => {
      writer.step_in(value.ion_type())
      for item in items {
        write_text_tree(writer, item)
      }
      writer.step_out()
    }
    Struct(fields) => {
      writer.step_in(Struct)
      for field in fields {
        writer.set_field_name(field.name())
        write_text_tree(writer, field.value())
      }
      writer.step_out()
    }
    _ => writer.write(value.with_annotations([]))
  }
}

///|
async fn write_binary_tree(
  writer : @binary_stream.IncrementalWriter,
  value : @ion.IonValue,
) -> Unit {
  writer.set_annotations(value.annotations())
  match value.kind() {
    List(items) | Sexp(items) => {
      writer.step_in(value.ion_type())
      for item in items {
        write_binary_tree(writer, item)
      }
      writer.step_out()
    }
    Struct(fields) => {
      writer.step_in(Struct)
      for field in fields {
        writer.set_field_name(field.name())
        write_binary_tree(writer, field.value())
      }
      writer.step_out()
    }
    _ => writer.write(value.with_annotations([]))
  }
}

///|
async fn check_incremental(values : Array[@ion.IonValue]) -> Unit {
  for value in values {
    for pretty in [false, true] {
      let sink = Octets::{ written: b"", }
      let writer = @text_stream.IncrementalWriter::new(
        sink,
        pretty~,
        symbols=@ion.SymbolTable::for_values([value]),
      )
      write_text_tree(writer, value)
      writer.finish()
      assert_true(
        same_values(
          [value],
          @text.read_ion_datagram(@utf8.decode(sink.written)),
        ),
      )
    }
    let sink = Octets::{ written: b"", }
    let writer = @binary_stream.IncrementalWriter::new(
      sink,
      symbols=@ion.SymbolTable::for_values([value]),
    )
    write_binary_tree(writer, value)
    writer.finish()
    assert_eq(sink.written, @binary.write_binary([value]))
    assert_true(same_values([value], @binary.read_binary(sink.written)))
  }
}
