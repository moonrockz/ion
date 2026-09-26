// Black-box tests for Ion Hash (Ion Hash 1.0, SHA-256).
//
// The expected digests come from the reference test vectors published with the
// specification (<https://amazon-ion.github.io/ion-hash/docs/spec.html>) and
// the `amazon-ion/ion-hash` conformance suite.

///|
/// The Ion Hash of a value written in Ion text, as lowercase hexadecimal.
fn hash_of(text : String) -> String raise @ion.IonError {
  @hash.ion_hash_hex(@text.read_ion(text))
}

///|
test "Ion Hash golden digests" {
  inspect(
    hash_of("null"),
    content=(
      #|0fb06b6183c21379529fdd45d6af4aba731ac6f081ef9e6c1c94b1fb26177304
    ),
  )
  inspect(
    hash_of("42"),
    content=(
      #|a9c9d493ae6a264a9eccb55bd9f047c2293e63d0b550b1f63652d7f25a23982e
    ),
  )
  inspect(
    hash_of("[1, 2, 3]"),
    content=(
      #|30a581772b5bad8853a950f592603fb8dde67168b21fee82b5bab4ac4985dfdc
    ),
  )
  inspect(
    hash_of("{a: 1, b: 2}"),
    content=(
      #|82600fc9b40e3c5392ee8a7f8d149f0e96d6b7e6f739a8f516d2715a07b6ce6b
    ),
  )
  inspect(
    hash_of("2000-01-01T00:00:00Z"),
    content=(
      #|2913b1818f8cccbedaf1b2ca5c913c4503b3fa5c080618dda1a01dc1a479a2db
    ),
  )
  inspect(
    hash_of("int32::12"),
    content=(
      #|40097a42dbeaaec3d37b218e9c3f636f7724e35fa19f00cfdbbb9152d9ec35f1
    ),
  )
}

///|
/// The serialization `s(value)` of a value written in Ion text, as hex.
fn serialization_hex(text : String) -> String raise @ion.IonError {
  to_hex(@hash.ion_hash_with(@text.read_ion(text), bytes => bytes))
}

///|
/// Timestamps are stored in UTC, so a local offset can shift the date across a
/// day, a month, or a year boundary while the fractional second is preserved.
test "timestamps normalize to UTC across date boundaries" {
  // A positive offset rolls the time back into the previous day.
  inspect(
    serialization_hex("2001-01-01T00:00:00+01:00"),
    content=(
      #|0b60bc0fd08c9f9780800e
    ),
  )
  // ... across a leap day (2000 is a leap year) ...
  inspect(
    serialization_hex("2000-03-01T00:30:00+01:00"),
    content=(
      #|0b60bc0fd0829d979e800e
    ),
  )
  // ... and a negative offset rolls forward across a year boundary.
  inspect(
    serialization_hex("2001-12-31T23:30:00-01:00"),
    content=(
      #|0b60fc0fd28181809e800e
    ),
  )
  // The fractional second survives the shift.
  inspect(
    serialization_hex("2000-01-01T00:00:00.5+01:00"),
    content=(
      #|0b60bc0fcf8c9f978080c1050e
    ),
  )
}
