// Black-box tests for version markers and local symbol tables in Ion text.
//
// A reader applies a top-level unquoted `$ion_1_0` and a top-level
// `$ion_symbol_table::{...}` struct to its symbol table instead of returning
// them, and resolves each symbol ID against the table in effect.

///|
/// The datagram `text` reads to, written back as compact text.
fn datagram(text : String) -> String raise {
  @text.write_all(@text.read_ion_datagram(text))
}

///|
test "a local symbol table gives text to symbol IDs" {
  assert_eq(
    datagram("$ion_symbol_table::{symbols: [\"a\", \"b\"]} $10 $11"),
    "a\nb",
  )
}

///|
test "symbol IDs resolve in annotations, field names, and nested values" {
  assert_eq(
    datagram(
      "$ion_symbol_table::{symbols: [\"a\", \"b\"]} $10::{$11: [$10, ($11)]}",
    ),
    "a::{b: [a, (b)]}",
  )
}

///|
test "a symbol ID with unknown text keeps only its ID" {
  assert_eq(
    datagram("$ion_symbol_table::{symbols: [\"a\", null]} $11 $0"),
    "$ion_symbol_table::{symbols: [null, null]}\n$11\n$0",
  )
}

///|
test "a version marker is consumed and resets the symbol table" {
  assert_eq(datagram("$ion_1_0 1"), "1")
  assert_eq(
    datagram("$ion_symbol_table::{symbols: [\"a\"]} $10 $ion_1_0 $4"),
    "a\nname",
  )
}

///|
test "an annotated or nested $ion_1_0 is an ordinary symbol" {
  assert_eq(datagram("$ion_1_0::1 ['$ion_1_0']"), "'$ion_1_0'::1\n['$ion_1_0']")
}

///|
test "a version marker for another Ion version is unsupported" {
  let mut unsupported = false
  ignore(
    @text.read_ion_datagram("$ion_2_0 1") catch {
      @ion.IonError::Unsupported(_) => {
        unsupported = true
        []
      }
      _ => []
    },
  )
  assert_true(unsupported)
}

///|
test "importing $ion_symbol_table appends to the current symbols" {
  assert_eq(
    datagram(
      "$ion_symbol_table::{symbols: [\"a\"]} " +
      "$ion_symbol_table::{imports: $ion_symbol_table, symbols: [\"b\"]} " +
      "$10 $11",
    ),
    "a\nb",
  )
}

///|
test "a symbol table that is not at the top level is data" {
  assert_eq(
    datagram("[$ion_symbol_table::{symbols: [\"a\"]}] $4"),
    "[$ion_symbol_table::{symbols: [\"a\"]}]\nname",
  )
}

///|
test "read_ion skips system values before its one value" {
  let value = @text.read_ion(
    "$ion_1_0 $ion_symbol_table::{symbols: [\"a\"]} $10",
  )
  assert_eq(@text.write_ion(value), "a")
  let mut failed = false
  ignore(
    @text.read_ion("$ion_1_0") catch {
      _ => {
        failed = true
        @ion.IonValue::untyped_null()
      }
    },
  )
  assert_true(failed)
}

///|
test "the event reader skips system values" {
  let names = @text.IonReader::from_text(
      "$ion_symbol_table::{symbols: [\"a\"]} $10",
    )
    .remaining()
    .map(fn(event) { event.to_text() })
  assert_eq(names, ["DocumentStart", "Scalar(symbol)", "DocumentEnd"])
}

///|
test "a prefix read reports a system value and updates the table" {
  let symbols = @ion.SymbolTable::system()
  let text = "$ion_symbol_table::{symbols: [\"a\"]} $10 "
  match @text.read_ion_prefix(text, symbols~, end_of_input=true) {
    Some((None, consumed)) =>
      match
        @text.read_ion_prefix(
          text.view(start_offset=consumed),
          symbols~,
          end_of_input=true,
        ) {
        Some((Some(value), _)) => assert_eq(@text.write_ion(value), "a")
        _ => fail("expected the symbol")
      }
    _ => fail("expected the symbol table to be consumed")
  }
}

///|
test "symbols with unknown text round-trip through the writer" {
  let values = [
    @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(27)),
    @ion.IonValue::symbol("a"),
  ]
  let text = @text.write_all(values)
  let read_back = @text.read_ion_datagram(text)
  assert_eq(read_back.length(), 2)
  match read_back[0].kind() {
    @ion.IonValueKind::Symbol(token) => {
      assert_eq(token.text(), None)
      assert_eq(token.sid(), Some(27))
    }
    _ => fail("expected a symbol")
  }
  assert_true(read_back[1].equals(values[1]))
}

///|
/// A catalog with `colors` versions 1 and 2.
fn colors() -> @ion.Catalog raise {
  @ion.Catalog::load(
    @text.read_ion_datagram(
      "$ion_shared_symbol_table::{name: \"colors\", symbols: [\"red\", \"green\"]} " +
      "$ion_shared_symbol_table::{name: \"colors\", version: 2, symbols: [\"red\", \"green\", \"blue\"]}",
    ),
  )
}

///|
test "imports resolve against a catalog" {
  let text = "$ion_symbol_table::{imports: [{name: \"colors\", version: 2}], symbols: [\"local\"]} $10 $12 $13"
  let values = @text.read_ion_datagram(text, catalog=colors())
  assert_eq(@text.write_all(values), "red\nblue\nlocal")
  // `read_ion` takes the catalog too; version 1 has only red and green.
  assert_eq(
    @text.write_ion(
      @text.read_ion(
        "$ion_symbol_table::{imports: [{name: \"colors\"}]} $11",
        catalog=colors(),
      ),
    ),
    "green",
  )
  // Without the catalog, the import needs a max_id.
  let mut failed = false
  ignore(
    @text.read_ion_datagram(text) catch {
      _ => {
        failed = true
        []
      }
    },
  )
  assert_true(failed)
}
