// Black-box tests for `read_ion_prefix`, the framing step of the streaming
// text reader.

///|
/// The value and the number of code units a prefix read reports.
fn prefix(
  text : String,
  end_of_input~ : Bool,
) -> (String, Int)? raise @ion.IonError {
  let symbols = @ion.SymbolTable::system()
  match @text.read_ion_prefix(text, symbols~, end_of_input~) {
    Some((Some(value), consumed)) => Some((@text.write_ion(value), consumed))
    Some((None, consumed)) => Some(("", consumed))
    None => None
  }
}

///|
test "a value followed by more text is settled" {
  assert_eq(prefix("{a: 1} [2]", end_of_input=false), Some(("{a: 1}", 7)))
}

///|
test "trailing whitespace and comments are consumed with the value" {
  assert_eq(
    prefix("1 /* note */ // line\n2", end_of_input=true),
    Some(("1", 21)),
  )
}

///|
test "a value that ends the text waits for more input" {
  assert_eq(prefix("123", end_of_input=false), None)
  assert_eq(prefix("abc  ", end_of_input=false), None)
  assert_eq(prefix("123", end_of_input=true), Some(("123", 3)))
}

///|
test "a value that ends with its closing delimiter is settled at once" {
  assert_eq(prefix("{a: 1}\n", end_of_input=false), Some(("{a: 1}", 7)))
  assert_eq(prefix("[1]", end_of_input=false), Some(("[1]", 3)))
  assert_eq(prefix("(a b)", end_of_input=false), Some(("(a b)", 5)))
  assert_eq(prefix("\"s\"", end_of_input=false), Some(("\"s\"", 3)))
  assert_eq(prefix("{{ aGk= }}", end_of_input=false), Some(("{{ aGk= }}", 10)))
  assert_eq(prefix("a::[1]", end_of_input=false), Some(("a::[1]", 6)))
  // A quoted symbol can still become an annotation.
  assert_eq(prefix("'s'", end_of_input=false), None)
}

///|
test "a symbol that may still gain an annotation waits for more input" {
  assert_eq(prefix("a :", end_of_input=false), None)
  assert_eq(prefix("a ::", end_of_input=false), None)
  assert_eq(prefix("a :: b [1]", end_of_input=false), Some(("a::b", 7)))
}

///|
test "a long string that may still continue waits for more input" {
  assert_eq(prefix("'''a''' ''", end_of_input=false), None)
  assert_eq(
    prefix("'''a''' '''b''' 1", end_of_input=true),
    Some(("\"ab\"", 16)),
  )
  assert_eq(prefix("'''a''' 'b'", end_of_input=false), Some(("\"a\"", 8)))
}

///|
test "an open container or comment waits for more input" {
  assert_eq(prefix("[1, 2", end_of_input=false), None)
  assert_eq(prefix("1 /* open", end_of_input=false), None)
  assert_eq(prefix("{a: \"b", end_of_input=false), None)
}

///|
test "only whitespace and comments leave no value" {
  assert_eq(prefix("  // done\n", end_of_input=true), None)
  assert_eq(prefix("", end_of_input=false), None)
}

///|
test "a malformed value is reported once the input has ended" {
  assert_eq(prefix("[1, 2", end_of_input=false), None)
  let mut failed = false
  ignore(
    prefix("[1, 2", end_of_input=true) catch {
      _ => {
        failed = true
        None
      }
    },
  )
  assert_true(failed)
}
