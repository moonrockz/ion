// Property-based tests for the Ion text reader and writer.
//
// A round trip is the specification of an encoder/decoder pair, so these laws
// are the natural properties to state: `read(write(v)) == v`, and canonical
// text is a fixed point. QuickCheck generates the inputs and shrinks any
// counterexample to a minimal one.

///|
test "integers survive a text round-trip" {
  @quickcheck.check((n : BigInt) => {
    let value = @ion.IonValue::big_int(n)
    @text.read_ion(@text.write_ion(value)).equals(value)
  })
}

///|
test "strings survive a text round-trip" {
  @quickcheck.check((s : String) => {
    let value = @ion.IonValue::string(s)
    @text.read_ion(@text.write_ion(value)).equals(value)
  })
}

///|
test "symbols survive a text round-trip" {
  @quickcheck.check((s : String) => {
    let value = @ion.IonValue::symbol(s)
    @text.read_ion(@text.write_ion(value)).equals(value)
  })
}

///|
test "blobs and clobs survive a text round-trip" {
  @quickcheck.check((bytes : Bytes) => {
    let blob = @ion.IonValue::blob(bytes)
    let clob = @ion.IonValue::clob(bytes)
    @text.read_ion(@text.write_ion(blob)).equals(blob) &&
    @text.read_ion(@text.write_ion(clob)).equals(clob)
  })
}

///|
test "canonical text is a fixed point of write and read" {
  @quickcheck.check((s : String) => {
    let once = @text.write_ion(@ion.IonValue::string(s))
    @text.write_ion(@text.read_ion(once)) == once
  })
}

///|
test "tokenizing a written value reproduces its source" {
  @quickcheck.check((s : String) => {
    let text = @text.write_ion(@ion.IonValue::string(s))
    let rebuilt = StringBuilder()
    for token in @text.tokenize(text) {
      rebuilt.write_view(token.slice(text))
    }
    rebuilt.to_string() == text
  })
}
