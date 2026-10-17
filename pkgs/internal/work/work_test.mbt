///|
suberror Failed {
  AtLeaf
} derive(Debug, Eq)

///|
async fn descend(
  runner : @work.Runner,
  depth : Int32,
  fail_at_leaf : Bool,
) -> Int32 raise Failed + nocancel {
  runner.pause()
  defer runner.pause()
  if depth == 0 {
    if fail_at_leaf {
      raise AtLeaf
    }
    0
  } else {
    descend(runner, depth - 1, fail_at_leaf) + 1
  }
}

///|
test "100000 levels return and unwind typed errors" {
  let runner = @work.Runner()
  assert_eq(runner.run(() => descend(runner, 100000, false)), 100000)
  let error = try {
    ignore(runner.run(() => descend(runner, 100000, true)))
    None
  } catch {
    error => Some(error)
  }
  assert_eq(error, Some(AtLeaf))
  assert_eq(runner.run(() => descend(runner, 100000, false)), 100000)
}

///|
test "independent nested executors return without an event loop" {
  let outer = @work.Runner()
  let inner = @work.Runner()
  let result = outer.run(() => {
    outer.pause()
    let value = inner.run(() => descend(inner, 10000, false))
    outer.pause()
    value + descend(outer, 10000, false)
  })
  assert_eq(result, 20000)
}
