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
