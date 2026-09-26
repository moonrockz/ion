// Tests for the Ion Schema Cookbook example vendored in
// `tests/fixtures/cookbook-logical-relationships.isl`
// (<https://amazon-ion.github.io/ion-schema/docs/cookbook/>).
//
// These exercise `any_of`, `nothing`, and `contains`, which the Cookbook uses
// to encode propositional logic over fields and elements. The `accepts` helper
// is shared with schema_test.mbt.

///|
/// The Cookbook schema text, read from `tests/fixtures` (the module root,
/// where `moon test` runs).
fn cookbook_text() -> String raise {
  @fs.read_file_to_string("tests/fixtures/cookbook-logical-relationships.isl")
}

///|
test "fields type accepts every listed field and rejects a wrong type" {
  let schema = cookbook_text()
  assert_true(accepts(schema, "Address", "{}"))
  assert_true(
    accepts(
      schema, "Address", "{country: \"US\", street: \"1 Main\", zip: 12345, state: \"CA\"}",
    ),
  )
  assert_true(!accepts(schema, "Address", "{zip: \"zip\"}"))
}

///|
test "any_of and nothing express propositional logic" {
  let schema = cookbook_text()
  // A v B
  assert_true(!accepts(schema, "a_or_b", "{}"))
  assert_true(accepts(schema, "a_or_b", "{a: 1}"))
  assert_true(accepts(schema, "a_or_b", "{b: 1}"))
  // A -> B, equivalent to A' v B
  assert_true(accepts(schema, "a_implies_b", "{}"))
  assert_true(accepts(schema, "a_implies_b", "{b: 1}"))
  assert_true(!accepts(schema, "a_implies_b", "{a: 1}"))
  // A -> B'
  assert_true(accepts(schema, "a_implies_not_b", "{}"))
  assert_true(accepts(schema, "a_implies_not_b", "{a: 1}"))
  assert_true(!accepts(schema, "a_implies_not_b", "{a: 1, b: 2}"))
  // A <-> B
  assert_true(accepts(schema, "a_iff_b", "{}"))
  assert_true(accepts(schema, "a_iff_b", "{a: 1, b: 2}"))
  assert_true(!accepts(schema, "a_iff_b", "{a: 1}"))
  // A xor B
  assert_true(accepts(schema, "a_xor_b", "{a: 1}"))
  assert_true(accepts(schema, "a_xor_b", "{b: 1}"))
  assert_true(!accepts(schema, "a_xor_b", "{}"))
  assert_true(!accepts(schema, "a_xor_b", "{a: 1, b: 2}"))
}

///|
test "contains requires a matching value" {
  let schema = cookbook_text()
  // (contains A) -> (contains B), for the symbol values A and B
  assert_true(accepts(schema, "contains_a_implies_contains_b", "[]"))
  assert_true(accepts(schema, "contains_a_implies_contains_b", "[B]"))
  assert_true(!accepts(schema, "contains_a_implies_contains_b", "[A]"))
  assert_true(accepts(schema, "contains_a_implies_contains_b", "[A, B]"))
}
