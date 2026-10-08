// Property-based tests for Ion Hash.
//
// The hash is encoding independent, so it must not change when a value is
// written and read back; and because structs are unordered, it must not change
// when their fields are reordered.

///|
/// The Ion Hash of a value written in Ion text, as lowercase hexadecimal.
fn hash_text(text : String) -> String raise @ion.IonError {
  @hash.ion_hash_hex(@text.read_ion(text))
}

///|
test "hashing commutes with the text encoding" {
  @quickcheck.check((s : String) => {
    let symbol = @ion.IonValue::symbol(s)
    let string = @ion.IonValue::string(s)
    @hash.ion_hash_hex(symbol) == hash_text(@text.write_ion(symbol)) &&
    @hash.ion_hash_hex(string) == hash_text(@text.write_ion(string))
  })
}

///|
test "an integer keeps its hash across a text round-trip" {
  @quickcheck.check((n : BigInt) => {
    let value = @ion.IonValue::big_int(n)
    @hash.ion_hash_hex(value) == hash_text(@text.write_ion(value))
  })
}

///|
test "struct hashing ignores field order" {
  @quickcheck.check((pairs : Array[(String, BigInt)]) => {
    let fields = pairs.map(pair => {
      @ion.Field::new(pair.0, @ion.IonValue::big_int(pair.1))
    })
    @hash.ion_hash_hex(@ion.IonValue::from_fields(fields)) ==
    @hash.ion_hash_hex(@ion.IonValue::from_fields(fields.rev()))
  })
}

///|
test "a value has one hash, read from text or from binary" {
  for
    value in @testkit.gen_value(max_depth=6, max_width=4, unknown_symbols=false).samples(
      count=300,
      size=8,
    ) {
    let from_text = @text.read_ion(@text.write_ion(value))
    let from_binary = @binary.read_binary_value(
      @binary.write_binary_value(value),
    )
    let expected = @hash.ion_hash(value)
    if @hash.ion_hash(from_text) != expected ||
      @hash.ion_hash(from_binary) != expected {
      fail("hash differs for \{@text.write_ion(value)}")
    }
  }
}
