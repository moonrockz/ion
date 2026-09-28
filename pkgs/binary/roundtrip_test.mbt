// Black-box tests for the Ion binary codec.
//
// Values are built from Ion text, written to Ion binary, read back, and
// compared, so the two encodings cross-check each other. A few encodings are
// also pinned byte for byte.

///|
/// Lowercase hexadecimal of a byte sequence.
fn hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder()
  for index in 0..<bytes.length() {
    let value = bytes[index].to_int()
    sb.write_view(digits[value >> 4:(value >> 4) + 1])
    sb.write_view(digits[value & 0x0F:(value & 0x0F) + 1])
  }
  sb.to_string()
}

///|
/// The Ion binary datagram for an Ion text document.
fn to_binary(text : String) -> Bytes raise @ion.IonError {
  @binary.write_binary([@text.read_ion(text)])
}

///|
/// Whether an Ion text document survives a trip through Ion binary unchanged.
fn survives(text : String) -> Bool raise @ion.IonError {
  let value = @text.read_ion(text)
  match @binary.read_binary(@binary.write_binary([value])) {
    [read_back] => read_back.equals(value)
    _ => false
  }
}

///|
test "scalars survive a binary round-trip" {
  let scalars = [
    "null", "null.null", "null.bool", "null.int", "null.float", "null.decimal", "null.timestamp",
    "null.symbol", "null.string", "null.clob", "null.blob", "null.list", "null.sexp",
    "null.struct", "true", "false", "0", "-0", "1", "-1", "255", "-255", "256", "-256",
    "2147483647", "-2147483648", "9223372036854775807", "-9223372036854775808", "123456789012345678901234567890",
    "-123456789012345678901234567890", "0e0", "-0e0", "1.5e0", "-1.5e0", "nan", "+inf",
    "-inf", "1e100", "-1e-100", "0.", "-0.", "1d0", "123d-2", "-123d-2", "0d0", "-0d0",
    "0d5", "-0d5", "0d-1", "1.20d3", "2007T", "2007-02T", "2007-02-23", "2007-02-23T12:14Z",
    "2007-02-23T12:14-08:00", "2007-02-23T12:14:33Z", "2007-02-23T12:14:33.079-08:00",
    "2007-02-23T00:00:00-00:00", "0001-01-01T00:00:00Z", "9999-12-31T23:59:59.999999Z",
    "\"\"", "\"hello\"", "\"a\\tb\\nc\"", "\"\\u00e9\\U0001F600\"", "'sym'", "''",
    "'a b'", "'null'", "'$ion'", "{{ }}", "{{ aGk= }}", "{{ \"clob\" }}", "{{ \"\" }}",
  ]
  for text in scalars {
    let ok = survives(text) catch { _ => false }
    assert_true(ok, msg="round-trip failed for \{text}")
  }
}

///|
test "containers survive a binary round-trip" {
  let containers = [
    "[]", "[1]", "[1, 2, 3]", "[[], [[]]]", "[1, [2, {c: 3}], (d e)]", "()", "(a)",
    "(a b c)", "((()))", "(1 + 2)", "{}", "{a: 1}", "{a: 1, b: 2}", "{a: 1, a: 2}",
    "{a: {b: [1, 2]}, c: (x)}", "{a: {b: {c: {}}}}", "[{a: []}, (), {}]",
  ]
  for text in containers {
    let ok = survives(text) catch { _ => false }
    assert_true(ok, msg="round-trip failed for \{text}")
  }
}

///|
test "annotations survive a binary round-trip" {
  for
    text in [
      "ann::1", "a::b::c", "a::b::[c]", "ann::{}", "{x: a::1, y: b::c::2}", "(a::1 b::2)",
      "ann::[ann::2]",
    ] {
    let ok = survives(text) catch { _ => false }
    assert_true(ok, msg="round-trip failed for \{text}")
  }
}

///|
test "a datagram of several values survives a binary round-trip" {
  let text = "1 [2] {a: 3} ann::4 'five'"
  let values = @text.read_ion_datagram(text)
  let read_back = @binary.read_binary(@binary.write_binary(values))
  assert_eq(read_back.length(), values.length())
  for index in 0..<values.length() {
    assert_true(read_back[index].equals(values[index]))
  }
}

