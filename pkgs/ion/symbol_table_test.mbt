// Black-box tests for the symbol table that the text and binary readers
// share.

///|
/// A local symbol table value: `$ion_symbol_table::{...}` with `fields`.
fn local_table(fields : Array[@ion.Field]) -> @ion.IonValue {
  @ion.IonValue::from_fields(fields).with_annotations([
    @ion.SymbolToken::new("$ion_symbol_table"),
  ])
}

///|
/// A list of strings, as a `symbols` field declares them.
fn texts(items : Array[String]) -> @ion.IonValue {
  @ion.IonValue::list(items.map(@ion.IonValue::string))
}

///|
/// A symbol value known only by its ID.
fn sid(id : Int) -> @ion.IonValue {
  @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(id))
}

///|
test "the system table resolves the system symbols only" {
  let table = @ion.SymbolTable::system()
  assert_eq(table.text(1), Some("$ion"))
  assert_eq(table.text(9), Some("$ion_shared_symbol_table"))
  assert_eq(table.text(0), None)
  assert_eq(table.text(10), None)
  assert_eq(table.max_id(), 9)
  assert_eq(table.token(10).sid(), Some(10))
}

///|
test "a local symbol table declares symbols from ID 10" {
  let table = @ion.SymbolTable::system()
  let value = local_table([@ion.Field::new("symbols", texts(["a", "b"]))])
  assert_true(table.apply_local_symbol_table(value))
  assert_eq(table.text(10), Some("a"))
  assert_eq(table.text(11), Some("b"))
  assert_eq(table.max_id(), 11)
}

///|
test "a new local symbol table replaces the local symbols" {
  let table = @ion.SymbolTable::system()
  ignore(
    table.apply_local_symbol_table(
      local_table([@ion.Field::new("symbols", texts(["a"]))]),
    ),
  )
  ignore(
    table.apply_local_symbol_table(
      local_table([@ion.Field::new("symbols", texts(["b"]))]),
    ),
  )
  assert_eq(table.text(10), Some("b"))
  assert_eq(table.max_id(), 10)
}

///|
test "importing the current table appends to it" {
  let table = @ion.SymbolTable::system()
  ignore(
    table.apply_local_symbol_table(
      local_table([@ion.Field::new("symbols", texts(["a"]))]),
    ),
  )
  let append = local_table([
    @ion.Field::new("imports", @ion.IonValue::symbol("$ion_symbol_table")),
    @ion.Field::new("symbols", texts(["b"])),
  ])
  assert_true(table.apply_local_symbol_table(append))
  assert_eq(table.text(10), Some("a"))
  assert_eq(table.text(11), Some("b"))
}

///|
test "a slot that is not a string has unknown text" {
  let table = @ion.SymbolTable::system()
  let symbols = @ion.IonValue::list([
    @ion.IonValue::string("a"),
    @ion.IonValue::untyped_null(),
    @ion.IonValue::int(1),
    @ion.IonValue::string("d"),
  ])
  ignore(
    table.apply_local_symbol_table(
      local_table([@ion.Field::new("symbols", symbols)]),
    ),
  )
  assert_eq(table.text(11), None)
  assert_eq(table.text(12), None)
  assert_eq(table.text(13), Some("d"))
  assert_eq(table.max_id(), 13)
}

///|
test "a symbols field that is not a list declares nothing" {
  let table = @ion.SymbolTable::system()
  let value = local_table([
    @ion.Field::new("symbols", @ion.IonValue::string("a")),
  ])
  assert_true(table.apply_local_symbol_table(value))
  assert_eq(table.max_id(), 9)
}

///|
test "only a struct whose first annotation is $ion_symbol_table is a table" {
  let table = @ion.SymbolTable::system()
  let second = @ion.IonValue::from_fields([
    @ion.Field::new("symbols", texts(["a"])),
  ]).with_annotations([
    @ion.SymbolToken::new("x"),
    @ion.SymbolToken::new("$ion_symbol_table"),
  ])
  assert_false(table.apply_local_symbol_table(second))
  let list = @ion.IonValue::list([]).with_annotations([
    @ion.SymbolToken::new("$ion_symbol_table"),
  ])
  assert_false(table.apply_local_symbol_table(list))
  assert_false(table.apply_local_symbol_table(@ion.IonValue::symbol("a")))
  assert_eq(table.max_id(), 9)
}

///|
test "shared symbol table imports are reported as unsupported" {
  let table = @ion.SymbolTable::system()
  let import_ = @ion.IonValue::from_fields([
    @ion.Field::new("name", @ion.IonValue::string("shared")),
    @ion.Field::new("version", @ion.IonValue::int(1)),
  ])
  let value = local_table([
    @ion.Field::new("imports", @ion.IonValue::list([import_])),
  ])
  let mut unsupported = false
  ignore(
    table.apply_local_symbol_table(value) catch {
      @ion.IonError::Unsupported(_) => {
        unsupported = true
        false
      }
      _ => false
    },
  )
  assert_true(unsupported)
}

///|
test "a table with two symbols fields is malformed" {
  let table = @ion.SymbolTable::system()
  let value = local_table([
    @ion.Field::new("symbols", texts(["a"])),
    @ion.Field::new("symbols", texts(["b"])),
  ])
  let mut failed = false
  ignore(
    table.apply_local_symbol_table(value) catch {
      _ => {
        failed = true
        false
      }
    },
  )
  assert_true(failed)
}

///|
test "resolving gives text to every symbol ID the table defines" {
  let table = @ion.SymbolTable::system()
  ignore(
    table.apply_local_symbol_table(
      local_table([@ion.Field::new("symbols", texts(["a", "b"]))]),
    ),
  )
  let value = @ion.IonValue::from_fields([
    @ion.Field::from_token(@ion.SymbolToken::from_sid(10), sid(11)),
    @ion.Field::new("list", @ion.IonValue::list([sid(10), sid(12), sid(0)])),
    @ion.Field::new("sexp", @ion.IonValue::sexp([sid(11)])),
  ]).with_annotations([@ion.SymbolToken::from_sid(11)])
  let expected = @ion.IonValue::from_fields([
    @ion.Field::new("a", @ion.IonValue::symbol("b")),
    @ion.Field::new(
      "list",
      @ion.IonValue::list([@ion.IonValue::symbol("a"), sid(12), sid(0)]),
    ),
    @ion.Field::new("sexp", @ion.IonValue::sexp([@ion.IonValue::symbol("b")])),
  ]).with_annotations([@ion.SymbolToken::new("b")])
  assert_true(table.resolve(value).equals(expected))
}

///|
test "a version marker resets the table to the system symbols" {
  let table = @ion.SymbolTable::system()
  ignore(
    table.apply_local_symbol_table(
      local_table([@ion.Field::new("symbols", texts(["a"]))]),
    ),
  )
  table.reset()
  assert_eq(table.text(10), None)
  assert_eq(table.max_id(), 9)
}

///|
test "interning reuses system and local IDs" {
  let table = @ion.SymbolTable::system()
  assert_eq(table.intern("name"), 4)
  assert_eq(table.intern("a"), 10)
  assert_eq(table.intern("b"), 11)
  assert_eq(table.intern("a"), 10)
  assert_eq(table.find("b"), Some(11))
  assert_eq(table.find("c"), None)
}
