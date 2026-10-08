// The text readers accept containers nested up to @ion.MAX_NESTING_DEPTH and
// raise IonError::LimitExceeded past it, however deep the input goes, instead
// of overflowing the call stack.

///|
/// Text for `depth` containers nested inside each other around `1`, each one
/// spelled `open` ... `close`.
fn nested(open : String, close : String, depth : Int) -> String {
  open.repeat(depth) + "1" + close.repeat(depth)
}

///|
/// The container spellings that nest: a list, an S-expression, a struct, and
/// an annotated list (annotations do not add depth).
let spellings : Array[(String, String)] = [
  ("[", "]"),
  ("(", ")"),
  ("{a:", "}"),
  ("x::[", "]"),
]

///|
/// Whether `read` raises `IonError::LimitExceeded`.
fn exceeds_limit(read : () -> Unit raise @ion.IonError) -> Bool {
  try read() catch {
    @ion.IonError::LimitExceeded(_) => true
    _ => false
  } noraise {
    _ => false
  }
}

///|
test "read_ion accepts containers nested to MAX_NESTING_DEPTH" {
  for spelling in spellings {
    let (open, close) = spelling
    let text = nested(open, close, @ion.MAX_NESTING_DEPTH)
    let value = @text.read_ion(text)
    assert_true(value.equals(@text.read_ion(@text.write_ion(value))))
  }
}

///|
test "read_ion rejects containers nested one level past MAX_NESTING_DEPTH" {
  for spelling in spellings {
    let (open, close) = spelling
    let text = nested(open, close, @ion.MAX_NESTING_DEPTH + 1)
    assert_true(exceeds_limit(() => ignore(@text.read_ion(text))))
  }
}

///|
test "read_ion rejects 100,000 nested containers without overflowing the stack" {
  for spelling in spellings {
    let (open, close) = spelling
    let text = nested(open, close, 100_000)
    assert_true(exceeds_limit(() => ignore(@text.read_ion(text))))
  }
}

///|
test "read_ion counts depth across mixed container kinds" {
  let text = nested("[({a:", "})]", 43)
  assert_true(exceeds_limit(() => ignore(@text.read_ion(text))))
  ignore(@text.read_ion(nested("[({a:", "})]", 42)))
}

///|
test "read_ion_datagram applies the limit to every top-level value" {
  let deep = nested("[", "]", @ion.MAX_NESTING_DEPTH + 1)
  assert_true(
    exceeds_limit(() => ignore(@text.read_ion_datagram("1 [2] " + deep))),
  )
}

///|
test "read_ion_prefix raises past the limit before the input ends" {
  // More text cannot make a value shallower, so a streaming reader learns
  // at once that the value is too deep instead of waiting for more input.
  let text = "[".repeat(@ion.MAX_NESTING_DEPTH + 1)
  let symbols = @ion.SymbolTable::system()
  assert_true(
    exceeds_limit(() => {
      ignore(@text.read_ion_prefix(text, symbols~, end_of_input=false))
    }),
  )
}

///|
test "parse_cst rejects containers nested past MAX_NESTING_DEPTH" {
  for spelling in spellings {
    let (open, close) = spelling
    ignore(@text.parse_cst(nested(open, close, @ion.MAX_NESTING_DEPTH)))
    let text = nested(open, close, 100_000)
    assert_true(exceeds_limit(() => ignore(@text.parse_cst(text))))
  }
}
