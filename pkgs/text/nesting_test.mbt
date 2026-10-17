// Optional text fuel bounds active container nesting independently of the
// machine stack. The default accepts any finite nesting depth.

///|
/// Text for `depth` containers nested inside each other around `1`, each one
/// spelled `open` ... `close`.
fn nested(open : String, close : String, depth : Int32) -> String {
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
/// Whether `read` raises `IonError::FuelExhausted`.
fn exceeds_limit(read : () -> Unit raise @ion.IonError) -> Bool {
  try read() catch {
    @ion.IonError::FuelExhausted(..) => true
    _ => false
  } noraise {
    _ => false
  }
}

///|
test "read_ion accepts containers nested to the finite fuel budget" {
  for spelling in spellings {
    let (open, close) = spelling
    let text = nested(open, close, 128)
    let value = @text.read_ion(text, fuel=Limited(@ion.Budget(128)))
    assert_true(value.equals(@text.read_ion(@text.write_ion(value))))
  }
}

///|
test "finite text fuel refuses containers one level past the budget" {
  for spelling in spellings {
    let (open, close) = spelling
    let text = nested(open, close, 128 + 1)
    assert_true(
      exceeds_limit(() => {
        ignore(@text.read_ion(text, fuel=Limited(@ion.Budget(128))))
      }),
    )
  }
}

///|
test "finite text fuel refuses 100000 nested containers without stack overflow" {
  for spelling in spellings {
    let (open, close) = spelling
    let text = nested(open, close, 100_000)
    assert_true(
      exceeds_limit(() => {
        ignore(@text.read_ion(text, fuel=Limited(@ion.Budget(128))))
      }),
    )
  }
}

///|
test "read_ion counts depth across mixed container kinds" {
  let text = nested("[({a:", "})]", 43)
  assert_true(
    exceeds_limit(() => {
      ignore(@text.read_ion(text, fuel=Limited(@ion.Budget(128))))
    }),
  )
  ignore(@text.read_ion(nested("[({a:", "})]", 42)))
}

///|
test "read_ion_datagram applies the limit to every top-level value" {
  let deep = nested("[", "]", 128 + 1)
  assert_true(
    exceeds_limit(() => {
      ignore(
        @text.read_ion_datagram("1 [2] " + deep, fuel=Limited(@ion.Budget(128))),
      )
    }),
  )
}

///|
test "read_ion_prefix raises past the limit before the input ends" {
  // More text cannot make a value shallower, so a streaming reader learns
  // at once that the value is too deep instead of waiting for more input.
  let text = "[".repeat(128 + 1)
  let symbols = @ion.SymbolTable::system()
  assert_true(
    exceeds_limit(() => {
      ignore(
        @text.read_ion_prefix(
          text,
          symbols~,
          end_of_input=false,
          fuel=Limited(@ion.Budget(128)),
        ),
      )
    }),
  )
}

///|
test "parse_cst rejects containers nested past the finite fuel budget" {
  for spelling in spellings {
    let (open, close) = spelling
    ignore(@text.parse_cst(nested(open, close, 128)))
    let text = nested(open, close, 100_000)
    assert_true(
      exceeds_limit(() => {
        ignore(@text.parse_cst(text, fuel=Limited(@ion.Budget(128))))
      }),
    )
  }
}