///|
test "the encoding is the compact Ion binary form" {
  // Version marker, then the value.
  assert_eq(hex(to_binary("null")), "e00100ea0f")
  assert_eq(hex(to_binary("null.int")), "e00100ea2f")
  assert_eq(hex(to_binary("false")), "e00100ea10")
  assert_eq(hex(to_binary("true")), "e00100ea11")
  assert_eq(hex(to_binary("0")), "e00100ea20")
  assert_eq(hex(to_binary("17")), "e00100ea2111")
  assert_eq(hex(to_binary("-1")), "e00100ea3101")
  assert_eq(hex(to_binary("255")), "e00100ea21ff")
  assert_eq(hex(to_binary("256")), "e00100ea220100")
  assert_eq(hex(to_binary("0e0")), "e00100ea480000000000000000")
  assert_eq(hex(to_binary("0.")), "e00100ea50")
  assert_eq(hex(to_binary("1d0")), "e00100ea528001")
  assert_eq(hex(to_binary("\"hi\"")), "e00100ea826869")
  assert_eq(hex(to_binary("[]")), "e00100eab0")
  assert_eq(hex(to_binary("()")), "e00100eac0")
  assert_eq(hex(to_binary("{}")), "e00100ead0")
  assert_eq(hex(to_binary("[[1], 2]")), "e00100eab5b221012102")
}

///|
test "a symbol outside the system table is declared by a local symbol table" {
  // `$ion_symbol_table::{symbols:["sym"]}` then the symbol with ID 10.
  assert_eq(hex(to_binary("'sym'")), "e00100eae98183d687b48373796d710a")
  // A system symbol needs no local table.
  assert_eq(hex(to_binary("'name'")), "e00100ea7104")
}

///|
test "reading tolerates padding, a missing version marker, and padded fields" {
  let int_zero : Array[Byte] = [0xE0, 0x01, 0x00, 0xEA, 0x00, 0x01, 0xFF, 0x20]
  assert_eq(@binary.read_binary(Bytes::from_array(int_zero)).length(), 1)
  // Without a version marker.
  let bare : Array[Byte] = [0x20]
  assert_eq(@binary.read_binary(Bytes::from_array(bare)).length(), 1)
  // A VarUInt length padded with zero groups is still valid.
  let padded : Array[Byte] = [
    0xE0, 0x01, 0x00, 0xEA, 0x8E, 0x00, 0x00, 0x82, 0x68, 0x69,
  ]
  let values = @binary.read_binary(Bytes::from_array(padded))
  assert_eq(values.length(), 1)
  assert_true(values[0].equals(@ion.IonValue::string("hi")))
}

///|
test "a local symbol table applies to the values after it" {
  // Two symbols whose ID the local table defines as "sym".
  let stream : Array[Byte] = [
    0xE0, 0x01, 0x00, 0xEA, 0xE9, 0x81, 0x83, 0xD6, 0x87, 0xB4, 0x83, 0x73, 0x79,
    0x6D, 0x71, 0x0A, 0x71, 0x0A,
  ]
  let values = @binary.read_binary(Bytes::from_array(stream))
  assert_eq(values.length(), 2)
  assert_true(values[0].equals(@ion.IonValue::symbol("sym")))
  assert_true(values[1].equals(@ion.IonValue::symbol("sym")))
}

///|
test "a symbol ID beyond the symbol table is rejected" {
  let stream : Array[Byte] = [0xE0, 0x01, 0x00, 0xEA, 0x71, 0x0B]
  let mut failed = false
  ignore(
    @binary.read_binary(Bytes::from_array(stream)) catch {
      _ => {
        failed = true
        []
      }
    },
  )
  assert_true(failed)
}

///|
test "a symbol ID with unknown text keeps only its ID" {
  // `$ion_symbol_table::{symbols: [null]}` and then the symbol with ID 10.
  let table = @ion.IonValue::from_fields([
    @ion.Field::new(
      "symbols",
      @ion.IonValue::list([@ion.IonValue::untyped_null()]),
    ),
  ]).with_annotations([@ion.SymbolToken::new("$ion_symbol_table")])
  let values = @binary.read_binary(
    @binary.write_binary([
      table,
      @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(10)),
    ]),
  )
  assert_eq(values.length(), 1)
  match values[0].kind() {
    @ion.IonValueKind::Symbol(token) => {
      assert_eq(token.text(), None)
      assert_eq(token.sid(), Some(10))
    }
    _ => fail("expected a symbol")
  }
}

///|
test "malformed input is rejected" {
  let cases : Array[Array[Byte]] = [
    // A descriptor without its representation.
    [0xE0, 0x01, 0x00, 0xEA, 0x82, 0x68],
    // A negative int with a zero magnitude.
    [0xE0, 0x01, 0x00, 0xEA, 0x31, 0x00],
    // A bool whose nibble is not 0 or 1.
    [0xE0, 0x01, 0x00, 0xEA, 0x12],
    // The reserved type code.
    [0xE0, 0x01, 0x00, 0xEA, 0xF0],
    // A float of a length that is not 0, 4, or 8.
    [0xE0, 0x01, 0x00, 0xEA, 0x42, 0x00, 0x00],
    // A container whose length overruns the input.
    [0xE0, 0x01, 0x00, 0xEA, 0xB5, 0x20],
    // A string that is not UTF-8.
    [0xE0, 0x01, 0x00, 0xEA, 0x82, 0xFF, 0xFF],
  ]
  for bytes in cases {
    let mut rejected = false
    ignore(
      @binary.read_binary(Bytes::from_array(bytes)) catch {
        _ => {
          rejected = true
          []
        }
      },
    )
    assert_true(
      rejected,
      msg="expected rejection of \{hex(Bytes::from_array(bytes))}",
    )
  }
}

