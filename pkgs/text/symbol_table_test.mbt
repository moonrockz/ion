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
test "a symbol ID the table does not define keeps only its ID" {
  assert_eq(datagram("$ion_symbol_table::{symbols: [\"a\"]} $11 $0"), "$11\n$0")
}

///|
test "a version marker is consumed and resets the symbol table" {
  assert_eq(datagram("$ion_1_0 1"), "1")
  assert_eq(
    datagram("$ion_symbol_table::{symbols: [\"a\"]} $10 $ion_1_0 $10"),
    "a\n$10",
  )
}

///|
test "a quoted or annotated $ion_1_0 is an ordinary symbol" {
  assert_eq(datagram("'$ion_1_0' $ion_1_0::1"), "'$ion_1_0'\n'$ion_1_0'::1")
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
    datagram("[$ion_symbol_table::{symbols: [\"a\"]}] $10"),
    "[$ion_symbol_table::{symbols: [\"a\"]}]\n$10",
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
