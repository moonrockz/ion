// Ion Hash handles values nested far deeper than the readers accept.

///|
let deep : Int = 100_000

///|
#skip("ion-dql.7: serialize_with recurses once per level")
test "ion_hash serializes lists and sexps 100,000 levels deep" {
  let cases : Array[(@testkit.DeepShape, Byte)] = [
    (List, b'\xB0'),
    (Sexp, b'\xC0'),
  ]
  for case in cases {
    let identity = (bytes : Array[Byte]) => bytes
    let actual = @hash.ion_hash_with(
      @testkit.deep_value(case.0, deep),
      identity,
    )
    let expected : Array[Byte] = []
    for _ in 0..<deep {
      expected.push(b'\x0B')
      expected.push(case.1)
    }
    expected.push_iter([b'\x0B', b'\x20', b'\x01', b'\x0E'].iter())
    for _ in 0..<deep {
      expected.push(b'\x0E')
    }
    if actual != Bytes::from_array(expected) {
      fail("serialization differs: \{actual.length()} octets")
    }
  }
}

///|
#skip("ion-dql.7: serialize_with recurses once per level")
test "ion_hash tells apart structs and annotated values 100,000 levels deep" {
  let shapes : Array[@testkit.DeepShape] = [Struct, AnnotatedList, Mixed]
  for shape in shapes {
    let a = @hash.ion_hash(@testkit.deep_value(shape, deep))
    assert_true(a == @hash.ion_hash(@testkit.deep_value(shape, deep)))
    assert_true(
      a !=
      @hash.ion_hash(
        @testkit.deep_value(shape, deep, leaf=@ion.IonValue::int(2)),
      ),
    )
  }
}