///|
/// A struct field whose value is NOP padding is ignored, name and all: the
/// official examples all decode to an empty struct, or to the named field.
test "NOP padding inside a struct makes the field disappear" {
  // Empty structs from the specification and the ion-tests suite.
  let empty_structs : Array[Array[Byte]] = [
    [0xE0, 0x01, 0x00, 0xEA, 0xD2, 0x80, 0x00],
    [0xE0, 0x01, 0x00, 0xEA, 0xD3, 0x80, 0x01, 0xAC],
    [0xE0, 0x01, 0x00, 0xEA, 0xD2, 0x8F, 0x00],
  ]
  for bytes in empty_structs {
    let values = @binary.read_binary(Bytes::from_array(bytes))
    assert_eq(values.length(), 1)
    assert_true(values[0].equals(@ion.IonValue::from_fields([])))
  }
  // `{name: true}` — the SID 0 field that follows the named one is padding.
  let with_field : Array[Byte] = [
    0xE0, 0x01, 0x00, 0xEA, 0xD4, 0x84, 0x11, 0x80, 0x00,
  ]
  let values = @binary.read_binary(Bytes::from_array(with_field))
  assert_eq(values.length(), 1)
  assert_true(
    values[0].equals(
      @ion.IonValue::from_fields([
        @ion.Field::new("name", @ion.IonValue::bool(true)),
      ]),
    ),
  )
  // `{name:"a"}`, with four octets of padding around the field.
  let padded : Array[Byte] = [
    0xE0, 0x01, 0x00, 0xEA, 0xD7, 0x84, 0x81, 0x61, 0x80, 0x02, 0x01, 0x02,
  ]
  let values = @binary.read_binary(Bytes::from_array(padded))
  assert_true(
    values[0].equals(
      @ion.IonValue::from_fields([
        @ion.Field::new("name", @ion.IonValue::string("a")),
      ]),
    ),
  )
}

///|
test "NOP padding is skipped between list elements and at the top level" {
  // `[1, 2]` with one octet of padding between the elements.
  let list : Array[Byte] = [
    0xE0, 0x01, 0x00, 0xEA, 0xB6, 0x21, 0x01, 0x01, 0xAC, 0x21, 0x02,
  ]
  let values = @binary.read_binary(Bytes::from_array(list))
  assert_eq(values.length(), 1)
  assert_true(values[0].equals(@text.read_ion("[1, 2]")))
  // Padding between top-level values.
  let between : Array[Byte] = [
    0xE0, 0x01, 0x00, 0xEA, 0x01, 0xAC, 0x21, 0x01, 0x00, 0x21, 0x02,
  ]
  assert_eq(@binary.read_binary(Bytes::from_array(between)).length(), 2)
}

///|
test "an annotation may not wrap NOP padding" {
  let malformed : Array[Byte] = [
    0xE0, 0x01, 0x00, 0xEA, 0xD5, 0x80, 0xE3, 0x81, 0x84, 0x00,
  ]
  let mut rejected = false
  ignore(
    @binary.read_binary(Bytes::from_array(malformed)) catch {
      _ => {
        rejected = true
        []
      }
    },
  )
  assert_true(rejected)
}

///|
/// Generated values survive Ion binary: integers and strings are carried
/// exactly, and the local symbol table the writer emits preserves a symbol's
/// text.
test "generated values survive Ion binary" {
  @quickcheck.check((n : BigInt) => {
    let value = @ion.IonValue::big_int(n)
    match @binary.read_binary(@binary.write_binary([value])) {
      [read_back] => read_back.equals(value)
      _ => false
    }
  })
  @quickcheck.check((text : String) => {
    let value = @ion.IonValue::string(text)
    match @binary.read_binary(@binary.write_binary([value])) {
      [read_back] => read_back.equals(value)
      _ => false
    }
  })
  @quickcheck.check((text : String) => {
    // A top-level symbol whose text is `$ion_1_0` is the Ion binary version
    // marker, so a reader consumes it rather than returning it; every other
    // symbol keeps its text.
    if text == "$ion_1_0" {
      true
    } else {
      let value = @ion.IonValue::symbol(text)
      match @binary.read_binary(@binary.write_binary([value])) {
        [read_back] => read_back.equals(value)
        _ => false
      }
    }
  })
}

