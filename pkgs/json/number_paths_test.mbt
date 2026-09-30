///|
test "explicit JSON number spellings retain integer digits and decimal scale" {
  let integer = @json.to_ion(
    Json::number(9007199254740992.0, repr="9007199254740993"),
  )
  assert_eq(@text.write_ion(integer), "9007199254740993")
  let decimal = @json.to_ion(Json::number(1.5, repr="1.500"))
  assert_eq(@text.write_ion(decimal), "1500d-3")
  let negative_zero = @json.to_ion(Json::number(-0.0, repr="-0.00"))
  assert_eq(@text.write_ion(negative_zero), "-0d-2")
  let exponential = @json.to_ion(Json::number(0.0025, repr="2.5E-3"))
  guard exponential.kind() is Float(value) else {
    fail("expected an exponent-spelled float")
  }
  assert_eq(value, 0.0025)
}

///|
test "malformed JSON number spellings fall back to the supplied double" {
  for repr in ["oops", "."] {
    let integral = @json.to_ion(Json::number(42.0, repr~))
    assert_true(integral.equals(@core.IonValue::int(42)))
    let fractional = @json.to_ion(Json::number(1.5, repr~))
    assert_true(fractional.equals(@core.IonValue::float(1.5)))
    let large = @json.to_ion(Json::number(1.0e20, repr~))
    assert_true(large.equals(@core.IonValue::float(1.0e20)))
  }
  let bad_exponent = @json.to_ion(Json::number(7.0, repr="1E+"))
  assert_true(bad_exponent.equals(@core.IonValue::float(7.0)))
}

///|
test "JSON double fallback respects Int64 boundaries and non-finite values" {
  let lower = @json.to_ion(Json::number(-9223372036854775808.0, repr="oops"))
  guard lower.kind() is Int(number) else {
    fail("Int64 minimum should remain an integer")
  }
  assert_eq(number.to_string(), "-9223372036854775808")
  let upper = @json.to_ion(Json::number(9223372036854775808.0, repr="oops"))
  assert_true(upper.kind() is Float(_))
  for value in [1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0] {
    let ion = @json.to_ion(Json::number(value, repr="oops"))
    guard ion.kind() is Float(actual) else {
      fail("non-finite fallback must be a float")
    }
    if value.is_nan() {
      assert_true(actual.is_nan())
    } else {
      assert_eq(actual, value)
    }
  }
}

///|
test "JSON parsing handles exponent extremes and negative zero" {
  for
    (source, expected) in [
      ("-0", "0"),
      ("-0.0", "0"),
      ("1e400", "+inf"),
      ("-1E400", "-inf"),
      ("1e-400", "0"),
    ] {
    assert_eq(@text.write_ion(@json.read_json(source)), expected, msg=source)
  }
  let nan = @json.to_ion(Json::number(0.0 / 0.0))
  guard nan.kind() is Float(value) else { fail("NaN fallback must be a float") }
  assert_true(value.is_nan())
}
