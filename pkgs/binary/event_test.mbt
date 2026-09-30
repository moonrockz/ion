// Black-box tests for the synchronous binary event reader.

///|
test "binary events retain annotations, field order, and scalar values" {
  let values = @text.read_ion_datagram(
    "a::b::{x: [c::1, null.list], x: (true null)}",
  )
  let reader = @binary.BinaryEventReader::new(@binary.write_binary(values))
  let names = reader.remaining().map(event => event.to_text())
  assert_eq(names, [
    "DocumentStart", "Annotation(a)", "Annotation(b)", "StructStart", "FieldName(x)",
    "ListStart", "Annotation(c)", "Scalar(int)", "Scalar(list)", "ListEnd", "FieldName(x)",
    "SexpStart", "Scalar(bool)", "Scalar(null)", "SexpEnd", "StructEnd", "DocumentEnd",
  ])
  assert_true(reader.next() is Some(@text.IonEvent::DocumentStart))
  assert_eq(reader.remaining().length(), names.length() - 1)
  let scalars : Array[@ion.IonValue] = []
  while reader.next() is Some(event) {
    if event is Scalar(value) {
      assert_true(value.annotations().is_empty())
      scalars.push(value)
    }
  }
  assert_true(scalars[0].equals(@ion.IonValue::int(1)))
  assert_true(scalars[1].equals(@ion.IonValue::typed_null(List)))
  assert_true(reader.next() is None)
  assert_true(reader.next() is None)
  assert_true(reader.remaining().is_empty())
}

///|
test "empty and padding-only binary datagrams have only document events" {
  for bytes in [b"", b"\xE0\x01\x00\xEA", b"\x00\x02\x00\x00"] {
    let reader = @binary.BinaryEventReader::new(bytes)
    assert_true(reader.next() is Some(@text.IonEvent::DocumentStart))
    assert_true(reader.next() is Some(@text.IonEvent::DocumentEnd))
    assert_true(reader.next() is None)
  }
}

///|
test "binary events apply local tables and version-marker resets" {
  let first = @binary.write_binary(
    @text.read_ion_datagram("first::{field: one}"),
  )
  let second = @binary.write_binary(
    @text.read_ion_datagram("second::{field: two}"),
  )
  let names = @binary.BinaryEventReader::new(first + second)
    .remaining()
    .map(event => event.to_text())
  assert_eq(names, [
    "DocumentStart", "Annotation(first)", "StructStart", "FieldName(field)", "Scalar(symbol)",
    "StructEnd", "Annotation(second)", "StructStart", "FieldName(field)", "Scalar(symbol)",
    "StructEnd", "DocumentEnd",
  ])
}

///|
test "binary event constructors reject truncated and malformed values" {
  for bytes in [b"\xE0\x01", b"\xB2\x21", b"\x12", b"\xF0"] {
    let error = try @binary.BinaryEventReader::new(bytes) catch {
      error => Some(error)
    } noraise {
      _ => None
    }
    assert_true(error is Some(@ion.IonError::Syntax(_)))
  }
}

///|
test "binary events resolve catalog imports and retain unknown symbol IDs" {
  let catalog = @ion.Catalog::new()
  catalog.add(@ion.SharedSymbolTable::new("example", 1, [Some("tag"), None]))
  let table = @ion.IonValue::from_fields([
    @ion.Field::new(
      "imports",
      @ion.IonValue::list([
        @ion.IonValue::from_fields([
          @ion.Field::new("name", @ion.IonValue::string("example")),
          @ion.Field::new("max_id", @ion.IonValue::int(2)),
        ]),
      ]),
    ),
  ]).with_annotations([@ion.SymbolToken::new("$ion_symbol_table")])
  let value = sid_symbol(11).with_annotations([@ion.SymbolToken::from_sid(10)])
  let reader = @binary.BinaryEventReader::new(
    @binary.write_binary([table, value]),
    catalog~,
  )
  assert_true(reader.next() is Some(@text.IonEvent::DocumentStart))
  match reader.next() {
    Some(Annotation(token)) => assert_eq(token.text(), Some("tag"))
    _ => fail("expected the catalog's annotation")
  }
  match reader.next() {
    Some(Scalar(value)) =>
      match value.kind() {
        Symbol(token) => {
          assert_eq(token.text(), None)
          assert_eq(token.sid(), Some(11))
        }
        _ => fail("expected a symbol")
      }
    _ => fail("expected a scalar")
  }
  assert_true(reader.next() is Some(@text.IonEvent::DocumentEnd))
}
