///|
fn unknown(
  name : String,
  slot : Int,
  local_sid? : Int = 10,
) -> @ion.SymbolToken {
  @ion.SymbolToken::from_import(local_sid, name, 1, slot)
}

///|
test "writers preserve unknown imports from different source contexts" {
  let a = unknown("a", 1)
  let b = unknown("b", 2)
  let shifted_a = unknown("a", 1, local_sid=99)
  let local_unknown = @ion.SymbolToken::from_sid(10)
  let value = @ion.IonValue::from_fields([
    @ion.Field::from_token(
      b,
      @ion.IonValue::list([
        @ion.IonValue::symbol_token(a),
        @ion.IonValue::symbol_token(shifted_a),
        @ion.IonValue::sexp([@ion.IonValue::symbol_token(b)]),
        @ion.IonValue::symbol_token(local_unknown),
        @ion.IonValue::symbol("known"),
      ]),
    ),
    @ion.Field::from_token(a, @ion.IonValue::int(2)),
  ]).with_annotations([a, b])
  let values = [value, @ion.IonValue::symbol_token(local_unknown)]
  for encoded in [@text.write_all(values), @text.write_all_pretty(values)] {
    let read_back = @text.read_ion_datagram(encoded)
    assert_eq(read_back.length(), 2)
    for index in 0..<values.length() {
      assert_true(values[index].equals(read_back[index]))
    }
  }
  let binary = @binary.write_binary(values)
  let read_back = @binary.read_binary(binary)
  assert_eq(read_back.length(), 2)
  for index in 0..<values.length() {
    assert_true(values[index].equals(read_back[index]))
  }
  let original = @text.read_ion_datagram(
    "$ion_symbol_table::{imports:[{name:\"prefix\",max_id:5},{name:\"a\",max_id:2}]} $15::{$16:$15}",
  )
  assert_true(
    original[0].equals(@binary.read_binary(@binary.write_binary(original))[0]),
  )
}

///|
test "shared null slots remain unknown when round-tripped with a catalog" {
  let catalog = @ion.Catalog::load(
    @text.read_ion_datagram(
      "$ion_shared_symbol_table::{name:\"shared\",version:1,symbols:[null]} $ion_shared_symbol_table::{name:\"shared\",version:2,symbols:[null,\"second\"]}",
    ),
  )
  let values = @text.read_ion_datagram(
    "$ion_symbol_table::{imports:[{name:\"shared\",version:2,max_id:3}]} $10 $11 $12",
    catalog~,
  )
  let text = @text.read_ion_datagram(@text.write_all(values), catalog~)
  let binary = @binary.read_binary(@binary.write_binary(values), catalog~)
  for index in 0..<values.length() {
    assert_true(values[index].equals(text[index]))
    assert_true(values[index].equals(binary[index]))
  }
}

///|
test "a writer rejects conflicting unknown shared-table versions in one value" {
  let value = @ion.IonValue::list([
    @ion.IonValue::symbol_token(
      @ion.SymbolToken::from_import(10, "shared", 1, 1),
    ),
    @ion.IonValue::symbol_token(
      @ion.SymbolToken::from_import(10, "shared", 2, 1),
    ),
  ])
  for binary in [false, true] {
    let mut rejected = false
    ignore(
      try {
        if binary {
          ignore(@binary.write_binary_value(value))
        } else {
          ignore(@text.write_ion(value))
        }
      } catch {
        @ion.IonError::Unsupported(_) => rejected = true
        error => fail(error.message())
      },
    )
    assert_true(rejected)
  }
}

///|
test "writer contexts reject invalid locations and ID overflow" {
  for
    values in [
      [
        @ion.IonValue::symbol_token(
          @ion.SymbolToken::from_import(10, "shared", 1, 0),
        ),
      ],
      [
        @ion.IonValue::symbol_token(
          @ion.SymbolToken::from_import(10, "shared", 0, 1),
        ),
      ],
      [
        @ion.IonValue::symbol_token(
          @ion.SymbolToken::from_import(10, "$ion", 1, 1),
        ),
      ],
      [
        @ion.IonValue::symbol_token(
          @ion.SymbolToken::from_import(10, "shared", 1, 0x7FFF_FFFF),
        ),
      ],
      [
        @ion.IonValue::symbol_token(
          @ion.SymbolToken::from_import(10, "shared", 1, 1),
        ),
        @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(0x7FFF_FFFF)),
      ],
    ] {
    let mut rejected = false
    ignore(
      @binary.write_binary(values) catch {
        @ion.IonError::DataModel(_) => {
          rejected = true
          b""
        }
        error => fail(error.message())
      },
    )
    assert_true(rejected)
  }
  // A large imported address needs no allocation proportional to the slot.
  let value = @ion.IonValue::symbol_token(
    @ion.SymbolToken::from_import(10, "shared", 1, 0x7FFF_FFFF - 9),
  )
  assert_true(
    @binary.read_binary(@binary.write_binary_value(value))[0].equals(value),
  )
}
