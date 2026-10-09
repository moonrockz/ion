// The binary writer handles values nested far deeper than the reader
// accepts. The expected octets come from `nested` in nesting_test.mbt, which
// builds them with loops.

///|
let deep : Int = 100_000

///|
#skip("ion-dql.6: encode recurses once per level")
test "write_binary encodes values 100,000 levels deep" {
  let cases : Array[(@testkit.DeepShape, Array[Frame])] = [
    (List, spellings[0]),
    (Sexp, spellings[1]),
    (Struct, spellings[2]),
    (AnnotatedList, spellings[3]),
  ]
  for case in cases {
    let actual = @binary.write_binary_value(@testkit.deep_value(case.0, deep))
    let expected = Bytes::from_array(
      [b'\xE0', b'\x01', b'\x00', b'\xEA', ..nested(case.1, deep).to_array()],
    )
    if actual != expected {
      fail(
        "octets differ: \{actual.length()} written, \{expected.length()} expected",
      )
    }
  }
}
