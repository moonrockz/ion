///|
test "unknown imported identity ignores stream IDs and table versions" {
  let a = @ion.SymbolToken::from_import(10, "shared", 1, 1)
  let shifted = @ion.SymbolToken::from_import(20, "shared", 2, 1)
  assert_true(a.equivalent(shifted))
  assert_false(a.equivalent(@ion.SymbolToken::from_import(10, "other", 1, 1)))
  assert_false(a.equivalent(@ion.SymbolToken::from_import(10, "shared", 1, 2)))
  assert_false(a.equivalent(@ion.SymbolToken::from_sid(10)))
  assert_false(a.equivalent(@ion.SymbolToken::from_sid(0)))
  assert_false(a.equivalent(@ion.SymbolToken::new("shared")))
  assert_true(
    @ion.SymbolToken::from_sid(10).equivalent(@ion.SymbolToken::from_sid(0)),
  )
  assert_true(@ion.SymbolToken::new("a").equivalent(@ion.SymbolToken::new("a")))
}

///|
test "readers compare import locations in values annotations and field names" {
  let first = @text.read_ion_datagram(
      "$ion_symbol_table::{imports:[{name:\"shared\",version:1,max_id:2}]} $10::{$11:[$10,($11)]}",
    )[0]
  let shifted = @text.read_ion_datagram(
      "$ion_symbol_table::{imports:[{name:\"prefix\",max_id:3},{name:\"shared\",version:2,max_id:2}]} $13::{$14:[$13,($14)]}",
    )[0]
  assert_true(first.equals(shifted))
  let other = @text.read_ion_datagram(
      "$ion_symbol_table::{imports:[{name:\"other\",max_id:2}]} $10::{$11:[$10,($11)]}",
    )[0]
  assert_false(first.equals(other))
  let a = @ion.SymbolToken::from_import(10, "shared", 1, 1)
  let b = @ion.SymbolToken::from_import(10, "shared", 1, 2)
  assert_false(
    @ion.IonValue::symbol_token(a).equals(@ion.IonValue::symbol_token(b)),
  )
  assert_false(
    @ion.IonValue::int(1)
    .with_annotation(a)
    .equals(@ion.IonValue::int(1).with_annotation(b)),
  )
  assert_false(
    @ion.IonValue::from_fields([
      @ion.Field::from_token(a, @ion.IonValue::int(1)),
    ]).equals(
      @ion.IonValue::from_fields([
        @ion.Field::from_token(b, @ion.IonValue::int(1)),
      ]),
    ),
  )
}

///|
test "null shared slots and unresolved padding retain their import location" {
  let catalog = @ion.Catalog::load(
    @text.read_ion_datagram(
      "$ion_shared_symbol_table::{name:\"shared\",version:2,symbols:[null,\"known\"]}",
    ),
  )
  let values = @text.read_ion_datagram(
    "$ion_symbol_table::{imports:[{name:\"shared\",version:2,max_id:3}],symbols:[null]} $10 $11 $12 $13 $0",
    catalog~,
  )
  assert_true(
    values[0].equals(
      @ion.IonValue::symbol_token(
        @ion.SymbolToken::from_import(99, "shared", 1, 1),
      ),
    ),
  )
  assert_true(values[1].equals(@ion.IonValue::symbol("known")))
  assert_true(
    values[2].equals(
      @ion.IonValue::symbol_token(
        @ion.SymbolToken::from_import(99, "shared", 1, 3),
      ),
    ),
  )
  assert_false(values[0].equals(values[2]))
  assert_false(values[0].equals(values[4]))
  assert_true(values[3].equals(values[4]))
  // A resolved token belongs to its source import, even in a different table.
  let table = @ion.SymbolTable::system()
  assert_true(table.resolve(values[0]).equals(values[0]))
}

///|
test "reserving local unknown IDs retains named locals and can be resized" {
  let table = @ion.SymbolTable::system()
  ignore(table.intern("known"))
  table.reserve(3)
  assert_eq(table.find("known"), Some(13))
  assert_eq(table.max_id(), 13)
  assert_true(table.lookup(10).equivalent(@ion.SymbolToken::from_sid(0)))
  table.reserve(1)
  assert_eq(table.find("known"), Some(11))
  assert_eq(table.max_id(), 11)
  let copy = @ion.SymbolTable::system()
  assert_true(
    copy.apply_local_symbol_table(table.to_local_symbol_table().unwrap()),
  )
  assert_eq(copy.lookup(11).text(), Some("known"))
  table.reset()
  assert_eq(table.max_id(), 9)
}
