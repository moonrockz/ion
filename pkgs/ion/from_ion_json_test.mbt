// Decoding core `Json` from Ion follows the documented down-conversion to
// JSON. It fails only for a symbol, or a field name, with no known text.

///|
test "Json reads Ion through the down-conversion rules" {
  let value = @text.read_ion(
    "a::{n: 1.50, s: sym, z: null.int, t: 2024-01-02T, l: (1 2), f: nan}",
  )
  let json : Json = @ion.FromIon::from_ion(value)
  assert_eq(
    json.stringify(),
    "{\"n\":1.50,\"s\":\"sym\",\"z\":null,\"t\":\"2024-01-02\",\"l\":[1,2],\"f\":null}",
  )
}

///|
test "Json names the path of a symbol value with no text" {
  let value = @ion.Ion::list([
    @ion.Ion::symbol("a"),
    @ion.Ion(@ion.SymbolToken::from_sid(99)),
  ])
  let error = try (@ion.FromIon::from_ion(value) : Json) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  guard error is MissingSymbolText(path=[Index(1)], token~) else {
    fail("expected MissingSymbolText at [1], got \{error.message()}")
  }
  assert_eq(token.sid(), Some(99))
  assert_eq(error.message(), "$[1]: symbol $99 has no known text")
}

///|
test "Json names the struct of a field name with no text" {
  let inner = @ion.Ion::from_fields([
    @ion.Field::from_token(@ion.SymbolToken::from_sid(99), @ion.Ion(1)),
  ])
  let value = @ion.Ion::from_fields([@ion.Field("x", inner)])
  let error = try (@ion.FromIon::from_ion(value) : Json) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is MissingSymbolText(path=[Name("x")], ..))
}

///|
test "Json resolves an Ion 1.0 system symbol ID to its text" {
  let value = @ion.Ion(@ion.SymbolToken::from_sid(4))
  let json : Json = @ion.FromIon::from_ion(value)
  assert_eq(json, Json::string("name"))
}

///|
test "Json names the path of a symbol with no text at any depth" {
  let depth = 100000
  let mut value = @ion.Ion(@ion.SymbolToken::from_sid(99))
  for _ in 0..<depth {
    value = @ion.Ion::list([value])
  }
  let error = try (@ion.FromIon::from_ion(value) : Json) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_eq(error.path().length(), depth)
  assert_true(error.path().iter().all(segment => segment == Index(0)))
}
