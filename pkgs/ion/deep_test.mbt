// Walkers handle values nested far deeper than any reader accepts. Each test
// builds a value 100,000 containers deep with a loop and checks the result
// without a recursive walker. A test that still overflows the call stack is
// skipped until the port that fixes it lands (epic ion-dql).

///|
let deep : Int = 100_000

///|
let shapes : Array[@testkit.DeepShape] = [
  List,
  Sexp,
  Struct,
  AnnotatedList,
  Mixed,
]

///|
#skip("ion-dql.3: IonValue::equals recurses once per level")
test "equals compares values 100,000 levels deep" {
  for shape in shapes {
    let a = @testkit.deep_value(shape, deep)
    assert_true(a.equals(@testkit.deep_value(shape, deep)))
    assert_true(
      !a.equals(@testkit.deep_value(shape, deep, leaf=@ion.IonValue::int(2))),
    )
  }
}

///|
test "fold visits every value 100,000 levels deep" {
  for shape in shapes {
    let count = @testkit.deep_value(shape, deep).fold(0, {
      ..@ion.IonFold::default(),
      visit_value: (count, _) => Continue(count + 1),
    })
    assert_eq(count, deep + 1)
  }
}

///|
test "the visitor visits every value 100,000 levels deep" {
  for shape in shapes {
    let counter : ValueCounter = { count: 0, }
    @testkit.deep_value(shape, deep).accept(counter)
    assert_eq(counter.count, deep + 1)
  }
}

///|
test "has_imported_symbols finds a symbol 100,000 levels deep" {
  let leaf = @ion.IonValue::symbol_token(
    @ion.SymbolToken::from_import(10, "shared", 1, 1),
  )
  for shape in shapes {
    assert_true(@testkit.deep_value(shape, deep, leaf~).has_imported_symbols())
  }
}

///|
#skip("ion-dql.4: value_highest_symbol_id recurses once per level")
test "highest_symbol_id finds an ID 100,000 levels deep" {
  let leaf = @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(12))
  for shape in shapes {
    assert_eq(
      @ion.highest_symbol_id([@testkit.deep_value(shape, deep, leaf~)]),
      12,
    )
  }
}

///|
#skip("ion-dql.4: SymbolTable::resolve recurses once per level")
test "resolve gives text to a symbol 100,000 levels deep" {
  let leaf = @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(4))
  for shape in shapes {
    let resolved = @ion.SymbolTable::system().resolve(
      @testkit.deep_value(shape, deep, leaf~),
    )
    let (inner, depth) = @testkit.innermost(resolved)
    assert_eq(depth, deep)
    assert_true(inner.kind() is Symbol(token) && token.text() == Some("name"))
  }
}

///|
#skip("ion-dql.4: collect_writer_tokens recurses once per level")
test "for_values interns a symbol 100,000 levels deep" {
  let leaf = @ion.IonValue::symbol("zzz")
  for shape in shapes {
    let table = @ion.SymbolTable::for_values([
      @testkit.deep_value(shape, deep, leaf~),
    ])
    assert_eq(table.find("zzz"), Some(10))
  }
}

///|
#skip("ion-dql.4: localize_for_text recurses once per level")
test "localize_for_text rewrites a symbol 100,000 levels deep" {
  let leaf = @ion.IonValue::symbol_token(
    @ion.SymbolToken::from_import(10, "shared", 1, 1),
  )
  for shape in shapes {
    let value = @testkit.deep_value(shape, deep, leaf~)
    let table = @ion.SymbolTable::for_values([value])
    let (inner, depth) = @testkit.innermost(table.localize_for_text(value))
    assert_eq(depth, deep)
    assert_true(
      inner.kind() is Symbol(token) &&
      token.text() is None &&
      token.sid() == Some(10),
    )
  }
}
