// Black-box tests for symbol-ID literals in Ion text.
//
// Ion text writes a symbol ID as `$` followed by digits. The reader resolves
// the Ion 1.0 system IDs (1..9) to their text, leaves ID 0 without text, and
// rejects an ID beyond the symbol table. Anything else — a `$` with trailing
// non-digits — is an ordinary symbol.

///|
/// The text of the symbol a value written as `text` parses to.
fn symbol_text(text : String) -> String? raise {
  match @text.read_ion(text).kind() {
    @ion.IonValueKind::Symbol(token) => token.text()
    _ => fail("expected a symbol: \{text}")
  }
}

///|
/// The symbol ID of the symbol a value written as `text` parses to.
fn symbol_sid(text : String) -> Int? raise {
  match @text.read_ion(text).kind() {
    @ion.IonValueKind::Symbol(token) => token.sid()
    _ => fail("expected a symbol: \{text}")
  }
}

///|
test "system symbol IDs resolve to their text" {
  assert_eq(symbol_text("$1"), Some("$ion"))
  assert_eq(symbol_text("$5"), Some("version"))
  assert_eq(symbol_text("$8"), Some("max_id"))
  assert_eq(symbol_text("$9"), Some("$ion_shared_symbol_table"))
}

///|
test "symbol ID zero keeps only its ID, and an unassigned ID is an error" {
  assert_eq(symbol_text("$0"), None)
  assert_eq(symbol_sid("$0"), Some(0))
  let mut failed = false
  ignore(
    symbol_text("$10") catch {
      _ => {
        failed = true
        None
      }
    },
  )
  assert_true(failed)
}

///|
test "a dollar sign without digits is an ordinary symbol" {
  assert_eq(symbol_text("$"), Some("$"))
  assert_eq(symbol_text("$ion"), Some("$ion"))
  assert_eq(symbol_text("$1a"), Some("$1a"))
}

///|
test "symbol-ID literals round-trip through the writer" {
  assert_eq(@text.write_ion(@text.read_ion("$0")), "$0")
  assert_eq(@text.write_ion(@text.read_ion("{$0: $1}")), "{$0: $ion}")
}
