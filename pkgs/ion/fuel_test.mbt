///|
test "fuel budgets are positive domain values" {
  assert_eq(@ion.Budget(1).units(), 1)
  assert_eq(@ion.Budget(1000).units(), 1000)
  for units in [0, -1] {
    let invalid = try @ion.Budget(units) catch {
      @ion.IonError::DataModel(_) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(invalid)
  }
}

///|
test "fuel exhaustion carries the budget operation and location" {
  let error = @ion.IonError::FuelExhausted(
    budget=@ion.Budget(2),
    operation=TextRead,
    location=TextOffset(3),
  )
  assert_eq(
    error.message(),
    "fuel budget of 2 exhausted during TextRead at TextOffset(3)",
  )
}
