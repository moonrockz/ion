///|
test "NestingDepth enters MAX_NESTING_DEPTH containers from the top" {
  let mut depth = @ion.NestingDepth::top()
  for _ in 0..<@ion.MAX_NESTING_DEPTH {
    depth = depth.enter()
  }
  let deeper = try depth.enter() catch {
    @ion.IonError::LimitExceeded(_) => None
    _ => fail("expected LimitExceeded")
  } noraise {
    depth => Some(depth)
  }
  assert_true(deeper is None)
}

///|
test "IonError::message of LimitExceeded is its text" {
  let error = @ion.IonError::LimitExceeded("too deep")
  assert_eq(error.message(), "too deep")
}
