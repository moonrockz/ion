// Black-box tests for the core data model.

///|
test "decimal preserves coefficient, exponent, and signed zero" {
  let d = @ion.Decimal::parse("-1.230d2")
  assert_eq(d.coefficient().to_string(), "-1230")
  assert_eq(d.exponent(), -1)
  assert_eq(d.to_ion_string(), "-1230d-1")
  let zero = @ion.Decimal::parse("-0.0")
  assert_true(zero.is_zero())
  assert_true(zero.is_negative_zero())
  assert_eq(zero.to_ion_string(), "-0d-1")
}

///|
test "timestamp derives precision from its components" {
  let year = @ion.Timestamp::parse("2007T")
  assert_eq(year.precision(), @ion.TimestampPrecision::Year)
  assert_eq(year.month(), None)
  let minute = @ion.Timestamp::parse("2007-02-23T12:14Z")
  assert_eq(minute.precision(), @ion.TimestampPrecision::Minute)
  assert_eq(minute.offset(), Some(@ion.TimestampOffset::Known(0)))
  let second = @ion.Timestamp::parse("2007-02-23T12:14:33.079-08:00")
  assert_eq(second.precision(), @ion.TimestampPrecision::Second)
  assert_eq(second.offset(), Some(@ion.TimestampOffset::Known(-480)))
  assert_eq(second.fraction().unwrap().coefficient().to_string(), "79")
}

///|
test "Ion types expose their names" {
  assert_eq(@ion.IonType::from_text("sexp"), Some(@ion.IonType::Sexp))
  assert_eq(@ion.IonType::from_text("$null"), Some(@ion.IonType::Null))
  assert_eq(@ion.IonType::from_text("nope"), None)
  assert_eq(@ion.IonType::Struct.to_text(), "struct")
  assert_true(@ion.IonType::List.is_container())
  assert_true(!@ion.IonType::Int.is_container())
}

///|
test "values compare structurally and keep annotations" {
  let a = @ion.IonValue::list([
    @ion.IonValue::int(1),
    @ion.IonValue::string("x"),
  ])
  let b = @ion.IonValue::list([
    @ion.IonValue::int(1),
    @ion.IonValue::string("x"),
  ])
  assert_true(a.equals(b))
  let annotated = @ion.IonValue::int(1).with_annotation(
    @ion.SymbolToken::new("int32"),
  )
  assert_true(annotated.has_annotations())
  assert_true(!annotated.equals(@ion.IonValue::int(1)))
}

///|
test "typed nulls report their own type" {
  let null_int = @ion.IonValue::typed_null(@ion.IonType::Int)
  assert_true(null_int.is_null())
  assert_true(!null_int.is_untyped_null())
  assert_eq(null_int.ion_type(), @ion.IonType::Int)
  assert_true(@ion.IonValue::untyped_null().is_untyped_null())
}

///|
test "struct equality ignores field order" {
  let a = @ion.IonValue::from_fields([
    @ion.Field::new("a", @ion.IonValue::int(1)),
    @ion.Field::new("b", @ion.IonValue::int(2)),
  ])
  let b = @ion.IonValue::from_fields([
    @ion.Field::new("b", @ion.IonValue::int(2)),
    @ion.Field::new("a", @ion.IonValue::int(1)),
  ])
  assert_true(a.equals(b))
}
