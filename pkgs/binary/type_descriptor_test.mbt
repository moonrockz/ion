// Black-box tests for the Ion binary type-descriptor model.

///|
test "type descriptor packs type code and length nibble" {
  let descriptor = @binary.type_descriptor(@binary.IonTypeCode::String, 5)
  assert_eq(descriptor, 0x85)
  assert_eq(
    @binary.descriptor_type_code(descriptor),
    @binary.IonTypeCode::String,
  )
  assert_eq(@binary.descriptor_length_nibble(descriptor), 5)
  assert_true(!@binary.descriptor_is_null(descriptor))
  let null_descriptor = @binary.type_descriptor(
    @binary.IonTypeCode::Struct,
    @binary.length_null,
  )
  assert_true(@binary.descriptor_is_null(null_descriptor))
}

///|
test "type codes round-trip through their numeric value" {
  for
    code in [
      @binary.IonTypeCode::Null,
      @binary.IonTypeCode::Bool,
      @binary.IonTypeCode::PosInt,
      @binary.IonTypeCode::NegInt,
      @binary.IonTypeCode::Float,
      @binary.IonTypeCode::Decimal,
      @binary.IonTypeCode::Timestamp,
      @binary.IonTypeCode::Symbol,
      @binary.IonTypeCode::String,
      @binary.IonTypeCode::Clob,
      @binary.IonTypeCode::Blob,
      @binary.IonTypeCode::List,
      @binary.IonTypeCode::Sexp,
      @binary.IonTypeCode::Struct,
      @binary.IonTypeCode::Annotation,
      @binary.IonTypeCode::Reserved,
    ] {
    assert_eq(@binary.IonTypeCode::from_int(code.to_int()), code)
  }
}

///|
test "Ion types map to and from type codes" {
  assert_eq(
    @binary.IonTypeCode::from_ion_type(@ion.IonType::String),
    @binary.IonTypeCode::String,
  )
  assert_eq(
    @binary.IonTypeCode::from_ion_type(@ion.IonType::Int),
    @binary.IonTypeCode::PosInt,
  )
  assert_eq(@binary.IonTypeCode::PosInt.to_ion_type(), Some(@ion.IonType::Int))
  assert_eq(@binary.IonTypeCode::Annotation.to_ion_type(), None)
}

///|
test "binary version marker is recognized" {
  let marker = @binary.binary_version_marker()
  assert_eq(marker.length(), 4)
  assert_true(@binary.has_binary_version_marker(marker))
  assert_true(
    !@binary.has_binary_version_marker(Bytes::from_array([0xE0, 0x01])),
  )
}
