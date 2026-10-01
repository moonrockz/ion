// Black-box round-trip tests for the Ion text reader and writer.

///|
fn parse_or_none(text : String) -> @ion.IonValue? {
  let value = @text.read_ion(text) catch { _ => return None }
  Some(value)
}

///|
fn rewrite(text : String) -> String raise @ion.IonError {
  @text.write_ion(@text.read_ion(text))
}

///|
fn is_rejected(text : String) -> Bool {
  parse_or_none(text) is None
}

///|
test "scalars round-trip to canonical text" {
  assert_eq(rewrite("null"), "null")
  assert_eq(rewrite("null.null"), "null")
  assert_eq(rewrite("null.int"), "null.int")
  assert_eq(rewrite("null.struct"), "null.struct")
  assert_eq(rewrite("true"), "true")
  assert_eq(rewrite("false"), "false")
  assert_eq(rewrite("42"), "42")
  assert_eq(rewrite("-17"), "-17")
  assert_eq(rewrite("0"), "0")
  assert_eq(rewrite("0xFF"), "255")
  assert_eq(rewrite("0b1010"), "10")
  assert_eq(rewrite("1_000_000"), "1000000")
}

///|
test "reals round-trip" {
  assert_eq(rewrite("1.5"), "1.5")
  assert_eq(rewrite("1d3"), "1d3")
  assert_eq(rewrite("-0.0"), "-0.0")
  assert_eq(rewrite("1.5e0"), "1.5e0")
  assert_eq(rewrite("nan"), "nan")
  assert_eq(rewrite("+inf"), "+inf")
  assert_eq(rewrite("-inf"), "-inf")
}

///|
test "timestamps round-trip" {
  assert_eq(rewrite("2007T"), "2007T")
  assert_eq(rewrite("2007-01T"), "2007-01T")
  assert_eq(rewrite("2007-01-01"), "2007-01-01")
  assert_eq(rewrite("2007-01-01T"), "2007-01-01")
  assert_eq(rewrite("2007-02-23T12:14Z"), "2007-02-23T12:14Z")
  assert_eq(
    rewrite("2007-02-23T12:14:33.079-08:00"),
    "2007-02-23T12:14:33.079-08:00",
  )
  assert_eq(rewrite("2007-01-01T00:00-00:00"), "2007-01-01T00:00-00:00")
}

///|
test "strings and symbols round-trip" {
  assert_eq(rewrite("\"hi\""), "\"hi\"")
  assert_eq(rewrite("\"a\\nb\""), "\"a\\nb\"")
  assert_eq(rewrite("'hi ho'"), "'hi ho'")
  assert_eq(rewrite("abc"), "abc")
  assert_eq(rewrite("'null'"), "'null'")
  assert_eq(rewrite("''"), "''")
  assert_eq(rewrite("'''long'''"), "\"long\"")
  assert_eq(rewrite("'''a''' '''b'''"), "\"ab\"")
  assert_eq(rewrite("\"\\u00e9\""), "\"\u{e9}\"")
  assert_eq(rewrite("\"\\uD83D\\uDE00\""), "\"\u{1F600}\"")
}

///|
test "lobs round-trip" {
  assert_eq(rewrite("{{ aGk= }}"), "{{ aGk= }}")
  assert_eq(rewrite("{{ \"hi\" }}"), "{{ \"hi\" }}")
}

///|
test "containers round-trip" {
  assert_eq(rewrite("[]"), "[]")
  assert_eq(rewrite("()"), "()")
  assert_eq(rewrite("{}"), "{}")
  assert_eq(rewrite("[1, 2, 3]"), "[1, 2, 3]")
  assert_eq(rewrite("[1,]"), "[1]")
  assert_eq(rewrite("[1, [2, [3]]]"), "[1, [2, [3]]]")
  assert_eq(rewrite("{a: 1, b: \"x\"}"), "{a: 1, b: \"x\"}")
  assert_eq(rewrite("{a: 1,}"), "{a: 1}")
  assert_eq(rewrite("(a b c)"), "(a b c)")
}

///|
test "annotations round-trip" {
  assert_eq(rewrite("int32::12"), "int32::12")
  assert_eq(rewrite("a::b::c"), "a::b::c")
  assert_eq(rewrite("'my.type'::1"), "'my.type'::1")
}

///|
test "comments are whitespace" {
  assert_eq(rewrite("/* c */ 1 // x"), "1")
  assert_eq(rewrite("[\n 1, // one\n 2\n]"), "[1, 2]")
}

///|
test "datagram reads and writes one value per line" {
  let values = @text.read_ion_datagram("1 2 3")
  assert_eq(values.length(), 3)
  assert_eq(@text.write_all(values), "1\n2\n3")
}

///|
test "malformed input is rejected" {
  assert_true(is_rejected("[1, , 2]"))
  assert_true(is_rejected("{a 1}"))
  assert_true(is_rejected("\"unterminated"))
  assert_true(is_rejected("0x"))
  assert_true(is_rejected("(1 2"))
  assert_true(is_rejected("null.bogus"))
  assert_true(is_rejected("2007-01"))
  assert_true(is_rejected("1 2"))
}

///|
test "pretty printing nests containers" {
  let value = @text.read_ion("[1, {a: 2}]")
  assert_eq(@text.write_ion_pretty(value), "[\n  1,\n  {\n    a: 2\n  }\n]")
}

///|
test "clobs preserve high bytes and escapes" {
  assert_eq(rewrite("{{ \"\\xFF\\x00A\" }}"), "{{ \"\\xff\\x00A\" }}")
  assert_eq(rewrite("{{ '''\\xE9''' }}"), "{{ \"\\xe9\" }}")
}

///|
test "negative zero float keeps its sign" {
  assert_eq(rewrite("-0e0"), "-0e0")
}

///|
test "zero year is rejected" {
  assert_true(is_rejected("0000T"))
}

///|
test "invalid integer forms are rejected" {
  assert_true(is_rejected("0123"))
  assert_true(is_rejected("1_"))
  assert_true(is_rejected("1__2"))
  assert_true(is_rejected("0x_1F"))
  assert_true(is_rejected("0x1F_"))
}

///|
test "S-expression operators stay bare" {
  assert_eq(rewrite("(1 + 2 * 3)"), "(1 + 2 * 3)")
  assert_eq(rewrite("(a+-b)"), "(a +- b)")
  // A symbol that would open a comment stays quoted.
  assert_eq(rewrite("('//')"), "('//')")
}
