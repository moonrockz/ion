// End-to-end tests for binary events over chunked async sources.

///|
async fn read_events(
  reader : @stream.BinaryEventReader,
) -> Array[@text.IonEvent] {
  let events : Array[@text.IonEvent] = []
  while reader.next() is Some(event) {
    events.push(event)
  }
  assert_true(reader.next() is None)
  events
}

///|
async test "binary events match text across one-octet reads and prefixes" {
  let text = "a::b::{x: [c::1, null.list], x: (true null)} 2.500 2001T \"hi\""
  let expected = @text.IonReader::from_text(text).remaining()
  let bytes = @binary.write_binary(@text.read_ion_datagram(text))
  for chunk in [1, 4096] {
    for split in [0, 2, 4, bytes.length()] {
      let source = reader_of(bytes[split:].to_owned(), chunk~)
      defer source.close()
      let events = read_events(
        @stream.BinaryEventReader::new(source, prefix=bytes[:split].to_owned()),
      )
      assert_eq(events.length(), expected.length())
      for index in 0..<events.length() {
        match (events[index], expected[index]) {
          (Scalar(a), Scalar(b)) => assert_true(a.equals(b))
          _ => assert_eq(events[index].to_text(), expected[index].to_text())
        }
      }
    }
  }
}

///|
async test "empty and padding-only streams emit one document boundary pair" {
  for bytes in [b"", b"\xE0\x01\x00\xEA", b"\x00\x02\x00\x00"] {
    let source = reader_of(bytes, chunk=1)
    defer source.close()
    let reader = @stream.BinaryEventReader::new(source)
    assert_true(reader.next() is Some(@text.IonEvent::DocumentStart))
    assert_true(reader.next() is Some(@text.IonEvent::DocumentEnd))
    assert_true(reader.next() is None)
    assert_true(reader.next() is None)
  }
}

///|
async test "a truncated stream raises instead of emitting document end" {
  let bytes = @binary.write_binary(@text.read_ion_datagram("1 [2, 3]"))
  let source = reader_of(bytes[:bytes.length() - 1].to_owned(), chunk=1)
  defer source.close()
  let reader = @stream.BinaryEventReader::new(source)
  assert_true(reader.next() is Some(@text.IonEvent::DocumentStart))
  assert_true(reader.next() is Some(@text.IonEvent::Scalar(_)))
  let error = try read_events(reader) catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  assert_true(error is Some(@ion.IonError::Syntax(_)))
}

///|
async test "binary stream events resolve catalog imports across resets" {
  let catalog = @ion.Catalog::new()
  catalog.add(
    @ion.SharedSymbolTable::new("example", 1, [Some("tag"), Some("value")]),
  )
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
  let value = @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(11)).with_annotations([
      @ion.SymbolToken::from_sid(10),
    ],
  )
  let imported = @binary.write_binary([table, value])
  let later = @binary.write_binary(@text.read_ion_datagram("later"))
  let source = reader_of(imported + later, chunk=1)
  defer source.close()
  let events = read_events(@stream.BinaryEventReader::new(source, catalog~))
  assert_eq(events.length(), 5)
  match events[1] {
    Annotation(token) => assert_eq(token.text(), Some("tag"))
    _ => fail("expected the catalog's annotation")
  }
  match events[2] {
    Scalar(value) => assert_true(value.equals(@ion.IonValue::symbol("value")))
    _ => fail("expected the catalog's symbol")
  }
  match events[3] {
    Scalar(value) => assert_true(value.equals(@ion.IonValue::symbol("later")))
    _ => fail("expected the symbol after the reset")
  }
}
