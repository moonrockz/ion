///|
test "binary reading accepts deep values with optional scoped fuel" {
  let mut value = @ion.IonValue::int(1)
  for level in 0..<10000 {
    value = match level % 4 {
      0 => @ion.IonValue::list([value])
      1 => @ion.IonValue::sexp([value])
      2 => @ion.IonValue::from_fields([@ion.Field::Field("a", value)])
      _ =>
        @ion.IonValue::list([value]).with_annotations([
          @ion.SymbolToken::SymbolToken("tag"),
        ])
    }
  }
  let bytes = @binary.write_binary_value(value)
  let decoded = @binary.read_binary_value(bytes)
  assert_true(decoded.equals(value))
  let exhausted = try
    @binary.read_binary_value(bytes, fuel=Limited(@ion.Budget(2)))
  catch {
    @ion.IonError::FuelExhausted(
      budget~,
      operation=BinaryRead,
      location=BinaryOffset(_)
    ) => budget.units() == 2
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
  let siblings = @ion.IonValue::list([
    @ion.IonValue::list([@ion.IonValue::int(1)]),
    @ion.IonValue::list([@ion.IonValue::int(2)]),
  ])
  let stream = @binary.write_binary([siblings, siblings])
  assert_eq(
    @binary.read_binary(stream, fuel=Limited(@ion.Budget(2))).length(),
    2,
  )
}

///|
test "binary event readers honor caller fuel" {
  let bytes = @binary.write_binary_value(
    @ion.IonValue::list([@ion.IonValue::list([])]),
  )
  let exhausted = try
    @binary.BinaryEventReader::new(bytes, fuel=Limited(@ion.Budget(1)))
  catch {
    @ion.IonError::FuelExhausted(..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}