///|
/// The symbols that `values` read back to after a binary round trip, as text.
/// A value may be a local symbol table, which the reader applies.
fn read_back_text(values : Array[@ion.IonValue]) -> String raise {
  @text.write_all(@binary.read_binary(@binary.write_binary(values)))
}

///|
/// A local symbol table value declaring `symbols`, with `imports` when given.
fn table_value(
  symbols : Array[@ion.IonValue],
  imports? : @ion.IonValue,
) -> @ion.IonValue {
  let fields = [@ion.Field::new("symbols", @ion.IonValue::list(symbols))]
  if imports is Some(imports) {
    fields.insert(0, @ion.Field::new("imports", imports))
  }
  @ion.IonValue::from_fields(fields).with_annotations([
    @ion.SymbolToken::new("$ion_symbol_table"),
  ])
}

///|
/// A symbol known only by its ID.
fn sid_symbol(sid : Int) -> @ion.IonValue {
  @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(sid))
}

///|
test "a symbol table slot that is not a string has unknown text" {
  let table = table_value([
    @ion.IonValue::untyped_null(),
    @ion.IonValue::string("b"),
  ])
  // The writer reserves symbol 10, which has no text, when it writes it back.
  assert_eq(
    read_back_text([table, sid_symbol(10), sid_symbol(11)]),
    "$ion_symbol_table::{imports: [{name: \"moonrockz.ion.unknown_symbols\", version: 1, max_id: 1}]}\n$10\nb",
  )
}

///|
test "importing $ion_symbol_table appends to the local symbols" {
  let first = table_value([@ion.IonValue::string("a")])
  let second = table_value(
    [@ion.IonValue::string("b")],
    imports=@ion.IonValue::symbol("$ion_symbol_table"),
  )
  assert_eq(
    read_back_text([first, second, sid_symbol(10), sid_symbol(11)]),
    "a\nb",
  )
}

///|
test "a struct is a symbol table only when its first annotation says so" {
  let struct_ = @ion.IonValue::from_fields([
    @ion.Field::new(
      "symbols",
      @ion.IonValue::list([@ion.IonValue::string("a")]),
    ),
  ]).with_annotations([
    @ion.SymbolToken::new("x"),
    @ion.SymbolToken::new("$ion_symbol_table"),
  ])
  // The writer reserves symbol 10, whose text it does not know. Had the
  // struct been applied as a table, symbol 10 would read back as `a`.
  assert_eq(
    read_back_text([struct_, sid_symbol(10)]),
    "x::$ion_symbol_table::{symbols: [\"a\"]}\n$ion_symbol_table::{imports: [{name: \"moonrockz.ion.unknown_symbols\", version: 1, max_id: 1}]}\n$10",
  )
}

///|
test "a decimal or timestamp followed by another value in a container" {
  // Both end at their own length, not at the end of their container.
  for
    text in [
      "[2.5, \"s\"]", "(1.25 x)", "{a: 1.5, b: 2}", "[2007-01-01T12:30:15.25Z, 1]",
      "[2007-02-03T04:05Z, 2.5, 2007T]",
    ] {
    let values = @text.read_ion_datagram(text)
    let read_back = @binary.read_binary(@binary.write_binary(values))
    assert_eq(read_back.length(), 1)
    assert_true(read_back[0].equals(values[0]))
  }
}

///|
test "an ordered struct carries its length as a VarUInt" {
  // `{name: null, version: false, imports: true}` as an ordered struct: the
  // descriptor 0xD1, a VarUInt length of 6, and the fields in ID order.
  let stream : Array[Byte] = [
    0xE0, 0x01, 0x00, 0xEA, 0xD1, 0x86, 0x84, 0x0F, 0x85, 0x10, 0x86, 0x11,
  ]
  let values = @binary.read_binary(Bytes::from_array(stream))
  assert_eq(
    @text.write_all(values),
    "{name: null, version: false, imports: true}",
  )
}

///|
test "symbols with unknown text keep their IDs apart from the writer's own" {
  let values = [
    @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(27)),
    @ion.IonValue::symbol("a"),
    @ion.IonValue::symbol("b"),
  ]
  let read_back = @binary.read_binary(@binary.write_binary(values))
  assert_eq(read_back.length(), 3)
  match read_back[0].kind() {
    @ion.IonValueKind::Symbol(token) => {
      assert_eq(token.text(), None)
      assert_eq(token.sid(), Some(27))
    }
    _ => fail("expected a symbol")
  }
  assert_true(read_back[1].equals(values[1]))
  assert_true(read_back[2].equals(values[2]))
}
