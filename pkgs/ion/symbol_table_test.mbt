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
/// An import of the shared table `name`, with `max_id` when given.
fn import_of(name : String, max_id? : Int) -> @ion.IonValue {
  let fields = [
    @ion.Field::new("name", @ion.IonValue::string(name)),
    @ion.Field::new("version", @ion.IonValue::int(1)),
  ]
  if max_id is Some(max_id) {
    fields.push(@ion.Field::new("max_id", @ion.IonValue::int(max_id)))
  }
  @ion.IonValue::from_fields(fields)
}

///|
test "an import reserves max_id symbol IDs with unknown text" {
  let table = @ion.SymbolTable::system()
  let value = local_table([
    @ion.Field::new(
      "imports",
      @ion.IonValue::list([
        import_of("one", max_id=2),
        import_of("$ion", max_id=9),
        import_of("big", max_id=268435444),
      ]),
    ),
    @ion.Field::new("symbols", texts(["a"])),
  ])
  assert_true(table.apply_local_symbol_table(value))
  assert_eq(table.text(10), None)
  assert_eq(table.text(268435455), None)
  assert_eq(table.text(268435456), Some("a"))
  assert_eq(table.max_id(), 268435456)
  assert_eq(table.find("a"), Some(268435456))
}

///|
test "an import without max_id is an error" {
  let table = @ion.SymbolTable::system()
  let value = local_table([
    @ion.Field::new("imports", @ion.IonValue::list([import_of("shared")])),
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
test "resolving gives text to every symbol ID the table defines, and rejects an ID beyond it" {
  let table = @ion.SymbolTable::system()
  ignore(
    table.apply_local_symbol_table(
      local_table([
        @ion.Field::new(
          "symbols",
          @ion.IonValue::list([
            @ion.IonValue::string("a"),
            @ion.IonValue::string("b"),
            @ion.IonValue::untyped_null(),
          ]),
        ),
      ]),
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
  let mut failed = false
  ignore(
    table.resolve(sid(13)) catch {
      _ => {
        failed = true
        sid(0)
      }
    },
  )
  assert_true(failed)
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

///|
test "a table describes itself as a local symbol table" {
  let table = @ion.SymbolTable::system()
  assert_true(table.to_local_symbol_table() is None)
  table.reserve(18)
  ignore(table.intern("a"))
  let copy = @ion.SymbolTable::system()
  assert_true(
    copy.apply_local_symbol_table(table.to_local_symbol_table().unwrap()),
  )
  assert_eq(copy.max_id(), 28)
  assert_eq(copy.text(27), None)
  assert_eq(copy.text(28), Some("a"))
}

///|
test "the highest symbol ID counts only symbols without text" {
  let values = [
    @ion.IonValue::symbol("a"),
    @ion.IonValue::list([sid(27)]).with_annotations([
      @ion.SymbolToken::from_sid(12),
    ]),
  ]
  assert_eq(@ion.highest_symbol_id(values), 27)
  assert_eq(@ion.highest_symbol_id([@ion.IonValue::symbol("a")]), 0)
}

///|
test "a repeated field in an import is malformed" {
  for field in ["name", "version", "max_id"] {
    let fields = [
      @ion.Field::new("name", @ion.IonValue::string("shared")),
      @ion.Field::new("version", @ion.IonValue::int(1)),
      @ion.Field::new("max_id", @ion.IonValue::int(1)),
    ]
    fields.push(
      match field {
        "name" => @ion.Field::new("name", @ion.IonValue::string("shared"))
        _ => @ion.Field::new(field, @ion.IonValue::int(1))
      },
    )
    let value = local_table([
      @ion.Field::new(
        "imports",
        @ion.IonValue::list([@ion.IonValue::from_fields(fields)]),
      ),
    ])
    let table = @ion.SymbolTable::system()
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
}

///|
/// A shared symbol table value, as a catalog file holds them.
fn shared(
  name : String,
  version : Int,
  symbols : Array[@ion.IonValue],
) -> @ion.IonValue {
  @ion.IonValue::from_fields([
    @ion.Field::new("name", @ion.IonValue::string(name)),
    @ion.Field::new("version", @ion.IonValue::int(version)),
    @ion.Field::new("symbols", @ion.IonValue::list(symbols)),
  ]).with_annotations([@ion.SymbolToken::new("$ion_shared_symbol_table")])
}

///|
/// The catalog of ion-tests: `abcs` 1 and 2, and `mnop` 1, 3, and 4, whose
/// first slot is a gap.
fn test_catalog() -> @ion.Catalog raise {
  let s = @ion.IonValue::string
  @ion.Catalog::load([
    shared("abcs", 1, [s("a")]),
    shared("abcs", 2, [s("a"), s("b")]),
    shared("mnop", 1, [s("m")]),
    shared("mnop", 3, [s("m"), s("n"), s("o")]),
    shared("mnop", 4, [@ion.IonValue::symbol("absent"), s("n"), s("o"), s("p")]),
  ])
}

///|
/// A table that has applied a local symbol table importing `imports`.
fn importing(imports : Array[@ion.IonValue]) -> @ion.SymbolTable raise {
  let table = @ion.SymbolTable::system(catalog=test_catalog())
  ignore(
    table.apply_local_symbol_table(
      local_table([@ion.Field::new("imports", @ion.IonValue::list(imports))]),
    ),
  )
  table
}

///|
/// An import of `name`, with a version and a max_id when given.
fn import_entry(name : String, version? : Int, max_id? : Int) -> @ion.IonValue {
  let fields = [@ion.Field::new("name", @ion.IonValue::string(name))]
  if version is Some(version) {
    fields.push(@ion.Field::new("version", @ion.IonValue::int(version)))
  }
  if max_id is Some(max_id) {
    fields.push(@ion.Field::new("max_id", @ion.IonValue::int(max_id)))
  }
  @ion.IonValue::from_fields(fields)
}

///|
test "a catalog finds a shared table by name and version" {
  let catalog = test_catalog()
  assert_eq(
    catalog.find("abcs", 2).map(table => table.symbols()),
    Some([Some("a"), Some("b")]),
  )
  assert_true(catalog.find("mnop", 2) is None)
  assert_eq(catalog.latest("mnop").map(table => table.version()), Some(4))
  assert_eq(
    catalog.find("mnop", 4).map(table => table.symbols()[0]),
    Some(None),
  )
}

///|
test "an exact import gives its symbols their text" {
  let table = importing([import_entry("abcs", version=2)])
  assert_eq(table.text(10), Some("a"))
  assert_eq(table.text(11), Some("b"))
  assert_eq(table.max_id(), 11)
  // The version defaults to 1.
  let first = importing([import_entry("abcs")])
  assert_eq(first.text(10), Some("a"))
  assert_eq(first.max_id(), 10)
}

///|
test "max_id truncates or pads an import" {
  let truncated = importing([import_entry("abcs", version=2, max_id=1)])
  assert_eq(truncated.max_id(), 10)
  let padded = importing([
    import_entry("abcs", version=1, max_id=3),
    import_entry("mnop", version=1),
  ])
  assert_eq(padded.text(10), Some("a"))
  assert_eq(padded.text(11), None)
  assert_eq(padded.text(12), None)
  assert_eq(padded.text(13), Some("m"))
}

///|
test "without an exact match, max_id picks the latest version" {
  // mnop 2 is missing, so mnop 4 is used, truncated to 2: a gap, then "n".
  let table = importing([
    import_entry("mnop", version=2, max_id=2),
    import_entry("abcs"),
  ])
  assert_eq(table.text(10), None)
  assert_eq(table.text(11), Some("n"))
  assert_eq(table.text(12), Some("a"))
  // A table missing from the catalog reserves max_id unknown symbols.
  let absent = importing([
    import_entry("absent", max_id=2),
    import_entry("abcs"),
  ])
  assert_eq(absent.text(12), Some("a"))
}

///|
test "without an exact match or a max_id, an import is an error" {
  let mut failed = false
  ignore(
    importing([import_entry("mnop", version=2)]) catch {
      _ => {
        failed = true
        @ion.SymbolTable::system()
      }
    },
  )
  assert_true(failed)
}

///|
test "a table describes its imports when written back" {
  let table = importing([
    import_entry("abcs", version=2),
    import_entry("nowhere", max_id=3),
  ])
  ignore(table.intern("z"))
  let copy = @ion.SymbolTable::system(catalog=test_catalog())
  assert_true(
    copy.apply_local_symbol_table(table.to_local_symbol_table().unwrap()),
  )
  assert_eq(copy.max_id(), table.max_id())
  for sid in 10..<=table.max_id() {
    assert_eq(copy.text(sid), table.text(sid))
  }
}
