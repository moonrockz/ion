// Black-box tests for the JSON <-> Ion conversions.
//
// `Json::stringify` gives the expected JSON text and `@text.write_ion` the
// expected Ion text; both are stable renderings, so the assertions double as a
// description of the two mappings.

///|
/// The error `to_json` raises for a value, or `None` when it succeeds.
fn to_json_error(value : @core.IonValue) -> @core.IonError? {
  let _ = @json.to_json(value) catch { error => return Some(error) }
  None
}

///|
test "JSON scalars become the matching Ion values" {
  assert_eq(@json.write_json(@json.to_ion(@cjson.parse("null"))), "null")
  assert_eq(@json.write_json(@json.to_ion(@cjson.parse("true"))), "true")
  assert_eq(@json.write_json(@json.to_ion(@cjson.parse("false"))), "false")
  assert_eq(@json.write_json(@json.to_ion(@cjson.parse("\"hi\""))), "\"hi\"")
}

///|
test "JSON objects and arrays become Ion structs and lists" {
  let value = @json.to_ion(@cjson.parse("{\"a\":1,\"b\":[true,null]}"))
  assert_eq(@text.write_ion(value), "{a: 1, b: [true, null]}")
  guard value.kind() is @core.IonValueKind::Struct(fields) else {
    fail("expected an Ion struct")
  }
  assert_eq(fields.length(), 2)
  assert_eq(fields[0].name().require_text(), "a")
  guard fields[1].value().kind() is @core.IonValueKind::List(items) else {
    fail("expected an Ion list")
  }
  assert_eq(items.length(), 2)
}

///|
test "JSON integers keep every digit" {
  assert_eq(@json.write_json(@json.to_ion(@cjson.parse("42"))), "42")
  let big = "123456789012345678901234567890"
  let value = @json.to_ion(@cjson.parse(big))
  assert_eq(@json.write_json(value), big)
  guard value.kind() is @core.IonValueKind::Int(number) else {
    fail("expected an Ion int")
  }
  assert_eq(number.to_string(), big)
}

///|
test "a JSON number's spelling decides its Ion type" {
  // Core drops the spelling of a fractional literal that fits a `Double`, so
  // the number's shortest spelling decides: `1.50` is the Ion decimal `1.5`.
  assert_eq(@text.write_ion(@json.to_ion(@cjson.parse("1.50"))), "1.5")
  assert_eq(@text.write_ion(@json.to_ion(@cjson.parse("2.5e-3"))), "0.0025")
  // An integral spelling is an Ion int.
  assert_eq(@text.write_ion(@json.to_ion(@cjson.parse("1e2"))), "100")
  // A spelling whose shortest form carries an exponent is an Ion float.
  let tiny = @json.to_ion(@cjson.parse("1e-7"))
  assert_true(tiny.kind() is @core.IonValueKind::Float(_))
  // A number that overflows the double keeps its spelling and is a float,
  // which JSON down-converts back to `null`.
  assert_eq(@text.write_ion(@json.to_ion(@cjson.parse("1e400"))), "+inf")
  assert_eq(@json.write_json(@json.to_ion(@cjson.parse("1e400"))), "null")
}

///|
test "Ion scalars down-convert following the cookbook" {
  assert_eq(
    @json.write_json(@core.IonValue::typed_null(@core.IonType::Int)),
    "null",
  )
  assert_eq(@json.write_json(@core.IonValue::bool(true)), "true")
  assert_eq(@json.write_json(@core.IonValue::int(7)), "7")
  assert_eq(
    @json.write_json(@json.to_ion(@cjson.parse("12345678901234567890"))),
    "12345678901234567890",
  )
  assert_eq(@json.write_json(@text.read_ion("1.5e0")), "1.5")
  assert_eq(@json.write_json(@text.read_ion("nan")), "null")
  assert_eq(@json.write_json(@text.read_ion("+inf")), "null")
  assert_eq(@json.write_json(@text.read_ion("-inf")), "null")
  assert_eq(
    @json.write_json(@text.read_ion("2000-01-01T00:00:00Z")),
    "\"2000-01-01T00:00:00Z\"",
  )
  assert_eq(@json.write_json(@text.read_ion("foo")), "\"foo\"")
  assert_eq(@json.write_json(@text.read_ion("\"bar\"")), "\"bar\"")
}

