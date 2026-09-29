// Tests for the Ion Schema Cookbook examples vendored in `tests/fixtures`
// (<https://amazon-ion.github.io/ion-schema/docs/cookbook/>): the pages
// "Expressing logical relationships between fields", "Modeling SQL decimals",
// "Optionally ignoring the occurs requirement for fields", and "Versioned
// types". Each test checks the values the page gives as valid and invalid.
// The `accepts` helper is shared with schema_test.mbt.

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

///|
/// A Cookbook schema from `tests/fixtures`.
fn fixture(name : String) -> String raise {
  @fs.read_file_to_string("tests/fixtures/cookbook-\{name}.isl")
}

///|
test "sql-decimals: the three ways to model DECIMAL(5,2)" {
  let schema = fixture("sql-decimals")
  assert_true(accepts(schema, "exact_precision_and_scale", "123.45"))
  // The page's own example: exact precision rejects 1.00.
  assert_true(!accepts(schema, "exact_precision_and_scale", "1.00"))
  for text in ["100.00", "1.50", "0.01"] {
    assert_true(
      accepts(schema, "compatible_precision_exact_scale", text),
      msg=text,
    )
  }
  for text in ["100", "1.5", "0.010", "1000.0"] {
    assert_true(
      !accepts(schema, "compatible_precision_exact_scale", text),
      msg=text,
    )
  }
  // The page also lists `500` as accepted; `exponent` applies only to
  // decimals, so the int 500 is not, and the decimal `500.` is.
  for text in ["1.5", "1.50", "5d2", "500."] {
    assert_true(accepts(schema, "fits_decimal_5_2", text), msg=text)
  }
  for text in ["1200.", "1.2d5", "1.501", "1.500", "500"] {
    assert_true(!accepts(schema, "fits_decimal_5_2", text), msg=text)
  }
}

///|
test "ignore-occurs-requirements: field types with and without occurs" {
  let schema = fixture("ignore-occurs")
  let partial = "{ firstName: \"Ada\", title: \"Dr.\" }"
  let full =
    #|{ firstName: "Ada", lastName: "Lovelace", customerId: 123456,
    #|  addresses: [{ street: "1 Main", city: "London" }],
    #|  lastUpdated: 2024-01-01T12:00:00Z }
  assert_true(accepts(schema, "CustomerFieldTypes", partial))
  assert_true(!accepts(schema, "Customer", partial))
  assert_true(accepts(schema, "Customer", full))
  assert_true(!accepts(schema, "CustomerFieldTypes", "{ title: \"Sir\" }"))
  assert_true(!accepts(schema, "CustomerFieldTypes", "{ nickname: \"A\" }"))
  assert_true(!accepts(schema, "CustomerFieldTypes", "{ customerId: 12 }"))
  assert_true(
    !accepts(schema, "CustomerFieldTypes", "{ lastUpdated: 2024-01-01T12:00Z }"),
  )
}

///|
test "versioned-types: the page's valid and invalid examples" {
  let schema = fixture("versioned-types")
  let cases = [
    ("Widget", "{ version: 1, name: \"sprocket\" }", true),
    ("Widget", "{ version: 2, name: \"gear\", color: \"red\" }", true),
    (
      "Widget", "{ version: 3, name: \"bolt\", color: \"zinc\", weight: 4.5, dimensions: \"M8x30\" }",
      true,
    ),
    ("Widget", "{ version: 2, name: \"washer\" }", true),
    ("Widget", "{ version: 1, name: \"sprocket\", color: \"blue\" }", false),
    ("Widget", "{ version: 2, name: \"gear\", weight: 1.2 }", false),
    ("Widget", "{ version: 2, name: \"bolt\", dimensions: \"M6x20\" }", false),
    (
      "ApiResponse", "{ version: 1, request_id: 42, status: \"ok\", payload: {} }",
      true,
    ),
    (
      "ApiResponse", "{ version: 2, request_id: \"abc-123\", status: \"ok\", payload: {}, metadata: { trace_id: \"x\" } }",
      true,
    ),
    (
      "ApiResponse", "{ version: 3, request_id: \"def-456\", status: \"ok\", payload: {}, metadata: { trace_id: \"y\" }, priority: high }",
      true,
    ),
    (
      "ApiResponse", "{ version: 4, request_id: \"ghi-789\", status: \"ok\", payload: {}, priority: critical }",
      true,
    ),
    (
      "ApiResponse", "{ version: 1, request_id: \"bad\", status: \"ok\", payload: {} }",
      false,
    ),
    (
      "ApiResponse", "{ version: 4, request_id: \"x\", status: \"ok\", payload: {}, metadata: {} }",
      false,
    ),
    (
      "ApiResponse", "{ version: 3, request_id: \"x\", status: \"ok\", payload: {}, priority: critical }",
      false,
    ),
    ("WidgetStrict", "{ version: 1, name: \"a\" }", true),
    ("WidgetStrict", "{ version: 2, name: \"a\", color: \"red\" }", true),
    ("WidgetStrict", "{ version: 2, name: \"a\" }", false),
    ("WidgetStrict", "{ version: 1, name: \"a\", color: \"red\" }", false),
    ("ThreeStateExample", "{ version: 1, name: \"a\" }", true),
    ("ThreeStateExample", "{ version: 2, name: \"a\" }", true),
    ("ThreeStateExample", "{ version: 2, name: \"a\", email: \"e\" }", true),
    ("ThreeStateExample", "{ version: 1, name: \"a\", email: \"e\" }", false),
    ("ThreeStateExample", "{ version: 3, name: \"a\" }", false),
    (
      "ShoppingCart", "{ version: 1, cart_id: \"cart-001\", items: [{ version: 1, product_id: \"SKU-A\", quantity: 2 }, { version: 2, product_id: \"SKU-B\", quantity: 1, unit_price: 9.99 }] }",
      true,
    ),
    (
      "ShoppingCart", "{ version: 2, cart_id: \"cart-002\", coupon_code: \"SAVE10\", shipping_estimate: 2025-03-15T, items: [{ version: 3, product_id: \"SKU-C\", quantity: 1, unit_price: 24.99, discount: 2.50 }] }",
      true,
    ),
    (
      "ShoppingCart", "{ version: 1, cart_id: \"cart-003\", coupon_code: \"OOPS\", items: [] }",
      false,
    ),
    (
      "ShoppingCart", "{ version: 2, cart_id: \"cart-004\", items: [{ version: 1, product_id: \"SKU-D\", quantity: 1, unit_price: 5.00 }] }",
      false,
    ),
  ]
  for case in cases {
    let (type_name, value, valid) = case
    assert_eq(
      accepts(schema, type_name, value),
      valid,
      msg="\{type_name} \{value}",
    )
  }
}
