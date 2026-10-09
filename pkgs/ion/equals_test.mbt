// Equality of Ion values. Struct fields compare as a multiset; the stack-safe
// equals gives every struct field value a class ID, so these cases check that
// the IDs keep the data model's rules at every level.

///|
fn same(a : String, b : String) -> Bool raise {
  @text.read_ion(a).equals(@text.read_ion(b))
}

///|
test "struct fields compare as a multiset" {
  assert_true(same("{a: 1, a: 2}", "{a: 2, a: 1}"))
  assert_true(!same("{a: 1, a: 1}", "{a: 1, a: 2}"))
  assert_true(!same("{a: 1}", "{a: 1, a: 1}"))
}

///|
test "nested structs compare regardless of field order at every level" {
  assert_true(
    same(
      "{a: {b: 1, c: [2, {d: 3, e: 4}]}}", "{a: {c: [2, {e: 4, d: 3}], b: 1}}",
    ),
  )
  assert_true(
    !same("{a: {b: 1, c: [2, {d: 3}]}}", "{a: {c: [2, {d: 4}], b: 1}}"),
  )
}

///|
test "a struct inside a list compares its fields as a multiset" {
  assert_true(same("[{a: 1, b: 2}]", "[{b: 2, a: 1}]"))
}

///|
test "special numbers keep their rules inside struct fields" {
  assert_true(same("{a: nan}", "{a: nan}"))
  assert_true(!same("{a: 0e0}", "{a: -0e0}"))
  assert_true(!same("{a: 0d0}", "{a: -0d0}"))
  assert_true(!same("{a: 1.0}", "{a: 1.00}"))
  assert_true(!same("{a: 2026T}", "{a: 2026-01T}"))
}

///|
test "annotations count inside struct fields" {
  assert_true(!same("{a: x::1}", "{a: y::1}"))
  assert_true(!same("{a: x::y::1}", "{a: y::x::1}"))
  assert_true(same("{a: x::{b: 1, c: 2}}", "{a: x::{c: 2, b: 1}}"))
}

///|
test "field names compare by symbol equivalence" {
  let unknown = @ion.SymbolToken::from_sid(0)
  let numbered = @ion.SymbolToken::from_sid(12)
  let a = @ion.IonValue::from_fields([
    @ion.Field::from_token(unknown, @ion.IonValue::int(1)),
  ])
  let b = @ion.IonValue::from_fields([
    @ion.Field::from_token(numbered, @ion.IonValue::int(1)),
  ])
  let c = @ion.IonValue::from_fields([
    @ion.Field::new("a", @ion.IonValue::int(1)),
  ])
  assert_true(a.equals(b))
  assert_true(!a.equals(c))
}

///|
test "separator characters in names and strings do not confuse struct keys" {
  assert_true(!same("{'1:a': 1}", "{a: 1}"))
  assert_true(!same("{a: \"1:b\"}", "{a: \"1\", b: \"\"}"))
  assert_true(!same("{'a=0': 1}", "{a: 1}"))
  assert_true(!same("{a: [1, 2]}", "{a: [12]}"))
}

///|
test "null.list differs from an empty list, and a list from a sexp" {
  assert_true(!same("null.list", "[]"))
  assert_true(!same("[]", "()"))
  assert_true(!same("{a: []}", "{a: ()}"))
}

///|
test "repeated field names match as a multiset when the first pairing differs" {
  assert_true(same("{a: {x: 1}, a: {x: 2}}", "{a: {x: 2}, a: {x: 1}}"))
  assert_true(same("{b: 0, a: [1], a: [2]}", "{a: [2], b: 0, a: [1]}"))
  assert_true(!same("{a: {x: 1}, a: {x: 2}}", "{a: {x: 2}, a: {x: 2}}"))
}

///|
test "repeated field names match as a multiset 100,000 levels deep" {
  let deep = @testkit.deep_value(Mixed, 100_000)
  let one = @ion.IonValue::int(1)
  let a = @ion.IonValue::from_fields([
    @ion.Field::new("a", deep),
    @ion.Field::new("a", one),
  ])
  let b = @ion.IonValue::from_fields([
    @ion.Field::new("a", one),
    @ion.Field::new("a", deep),
  ])
  assert_true(a.equals(b))
  let other = @ion.IonValue::from_fields([
    @ion.Field::new("a", one),
    @ion.Field::new("a", @testkit.deep_value(Mixed, 99_999)),
  ])
  assert_true(!a.equals(other))
}
