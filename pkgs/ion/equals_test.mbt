// Equality of Ion values. Struct fields compare as a multiset. The stack-safe
// equals pairs struct fields by name, and falls back to class IDs when names
// repeat and the first pairing differs; these cases check that both paths
// keep the data model's rules at every level.

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

///|
/// `{a: inner, a: 1, a: 2}` around `inner`, `levels` times, with the two
/// numbers in the order `first`, `second`.
fn repeated_name_chain(
  levels : Int,
  first : Int,
  second : Int,
) -> @ion.IonValue {
  let mut value = @ion.IonValue::int(0)
  for _ in 0..<levels {
    value = @ion.IonValue::from_fields([
      @ion.Field::new("a", value),
      @ion.Field::new("a", @ion.IonValue::int(first)),
      @ion.Field::new("a", @ion.IonValue::int(second)),
    ])
  }
  value
}

///|
test "repeated field names at every level of 100,000 compare in linear time" {
  // Every level has repeated names and pairs wrongly at first, so a
  // fallback per level would cost quadratic time.
  let left = repeated_name_chain(100_000, 1, 2)
  assert_true(left.equals(repeated_name_chain(100_000, 2, 1)))
  assert_true(!left.equals(repeated_name_chain(100_000, 2, 2)))
}

///|
/// `{a: x, a: 0}` against `{a: 0, a: y}`: the names repeat and the first
/// pairing differs, so `x` and `y` compare through class IDs.
fn same_by_class(x : String, y : String) -> Bool raise {
  same("{a: \{x}, a: 0}", "{a: 0, a: \{y}}")
}

///|
test "class IDs keep the rules of equals for scalars" {
  assert_true(same_by_class("nan", "nan"))
  assert_true(!same_by_class("0e0", "-0e0"))
  assert_true(!same_by_class("0d0", "-0d0"))
  assert_true(!same_by_class("1.0", "1.00"))
  assert_true(!same_by_class("2026T", "2026-01T"))
  assert_true(!same_by_class("null.list", "[]"))
  assert_true(!same_by_class("\"a\"", "a"))
  assert_true(!same_by_class("{{ \"a\" }}", "{{ YQ== }}"))
  assert_true(same_by_class("2026-10-08T00:00Z", "2026-10-08T00:00Z"))
}

///|
test "class IDs keep annotations, container kinds and field order rules" {
  assert_true(!same_by_class("x::1", "y::1"))
  assert_true(!same_by_class("x::y::1", "y::x::1"))
  assert_true(!same_by_class("[1]", "(1)"))
  assert_true(same_by_class("{b: 1, c: 2}", "{c: 2, b: 1}"))
  assert_true(!same_by_class("{b: 1}", "{c: 1}"))
}

///|
test "class IDs of container children do not run together" {
  // Twelve integers take class IDs 0 to 11, so `[1, 2]` has children 1 and
  // 2, and `[[1, 2]]` has one child whose ID is 12.
  let numbers = "a: 0, a: 1, a: 2, a: 3, a: 4, a: 5, a: 6, a: 7, a: 8, a: 9, a: 10, a: 11"
  assert_true(!same("{\{numbers}, b: [1, 2]}", "{\{numbers}, b: [[1, 2]]}"))
}

///|
test "class IDs compare field names by symbol equivalence" {
  let unknown = @ion.SymbolToken::from_sid(0)
  let numbered = @ion.SymbolToken::from_sid(12)
  let imported = @ion.SymbolToken::from_import(10, "shared", 1, 1)
  let zero = @ion.IonValue::int(0)
  let one = @ion.IonValue::int(1)
  let left = @ion.IonValue::from_fields([
    @ion.Field::new(
      "a",
      @ion.IonValue::from_fields([@ion.Field::from_token(unknown, one)]),
    ),
    @ion.Field::new("a", zero),
  ])
  let right_numbered = @ion.IonValue::from_fields([
    @ion.Field::new("a", zero),
    @ion.Field::new(
      "a",
      @ion.IonValue::from_fields([@ion.Field::from_token(numbered, one)]),
    ),
  ])
  let right_imported = @ion.IonValue::from_fields([
    @ion.Field::new("a", zero),
    @ion.Field::new(
      "a",
      @ion.IonValue::from_fields([@ion.Field::from_token(imported, one)]),
    ),
  ])
  assert_true(left.equals(right_numbered))
  assert_true(!left.equals(right_imported))
}
