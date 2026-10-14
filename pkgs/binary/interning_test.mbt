// The binary encoder interns new symbols in document order: for each value,
// its field name, then its annotations, then its symbol value.

///|
test "encode_value interns new symbols in document order" {
  let symbols = @ion.SymbolTable::system()
  let value = @text.read_ion("x::{y: z, w: v::[u]}")
  let octets = @binary.encode_value(value, symbols)
  debug_inspect(
    ["x", "y", "z", "w", "v", "u"].map(text => symbols.find(text)),
    content=(
      #|[Some(10), Some(11), Some(12), Some(13), Some(14), Some(15)]
    ),
  )
  // The same value with a table that already has the IDs encodes the same.
  assert_true(@binary.encode_value(value, symbols) == octets)
}
