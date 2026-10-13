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
test "for_values interns annotations in order, before the symbol value" {
  let table = @ion.SymbolTable::for_values([@text.read_ion("x::y::a")])
  debug_inspect(
    ["x", "y", "a"].map(text => table.find(text)),
    content=(
      #|[Some(10), Some(11), Some(12)]
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

///|
fn resolve_error(value : @ion.IonValue) -> String {
  try @ion.SymbolTable::system().resolve(value) catch {
    error => error.message()
  } noraise {
    _ => "resolved"
  }
}

///|
test "resolve names the first out-of-range ID in document order" {
  let sid = @ion.SymbolToken::from_sid
  // A field name comes before its value's annotations and symbol.
  let field_first = @ion.IonValue::from_fields([
    @ion.Field::from_token(
      sid(20),
      @ion.IonValue::symbol_token(sid(30)).with_annotation(sid(40)),
    ),
  ])
  inspect(
    resolve_error(field_first),
    content="symbol ID $20 is beyond the symbol table, whose largest ID is 9",
  )
  // A container's annotations come before its children.
  let annotation_first = @ion.IonValue::list([
    @ion.IonValue::symbol_token(sid(50)),
  ]).with_annotation(sid(60))
  inspect(
    resolve_error(annotation_first),
    content="symbol ID $60 is beyond the symbol table, whose largest ID is 9",
  )
}

///|
test "resolve names the first failing annotation, before the symbol value" {
  let sid = @ion.SymbolToken::from_sid
  let value = @ion.IonValue::symbol_token(sid(30)).with_annotations([
    sid(40),
    sid(50),
  ])
  inspect(
    resolve_error(value),
    content="symbol ID $40 is beyond the symbol table, whose largest ID is 9",
  )
}

///|
test "resolve gives text to IDs at every depth and keeps other tokens" {
  let sid = @ion.SymbolToken::from_sid
  let value = @ion.IonValue::from_fields([
    @ion.Field::from_token(
      sid(4),
      @ion.IonValue::list([@ion.IonValue::symbol_token(sid(5))]),
    ),
    @ion.Field::new("plain", @ion.IonValue::symbol_token(sid(0))),
  ])
  inspect(
    @text.write_ion(@ion.SymbolTable::system().resolve(value)),
    content="{name: [version], plain: $0}",
  )
}

///|
test "localize_for_text gives each unknown imported symbol this context's ID" {
  let shared = @ion.SymbolToken::from_import(10, "shared", 1, 1)
  let value = @ion.IonValue::from_fields([
    @ion.Field::from_token(
      shared,
      @ion.IonValue::list([@ion.IonValue::symbol_token(shared)]),
    ),
  ])
  let table = @ion.SymbolTable::for_values([value])
  // Check the tokens, not the text: a writer would put a symbol table first.
  guard table.localize_for_text(value).kind() is Struct([field]) else {
    fail("expected a struct with one field")
  }
  assert_eq(field.name().sid(), Some(10))
  assert_true(field.name().text() is None)
  assert_true(
    field.value().kind() is List([item]) &&
    item.kind() is Symbol(token) &&
    token.sid() == Some(10),
  )
}
