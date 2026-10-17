///|
test "Ion constructor keeps the kind without annotations" {
  let value = @ion.Ion(@ion.IonValueKind::Bool(true))
  assert_true(value.kind() is Bool(true))
  assert_true(value.annotations().is_empty())
}

///|
test "named Field constructor preserves its components" {
  let value = @ion.IonValue::int(7)
  let field = @ion.Field("count", value)
  assert_eq(field.name().text(), Some("count"))
  assert_true(field.value().equals(value))
}

///|
test "named Decimal constructor preserves its components" {
  let coefficient = @ion.Decimal::from_int(123).coefficient()
  let value = @ion.Decimal::Decimal(coefficient, -2)
  assert_eq(value.to_ion_string(), "1.23")
}

///|
test "named Timestamp constructor preserves its components" {
  let value = @ion.Timestamp::Timestamp(year=2024, month=Some(2), day=Some(29))
  value.validate()
  assert_eq(value.to_ion_string(), "2024-02-29")
  assert_eq(value.precision(), @ion.TimestampPrecision::Day)
}

///|
test "named SymbolToken constructor preserves its components" {
  let value = @ion.SymbolToken("known")
  assert_eq(value.text(), Some("known"))
  assert_eq(value.sid(), None)
}

///|
test "Ion constructor converts a boolean through ToIon" {
  let value : @ion.IonValue = @ion.Ion(true)
  assert_true(value.kind() is Bool(true))
}

///|
test "Ion integers keep their exact signed value" {
  assert_eq(@text.write_ion(@ion.Ion(-42)), "-42")
}

///|
test "Ion 64-bit integers keep digits beyond double precision" {
  assert_eq(
    @text.write_ion(@ion.Ion(-9223372036854775808L)),
    "-9223372036854775808",
  )
}

///|
test "Ion unsigned integers stay positive" {
  assert_eq(@text.write_ion(@ion.Ion(4294967295U)), "4294967295")
}

///|
test "Ion unsigned 64-bit integers keep every digit" {
  assert_eq(
    @text.write_ion(@ion.Ion(18446744073709551615UL)),
    "18446744073709551615",
  )
}

///|
test "Ion arbitrary precision integers keep every digit" {
  let integer = @ion.Decimal::parse("123456789012345678901234567890.").coefficient()
  assert_eq(
    @text.write_ion(@ion.Ion(integer)),
    "123456789012345678901234567890",
  )
}

///|
test "Ion doubles remain Ion floats even when integral" {
  assert_true(@ion.Ion(42.0).kind() is Float(42.0))
}

///|
test "Ion single precision floats remain Ion floats" {
  assert_true(@ion.Ion((1.5 : Float)).kind() is Float(1.5))
}

///|
test "Ion strings remain strings rather than symbols" {
  assert_true(@ion.Ion("hello").kind() is String("hello"))
}

///|
test "Ion unit becomes an untyped null" {
  assert_true(@ion.Ion(()).is_untyped_null())
}

///|
test "Ion bytes become a blob rather than a clob" {
  assert_true(@ion.Ion(b"hi").kind() is Blob(bytes) && bytes == b"hi")
}

///|
test "Ion decimal scale and negative zero survive construction" {
  let decimal = @ion.Decimal::parse("-0.00")
  assert_eq(@text.write_ion(@ion.Ion(decimal)), "-0.00")
}

///|
test "Ion timestamp precision survives construction" {
  let timestamp = @ion.Timestamp::parse("2007T")
  assert_eq(@text.write_ion(@ion.Ion(timestamp)), "2007T")
}

///|
test "Ion symbol token identity survives construction" {
  let token = @ion.SymbolToken::from_sid(0)
  assert_true(@ion.Ion(token).kind() is Symbol(symbol) && symbol == token)
}

///|
test "Ion existing Ion values retain their annotations" {
  let original = @ion.IonValue::int(7).with_annotation(@ion.SymbolToken("tag"))
  assert_true(@ion.Ion(original).equals(original))
}

///|
test "Ion arrays convert their elements to an Ion list" {
  assert_eq(@text.write_ion(@ion.Ion([1, 2, 3])), "[1, 2, 3]")
}

///|
test "Ion maps convert entries to an Ion struct in iteration order" {
  let entries = Map([("b", 2), ("a", 1)])
  assert_eq(@text.write_ion(@ion.Ion(entries)), "{b: 2, a: 1}")
}

///|
struct ConstructorRecord {
  count : Int32
}

///|
impl @ion.ToIon for ConstructorRecord with fn to_ion(self) -> @ion.Ion {
  @ion.Ion(Map([("count", self.count)]))
}

///|
test "Ion constructor accepts an application implementation of ToIon" {
  assert_eq(
    @text.write_ion(@ion.Ion(ConstructorRecord::{ count: 3, })),
    "{count: 3}",
  )
}

///|
test "Ion constructor composes maps arrays and application values" {
  let value = @ion.Ion(Map([("records", [ConstructorRecord::{ count: 3, }])]))
  assert_eq(@text.write_ion(value), "{records: [{count: 3}]}")
}

///|
#warnings("-deprecated")
test "deprecated model constructors preserve the existing API" {
  let value : @ion.IonValue = @ion.IonValue::new(@ion.IonValueKind::Bool(true))
  assert_true(value.equals(@ion.Ion(true)))
  let field = @ion.Field::new("count", value)
  assert_eq(field.name().text(), Some("count"))
  assert_true(field.value().equals(value))
  assert_eq(@ion.SymbolToken::new("tag"), @ion.SymbolToken("tag"))
  assert_eq(["tag"].map(@ion.SymbolToken::new), [@ion.SymbolToken("tag")])
  let coefficient = @ion.Decimal::from_int(123).coefficient()
  assert_eq(@ion.Decimal::new(coefficient, -2).to_ion_string(), "1.23")
  assert_eq(@ion.Timestamp::new(year=2024).to_ion_string(), "2024T")
  assert_true(value.to_ion().equals(value))
}
