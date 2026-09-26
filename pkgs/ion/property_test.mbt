// Property-based tests for the Ion core data model.
//
// Numbers keep exact precision, so `parse(render(x)) == x` is a meaningful law
// for decimals and timestamps; QuickCheck supplies the components.

///|
test "decimal text round-trips through parsing" {
  @quickcheck.check((pair : (BigInt, Int)) => {
    // Keep the exponent small: the value is arbitrary precision, but the
    // exponent travels as an Ion `int` and the parser reads it back as one.
    let original = @ion.Decimal::new(pair.0, pair.1 % 1000)
    let reparsed = @ion.Decimal::parse(original.to_ion_string())
    reparsed.coefficient().equal(original.coefficient()) &&
    reparsed.exponent() == original.exponent() &&
    reparsed.is_negative_zero() == original.is_negative_zero()
  })
}

///|
test "timestamp text round-trips through parsing" {
  @quickcheck.check((seed : (Int, Int, Int, Int, Int, Int)) => {
    let original = @ion.Timestamp::new(
      year=2000 + (seed.0 & 0xFF),
      month=Some((seed.1 & 0x0F) % 12 + 1),
      day=Some((seed.2 & 0x1F) % 28 + 1),
      hour=Some((seed.3 & 0x1F) % 24),
      minute=Some((seed.4 & 0x3F) % 60),
      second=Some((seed.5 & 0x3F) % 60),
      offset=Some(@ion.TimestampOffset::Known(0)),
    )
    @ion.Timestamp::parse(original.to_ion_string()).to_ion_string() ==
    original.to_ion_string()
  })
}
