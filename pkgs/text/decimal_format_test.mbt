///|
test "decimal spelling is positional when exact and reasonably short" {
  for
    (input, expected) in [
      ("4.5", "4.5"),
      ("1.50", "1.50"),
      ("150d-2", "1.50"),
      ("123d0", "123."),
      ("-123d0", "-123."),
      ("0d0", "0."),
      ("-0d0", "-0."),
      ("0d-2", "0.00"),
      ("-0d-2", "-0.00"),
      ("1d-6", "0.000001"),
      ("1d-7", "1d-7"),
      ("123d-8", "0.00000123"),
      ("123d-9", "123d-9"),
      ("-123d-8", "-0.00000123"),
      ("-123d-9", "-123d-9"),
      ("-0d-6", "-0.000000"),
      ("-0d-7", "-0d-7"),
      ("10d1", "10d1"),
      ("0d1", "0d1"),
      ("-0d1", "-0d1"),
      ("123456789012345678901234567890d-2", "1234567890123456789012345678.90"),
      ("1d2147483647", "1d2147483647"),
      ("1d-2147483647", "1d-2147483647"),
    ] {
    let value = @text.read_ion(input)
    assert_eq(@text.write_ion(value), expected)
    assert_eq(@text.write_ion_pretty(value), expected)
    assert_true(@text.read_ion(expected).equals(value))
    assert_eq(@text.write_ion(@text.read_ion(expected)), expected)
  }
}

///|
test "decimal text round-trips exact components and signed zero" {
  @quickcheck.check((pair : (BigInt, Int)) => {
    let exponent = pair.1 % 50
    let decimal = @ion.Decimal::new(pair.0, exponent)
    let zero = @ion.Decimal::negative_zero_at(exponent)
    let value = @ion.IonValue::list([
      @ion.IonValue::decimal(decimal),
      @ion.IonValue::decimal(zero),
    ])
    @text.read_ion(@text.write_ion(value)).equals(value)
  })
}

///|
test "extreme decimal exponents never expand to positional zeros" {
  let smallest = @ion.Decimal::new(BigInt::from_int(1), -2147483648)
  let largest = @ion.Decimal::new(BigInt::from_int(1), 2147483647)
  assert_eq(@text.write_ion(@ion.IonValue::decimal(smallest)), "1d-2147483648")
  assert_eq(@text.write_ion(@ion.IonValue::decimal(largest)), "1d2147483647")
  assert_true(
    @text.read_ion(smallest.to_ion_string()).equals(
      @ion.IonValue::decimal(smallest),
    ),
  )
}

///|
test "decimal exponent parsing checks signed bounds and fractional adjustment" {
  let minimum = @text.read_ion("0.1d-2147483647")
  assert_eq(@text.write_ion(minimum), "1d-2147483648")
  assert_true(@text.read_ion(@text.write_ion(minimum)).equals(minimum))
  for input in ["1d2147483648", "1d-2147483649", "0.1d-2147483648"] {
    assert_true(is_rejected(input))
  }
  let zero = @ion.Decimal::negative_zero_at(-2147483648)
  assert_true(
    @text.read_ion(zero.to_ion_string()).equals(@ion.IonValue::decimal(zero)),
  )
}
