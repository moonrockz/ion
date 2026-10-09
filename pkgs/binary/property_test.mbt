// Property-based tests for the Ion binary type-descriptor model.

///|
test "a type descriptor round-trips its type code and length nibble" {
  @quickcheck.check((pair : (Int, Int)) => {
    let code = @binary.IonTypeCode::from_int(pair.0 & 0x0F)
    let nibble = pair.1 & 0x0F
    let descriptor = @binary.type_descriptor(code, nibble)
    @binary.descriptor_type_code(descriptor) == code &&
    @binary.descriptor_length_nibble(descriptor) == nibble
  })
}

///|
fn walker_samples() -> Array[@ion.IonValue] {
  @testkit.gen_value(max_depth=6, max_width=4).samples(count=300, size=8)
}

///|
test "generated values survive binary" {
  for value in walker_samples() {
    let back = @binary.read_binary_value(@binary.write_binary_value(value))
    if !back.equals(value) {
      fail("binary round trip of \{@text.write_ion(value)}")
    }
  }
}

///|
test "text through binary gives the same text" {
  for value in walker_samples() {
    let text = @text.write_ion(value)
    let back = @binary.read_binary_value(
      @binary.write_binary_value(@text.read_ion(text)),
    )
    assert_eq(@text.write_ion(back), text)
  }
}

///|
test "values with symbols from a shared import survive binary" {
  for
    value in @testkit.gen_value(max_depth=6, max_width=4, imported_symbols=true).samples(
      count=300,
      size=8,
    ) {
    let back = @binary.read_binary_value(@binary.write_binary_value(value))
    if !back.equals(value) {
      fail("imported symbols: \{@text.write_ion(value)}")
    }
  }
}
