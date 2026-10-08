// read_json accepts arrays and objects nested up to @core.MAX_NESTING_DEPTH,
// the limit of the Ion readers, and raises IonError::LimitExceeded past it.

///|
/// JSON text for `depth` containers nested inside each other around `1`.
fn nested(open : String, close : String, depth : Int) -> String {
  open.repeat(depth) + "1" + close.repeat(depth)
}

///|
/// Whether `read` raises `IonError::LimitExceeded`.
fn exceeds_limit(read : () -> Unit raise @core.IonError) -> Bool {
  try read() catch {
    @core.IonError::LimitExceeded(_) => true
    _ => false
  } noraise {
    _ => false
  }
}

///|
test "read_json nests as deep as the Ion readers allow" {
  for spelling in [("[", "]"), ("{\"a\":", "}")] {
    let (open, close) = spelling
    ignore(@json.read_json(nested(open, close, @core.MAX_NESTING_DEPTH)))
    let deeper = nested(open, close, @core.MAX_NESTING_DEPTH + 1)
    assert_true(exceeds_limit(() => ignore(@json.read_json(deeper))))
  }
}

///|
test "read_json rejects 100,000 nested arrays without overflowing the stack" {
  let text = nested("[", "]", 100_000)
  assert_true(exceeds_limit(() => ignore(@json.read_json(text))))
}

///|
test "read_json does not count brackets inside strings as nesting" {
  let brackets = "[".repeat(@core.MAX_NESTING_DEPTH + 1)
  let value = @json.read_json("{\"a\\\"[\": \"" + brackets + "\"}")
  assert_true(value.kind() is @core.IonValueKind::Struct(_))
}