///|
test "Ion decimals keep their scale in JSON numbers" {
  assert_eq(@json.write_json(@text.read_ion("1.50")), "1.50")
  assert_eq(@json.write_json(@text.read_ion("-0.")), "-0")
  assert_eq(@json.write_json(@text.read_ion("-0.00")), "-0.00")
  assert_eq(@json.write_json(@text.read_ion("123d-2")), "1.23")
  assert_eq(@json.write_json(@text.read_ion("123d3")), "123000")
  assert_eq(@json.write_json(@text.read_ion("0d0")), "0")
  // A zero coefficient keeps its scale with an explicit exponent.
  assert_eq(@json.write_json(@text.read_ion("0d5")), "0e5")
  assert_eq(@json.write_json(@text.read_ion("-0d3")), "-0e3")
  assert_eq(@json.write_json(@text.read_ion("0d-3")), "0.000")
  // A decimal with more digits than a double can hold keeps them in `repr`.
  assert_eq(
    @json.write_json(@text.read_ion("1.0000000000000000000000001")),
    "1.0000000000000000000000001",
  )
}

///|
test "containers and annotations down-convert" {
  assert_eq(@json.write_json(@text.read_ion("(1 2 3)")), "[1,2,3]")
  assert_eq(@json.write_json(@text.read_ion("(1 + 2)")), "[1,\"+\",2]")
  assert_eq(@json.write_json(@text.read_ion("x::1")), "1")
  assert_eq(@json.write_json(@text.read_ion("x::{a: 1}")), "{\"a\":1}")
  // A JSON object cannot carry the repeated field names an Ion struct can.
  assert_eq(@json.write_json(@text.read_ion("{a: 1, a: 2}")), "{\"a\":2}")
}

///|
test "clobs become Latin-1 strings and blobs become Base64" {
  let clob = @json.to_json(@core.IonValue::clob(b"\x00A\xff"))
  guard clob is Json::String(text) else { fail("expected a JSON string") }
  assert_eq(text.char_length(), 3)
  assert_eq(text.get_char(0).unwrap().to_int(), 0x00)
  assert_eq(text.get_char(1).unwrap().to_int(), 0x41)
  assert_eq(text.get_char(2).unwrap().to_int(), 0xff)
  assert_eq(
    @json.write_json(@core.IonValue::blob(b"Hello, world!")),
    "\"SGVsbG8sIHdvcmxkIQ==\"",
  )
}

///|
test "a symbol known only by ID cannot become JSON" {
  let symbol = to_json_error(
    @core.IonValue::symbol_token(@core.SymbolToken::from_sid(900)),
  )
  assert_true(symbol is Some(@core.IonError::Unsupported(_)))
  let field = to_json_error(
    @core.IonValue::from_fields([
      @core.Field::from_token(
        @core.SymbolToken::from_sid(901),
        @core.IonValue::int(1),
      ),
    ]),
  )
  assert_true(field is Some(@core.IonError::Unsupported(_)))
  // The Ion 1.0 system symbols still resolve, so symbol ID 4 is `name`.
  assert_eq(
    @json.write_json(
      @core.IonValue::symbol_token(@core.SymbolToken::from_sid(4)),
    ),
    "\"name\"",
  )
}

///|
test "JSON survives a trip through Ion" {
  for
    text in [
      "null", "true", "42", "-7", "1.5", "0.1", "123456789012345678901234567890",
      "[1,2,3]", "{\"a\":1,\"b\":[true,null,\"x\"]}", "\"a\\\"b\"",
    ] {
    let original = @cjson.parse(text)
    assert_eq(@json.write_json(@json.to_ion(original)), original.stringify())
  }
}

///|
test "read_json and write_json go through JSON text" {
  assert_eq(@text.write_ion(@json.read_json("{\"a\":[1,2]}")), "{a: [1, 2]}")
  assert_eq(
    @json.write_json(@text.read_ion("{a: 1}"), indent=2),
    "{\n  \"a\": 1\n}",
  )
}

///|
test "unknown imported symbols cannot borrow system text from a local ID" {
  for sid in [0, 4, 10] {
    let value = @core.IonValue::symbol_token(
      @core.SymbolToken::from_import(sid, "shared", 1, 1),
    )
    let mut rejected = false
    ignore(
      @json.to_json(value) catch {
        @core.IonError::Unsupported(_) => {
          rejected = true
          Json::null()
        }
        error => fail(error.message())
      },
    )
    assert_true(rejected)
  }
}
