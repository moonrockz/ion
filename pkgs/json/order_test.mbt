// to_json raises for the first symbol with no text in document order: a
// field name before its value, and an earlier field before a later one.

///|
fn json_error(value : @core.IonValue) -> String {
  try @json.to_json(value) catch {
    error => error.message()
  } noraise {
    _ => "converted"
  }
}

///|
test "to_json names the first symbol with no text in document order" {
  let sid = @core.SymbolToken::from_sid
  let value = @core.IonValue::from_fields([
    @core.Field::from_token(
      sid(20),
      @core.IonValue::list([@core.IonValue::symbol_token(sid(30))]),
    ),
    @core.Field::new("later", @core.IonValue::symbol_token(sid(40))),
  ])
  inspect(
    json_error(value),
    content="a symbol known only by symbol ID 20 has no text to convert to JSON",
  )
}

///|
test "a repeated field name keeps the last value in the first position" {
  let value = @text.read_ion("{a: [1], b: 2, a: {c: 3}}")
  inspect(@json.to_json(value).stringify(), content="{\"a\":{\"c\":3},\"b\":2}")
}

///|
test "to_json keeps document order when the first error is far deeper" {
  let sid = @core.SymbolToken::from_sid
  let mut inner = @core.IonValue::symbol_token(sid(20))
  for _ in 0..<300 {
    inner = @core.IonValue::list([inner])
  }
  let value = @core.IonValue::list([
    inner,
    @core.IonValue::symbol_token(sid(40)),
  ])
  inspect(
    json_error(value),
    content="a symbol known only by symbol ID 20 has no text to convert to JSON",
  )
}

///|
test "to_json converts every level of a value nested past any fixed depth" {
  for depth in [1, 63, 64, 65, 128, 129, 300] {
    let mut value = @core.IonValue::int(7)
    for _ in 0..<depth {
      value = @core.IonValue::from_fields([@core.Field::new("a", value)])
      value = @core.IonValue::list([value])
    }
    let mut expected = "7"
    for _ in 0..<depth {
      expected = "[{\"a\":" + expected + "}]"
    }
    assert_eq(@json.to_json(value).stringify(), expected)
  }
}

///|
test "to_ion keeps field order and every level past any fixed depth" {
  for depth in [1, 63, 64, 65, 128, 129, 300] {
    let mut json = Json::number(7.0)
    for _ in 0..<depth {
      json = Json::array([Json::object(Map([("b", Json::null()), ("a", json)]))])
    }
    let mut expected = "7"
    for _ in 0..<depth {
      expected = "[{b: null, a: " + expected + "}]"
    }
    assert_eq(@text.write_ion(@json.to_ion(json)), expected)
  }
}
