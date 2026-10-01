///|
test "cookbook products require each field once and reject extra fields" {
  let schema = @schema.Schema::load_from_text(
    @fs.read_file_to_string("docs/cookbook/examples/algebraic-types.isl"),
  )
  for
    valid in [
      "{x: 1.0, y: 2.0}", "{x: 1.0, y: 2.0, label: \"origin\"}", "{x: 1.0, y: 2.0, label: null}",
    ] {
    assert_true(schema.is_valid("point", @text.read_ion(valid)))
  }
  for
    invalid in [
      "{x: 1.0}", "{x: 1.0, x: 2.0, y: 3.0}", "{x: 1.0, y: 2.0, z: 3.0}", "{x: 1, y: 2.0}",
      "{x: 1.0, y: 2.0, label: null.string}", "null.struct",
    ] {
    assert_true(!schema.is_valid("point", @text.read_ion(invalid)))
  }
}

///|
test "cookbook tagged union accepts only the payload of its selected variant" {
  let schema = @schema.Schema::load_from_text(
    @fs.read_file_to_string("docs/cookbook/examples/algebraic-types.isl"),
  )
  for
    value in @text.read_ion_datagram(
      @fs.read_file_to_string("docs/cookbook/examples/shapes.ion"),
    ) {
    assert_true(schema.is_valid("shape", value))
  }
  for
    value in @text.read_ion_datagram(
      @fs.read_file_to_string("docs/cookbook/examples/invalid-shapes.ion"),
    ) {
    assert_true(!schema.is_valid("shape", value))
  }
}

///|
test "cookbook enum uses symbols and annotated option requires exactly one tag" {
  let schema = @schema.Schema::load_from_text(
    @fs.read_file_to_string("docs/cookbook/examples/algebraic-types.isl"),
  )
  assert_true(schema.is_valid("color", @text.read_ion("red")))
  assert_true(!schema.is_valid("color", @text.read_ion("\"red\"")))
  assert_true(!schema.is_valid("color", @text.read_ion("purple")))
  for valid in ["none", "some::42", "some::0"] {
    assert_true(schema.is_valid("option_int", @text.read_ion(valid)))
  }
  for
    invalid in [
      "42", "some::null.int", "some::\"42\"", "some::some::42", "other::some::42",
      "some::none", "null",
    ] {
    assert_true(!schema.is_valid("option_int", @text.read_ion(invalid)))
  }
}

///|
test "cookbook recursive tree validates every child" {
  let schema = @schema.Schema::load_from_text(
    @fs.read_file_to_string("docs/cookbook/examples/algebraic-types.isl"),
  )
  for
    value in @text.read_ion_datagram(
      @fs.read_file_to_string("docs/cookbook/examples/trees.ion"),
    ) {
    assert_true(schema.is_valid("tree", value))
  }
  assert_true(
    !schema.is_valid(
      "tree",
      @text.read_ion("{kind: branch, children: [{kind: leaf, value: \"1\"}]}"),
    ),
  )
}

///|
test "cookbook record validation reports the offending field" {
  let schema = @schema.Schema::load_from_text(
    @fs.read_file_to_string("docs/cookbook/examples/person.isl"),
  )
  let value = @text.read_ion("{name: \"Ada\", born: 1815}")
  assert_true(schema.is_valid("person", value))
  let violations = schema.validate("person", @text.read_ion("{name: 42}"))
  assert_eq(violations.length(), 1)
  assert_eq(violations[0].path(), "$.name")
  assert_eq(violations[0].message(), "expected one of [string] but found int")
}
