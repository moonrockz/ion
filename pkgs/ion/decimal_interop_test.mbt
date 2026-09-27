// Black-box tests for `moonbitlang/x` decimal interoperability.

///|
test "decimal arithmetic via moonbitlang/x" {
  let a = @ion.Decimal::parse("1.25")
  let b = @ion.Decimal::parse("2.75")
  assert_eq(a.add(b).unwrap().to_double(), Some(4.0))
  assert_eq(a.subtract(b).unwrap().to_double(), Some(-1.5))
  assert_eq(a.multiply(b).unwrap().to_double(), Some(3.4375))
  assert_eq(a.compare(b), Some(-1))
  assert_eq(a.to_double(), Some(1.25))
}

///|
test "conversion preserves the value but not the scale or signed zero" {
  let round_tripped = @ion.Decimal::from_x(
    @ion.Decimal::parse("1.50").to_x().unwrap(),
  )
  // `x`'s decimal normalizes, so the trailing zero is gone.
  assert_eq(round_tripped.to_ion_string(), "15d-1")
  // It has no signed zero, so `-0.` becomes plain `0.`.
  let zero = @ion.Decimal::negative_zero()
  assert_eq(@ion.Decimal::from_x(zero.to_x().unwrap()).to_ion_string(), "0d0")
}

///|
test "conversion fails outside the moonbitlang/x decimal range" {
  let far = @ion.Decimal::new(@ion.Decimal::parse("1").coefficient(), -40)
  assert_true(far.to_x() is None)
  assert_true(far.to_double() is None)
}
