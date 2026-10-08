// The test kit is test code for the other packages, so its own tests check
// that each helper builds what its name says.

///|
test "deep_value nests the requested number of containers" {
  let shapes : Array[@testkit.DeepShape] = [
    List,
    Sexp,
    Struct,
    AnnotatedList,
    Mixed,
  ]
  for shape in shapes {
    let (leaf, depth) = @testkit.innermost(@testkit.deep_value(shape, 5))
    assert_eq(depth, 5)
    assert_true(leaf.kind() is Int(_))
  }
}

///|
test "deep_value spells each shape as its name says" {
  inspect(@text.write_ion(@testkit.deep_value(List, 2)), content="[[1]]")
  inspect(@text.write_ion(@testkit.deep_value(Sexp, 2)), content="((1))")
  inspect(
    @text.write_ion(@testkit.deep_value(Struct, 2)),
    content="{name: {name: 1}}",
  )
  inspect(
    @text.write_ion(@testkit.deep_value(AnnotatedList, 2)),
    content="name::[name::[1]]",
  )
  inspect(
    @text.write_ion(@testkit.deep_value(Mixed, 4)),
    content="[{name: ([1])}]",
  )
}

///|
test "deep_value builds and frees 100,000 levels on every target" {
  let shapes : Array[@testkit.DeepShape] = [List, Struct, Mixed]
  for shape in shapes {
    let (_, depth) = @testkit.innermost(@testkit.deep_value(shape, 100_000))
    assert_eq(depth, 100_000)
  }
}

///|
test "reference_equals follows the Ion data model" {
  fn read(text : String) -> @ion.IonValue raise {
    @text.read_ion(text)
  }
  assert_true(
    @testkit.reference_equals(read("{a: 1, b: 2}"), read("{b: 2, a: 1}")),
  )
  assert_true(@testkit.reference_equals(read("nan"), read("nan")))
  assert_true(!@testkit.reference_equals(read("0e0"), read("-0e0")))
  assert_true(!@testkit.reference_equals(read("1.0"), read("1.00")))
  assert_true(
    !@testkit.reference_equals(read("{a: 1, a: 1}"), read("{a: 1, a: 2}")),
  )
  assert_true(!@testkit.reference_equals(read("x::1"), read("1")))
  assert_true(!@testkit.reference_equals(read("[]"), read("()")))
}

///|
test "count_values counts every value, containers included" {
  assert_eq(
    @testkit.count_values(@text.read_ion("[1, {a: (2 3)}, x::null.list]")),
    7,
  )
}
