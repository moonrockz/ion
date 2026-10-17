// Optional JSON fuel bounds open arrays and objects independently of the
// machine stack. The default accepts unrestricted nesting.

///|
/// JSON text for `depth` containers nested inside each other around `1`.
fn nested(open : String, close : String, depth : Int32) -> String {
  open.repeat(depth) + "1" + close.repeat(depth)
}

///|
/// Whether `read` raises `IonError::FuelExhausted`.
fn exceeds_limit(read : () -> Unit raise @core.IonError) -> Bool {
  try read() catch {
    @core.IonError::FuelExhausted(..) => true
    _ => false
  } noraise {
    _ => false
  }
}

///|
test "finite JSON fuel counts both arrays and objects" {
  for spelling in [("[", "]"), ("{\"a\":", "}")] {
    let (open, close) = spelling
    ignore(@json.read_json(nested(open, close, 128)))
    let deeper = nested(open, close, 128 + 1)
    assert_true(
      exceeds_limit(() => {
        ignore(@json.read_json(deeper, fuel=Limited(@core.Budget(128))))
      }),
    )
  }
}

///|
test "finite JSON fuel refuses 100000 nested arrays without stack overflow" {
  let text = nested("[", "]", 100_000)
  assert_true(
    exceeds_limit(() => {
      ignore(@json.read_json(text, fuel=Limited(@core.Budget(128))))
    }),
  )
}

///|
test "read_json does not count brackets inside strings as nesting" {
  let brackets = "[".repeat(128 + 1)
  let value = @json.read_json("{\"a\\\"[\": \"" + brackets + "\"}")
  assert_true(value.kind() is @core.IonValueKind::Struct(_))
}
