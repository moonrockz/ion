// Black-box tests for Ion 1.0 text rules that the ion-tests suite checks.

///|
/// Whether reading `text` as a datagram raises an error.
fn rejects(text : String) -> Bool {
  try @text.read_ion_datagram(text) catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
/// The datagram `text` reads to, written back as compact text.
fn reads_as(text : String) -> String raise {
  @text.write_all(@text.read_ion_datagram(text))
}

///|
test "raw control characters are not allowed in strings, symbols, or clobs" {
  assert_true(rejects("\"a\u{1f}b\""))
  assert_true(rejects("'''a\u{1f}b'''"))
  assert_true(rejects("'a\u{1f}b'"))
  assert_true(rejects("{{ \"a\u{0}b\" }}"))
  assert_true(rejects("{{ '''a\u{1f}b''' }}"))
  // Tab, vertical tab, and form feed are whitespace, and allowed.
  assert_eq(reads_as("\"a\tb\u{0b}c\u{0c}d\""), "\"a\\tb\\vc\\fd\"")
}

///|
test "newlines in long strings and long clobs read as line feeds" {
  assert_eq(reads_as("'''a\r\nb\rc\nd'''"), "\"a\\nb\\nc\\nd\"")
  assert_eq(reads_as("'''\r\r\n'''"), "\"\\n\\n\"")
  assert_eq(reads_as("{{ '''a\r\nb\rc''' }}"), "{{ \"a\\x0ab\\x0ac\" }}")
}

///|
test "only whitespace may separate the parts of a long clob" {
  assert_eq(reads_as("{{ '''a''' \n '''b''' }}"), "{{ \"ab\" }}")
  assert_true(rejects("{{ '''a''' /* c */ '''b''' }}"))
  assert_true(rejects("{{ '''a''' // c\n '''b''' }}"))
}

///|
test "keywords are not annotations or field names unless quoted" {
  for keyword in ["null", "true", "false", "nan"] {
    assert_true(rejects(keyword + "::1"))
    assert_true(rejects("{" + keyword + ": 1}"))
    assert_eq(reads_as("'" + keyword + "'::1"), "'" + keyword + "'::1")
    assert_eq(reads_as("{'" + keyword + "': 1}"), "{'" + keyword + "': 1}")
  }
}

///|
test "a long string can be a field name" {
  assert_eq(reads_as("{'''foo''': 1}"), "{foo: 1}")
  assert_eq(reads_as("{'''a''' '''b''' : 1}"), "{ab: 1}")
  assert_eq(reads_as("{'''''': 1}"), "{'': 1}")
}

///|
test "decimals and floats may not have leading zeros" {
  for text in ["03.4e0", "003e4", "00e0", "04.3", "007d4", "00d0"] {
    assert_true(rejects(text))
  }
  assert_eq(reads_as("0.4 0e0 0d0 -0.5 0.0e1"), "0.4\n0e0\n0.\n-0.5\n0e0")
}

///|
test "a float may have a decimal point and no fraction digits" {
  assert_eq(reads_as("123.e7"), "1230000000e0")
  assert_eq(reads_as("0.e0"), "0e0")
}

///|
test "a float too large for a double reads as infinity" {
  assert_eq(reads_as("123.777e777 -1e400"), "+inf\n-inf")
}

///|
test "a symbol ID beyond the symbol table is an error" {
  assert_true(rejects("$10"))
  assert_true(rejects("$99::1"))
  assert_true(rejects("{$10: 1}"))
  assert_true(rejects("$ion_symbol_table::{symbols: [\"a\"]} $11"))
  assert_eq(reads_as("$0"), "$0")
}

///|
test "a top-level symbol with the text $ion_1_0 is a no-op" {
  assert_eq(reads_as("'$ion_1_0' 1"), "1")
  assert_eq(reads_as("$2 1"), "1")
  assert_eq(reads_as("$ion_symbol_table::{symbols: [\"$ion_1_0\"]} $10 1"), "1")
  // Nested, or annotated, it is an ordinary symbol.
  assert_eq(
    reads_as("['$ion_1_0'] a::'$ion_1_0'"),
    "['$ion_1_0']\na::'$ion_1_0'",
  )
}

///|
test "an underscore in a float or decimal must sit between two digits" {
  for
    text in [
      "1_.2e3", "1._2e3", "1.2_e3", "1.2e_3", "1.2e3_", "-6.0__1e1", "1_.2", "1._2",
      "1.2_", "1_d2", "_1.2e3",
    ] {
    assert_true(rejects(text))
  }
  assert_eq(
    reads_as("1_0.2_5e1_0 1_0.2_5 -1_2.3d1"),
    "102500000000e0\n10.25\n-123.",
  )
}

///|
test "a null struct annotated $ion_symbol_table is an empty symbol table" {
  assert_eq(
    reads_as(
      "$ion_symbol_table::{symbols: [\"a\"]} $10 $ion_symbol_table::null.struct first",
    ),
    "a\nfirst",
  )
  assert_true(
    rejects(
      "$ion_symbol_table::{symbols: [\"a\"]} $ion_symbol_table::null.struct $10",
    ),
  )
}
