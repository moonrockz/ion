// The symbol walks of the data model: they find, intern, resolve and rewrite
// symbol tokens in document order — for each value, its field name, then its
// annotations, then its symbol value.

///|
test "for_values interns symbols in document order" {
  let value = @text.read_ion("x::{b: a, c: y::[d]}")
  let table = @ion.SymbolTable::for_values([value])
  debug_inspect(
    ["x", "b", "a", "c", "y", "d"].map(text => table.find(text)),
    content=(
      #|[Some(10), Some(11), Some(12), Some(13), Some(14), Some(15)]
    ),
  )
}

///|
test "highest_symbol_id finds IDs in field names, annotations and values" {
  let sid = @ion.SymbolToken::from_sid
  let value = @ion.IonValue::list([
    @ion.IonValue::from_fields([
      @ion.Field::from_token(sid(30), @ion.IonValue::int(1)),
    ]),
    @ion.IonValue::int(2).with_annotation(sid(20)),
    @ion.IonValue::symbol_token(sid(25)),
  ])
  assert_eq(@ion.highest_symbol_id([value]), 30)
}
