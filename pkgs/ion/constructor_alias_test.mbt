///|
test "decimal helper constructs a payload for Ion" {
  let amount : @ion.Decimal = @ion.decimal(123N, -2)
  assert_eq(@text.write_ion(@ion.Ion(amount)), "1.23")
}

///|
test "timestamp helper constructs a payload for Ion" {
  let date : @ion.Timestamp = @ion.timestamp(
    year=2024,
    month=Some(2),
    day=Some(29),
  )
  assert_eq(@text.write_ion(@ion.Ion(date)), "2024-02-29")
  assert_eq(
    @ion.timestamp(year=2024).precision(),
    @ion.TimestampPrecision::Year,
  )
}

///|
test "symbol helper constructs a payload for Ion" {
  let token : @ion.SymbolToken = @ion.symbol("ready")
  assert_eq(token.text(), Some("ready"))
  assert_eq(token.sid(), None)
  assert_eq(@text.write_ion(@ion.Ion(token)), "ready")
}

///|
test "field helper constructs a payload for Ion" {
  let field : @ion.Field = @ion.field(
    "amount",
    @ion.Ion(@ion.decimal(123N, -2)),
  )
  assert_eq(@text.write_ion(@ion.Ion::from_fields([field])), "{amount: 1.23}")
}
