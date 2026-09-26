// Black-box tests for the Ion concrete syntax tree.

///|
test "cst keeps annotation tokens and spans" {
  let text = "int32::12"
  let doc = @text.parse_cst(text)
  let value = doc.values()[0]
  assert_eq(value.annotations().length(), 1)
  assert_eq(value.slice(text).to_owned(), "int32::12")
  match value.content() {
    @text.CstContent::Scalar(token) =>
      assert_true(token.kind() is @text.IonTokenKind::Int(_))
    _ => fail("expected a scalar")
  }
}

///|
test "cst nests containers and records field names" {
  let text = "{a: 1, b: [x]}"
  let doc = @text.parse_cst(text)
  let root = doc.values()[0]
  assert_eq(root.slice(text).to_owned(), text)
  assert_eq(root.elements().unwrap().length(), 2)
  match root.content() {
    @text.CstContent::Struct(fields) => {
      assert_eq(fields.length(), 2)
      assert_eq(fields[0].field_name().unwrap().slice(text).to_owned(), "a")
      assert_eq(fields[1].field_name().unwrap().slice(text).to_owned(), "b")
      match fields[1].content() {
        @text.CstContent::List(items) => {
          assert_eq(items.length(), 1)
          assert_eq(items[0].slice(text).to_owned(), "x")
        }
        _ => fail("expected a list")
      }
    }
    _ => fail("expected a struct")
  }
}

///|
test "cst parses a datagram of values" {
  let doc = @text.parse_cst("1 2 3")
  assert_eq(doc.values().length(), 3)
}
