///|
test "schema loader rejects invalid ISL 1 annotation lists" {
  for
    body in ["annotations: 1", "annotations: [foo::a]", "fields: foo::{a: int}"] {
    assert_true(
      load_error("$ion_schema_1_0 type::{name:t, " + body + "}")
      is Some(@ion.IonError::DataModel(_)),
    )
  }
}

///|
test "ISL 1 closed structs and unbounded scale have precise behavior" {
  let closed = @schema.Schema::load_from_text(
    "$ion_schema_1_0 type::{name:t, content:closed}",
  )
  assert_true(closed.is_valid("t", @text.read_ion("{}")))
  assert_false(closed.is_valid("t", @text.read_ion("{extra:1}")))
  let scale = @schema.Schema::load_from_text(
    "$ion_schema_1_0 type::{name:t, type:decimal, scale:range::[0,max]}",
  )
  assert_true(scale.is_valid("t", @text.read_ion("1.00")))
  assert_false(scale.is_valid("t", @text.read_ion("1d2")))
  let range = @schema.Schema::load_from_text(
    "$ion_schema_2_0 type::{name:t, valid_values:[range::[1,3]]}",
  )
  assert_true(range.is_valid("t", @ion.IonValue::int(2)))
  assert_false(range.is_valid("t", @ion.IonValue::int(4)))
}

///|
test "ISL 1 nullable types resolve defaults and recursive base types" {
  let schema = @schema.Schema::load_from_text(
    "$ion_schema_1_0 type::{name:unconstrained} type::{name:defaults,type:nullable::unconstrained} type::{name:inline_default,type:nullable::{container_length:0}} type::{name:all,type:nullable::any} type::{name:empty,type:nullable::nothing} type::{name:a,type:b} type::{name:b,type:a} type::{name:cycle,type:nullable::a}",
  )
  assert_true(schema.is_valid("defaults", @ion.IonValue::typed_null(String)))
  assert_true(
    schema.is_valid("inline_default", @ion.IonValue::typed_null(Struct)),
  )
  assert_true(schema.is_valid("all", @ion.IonValue::typed_null(Int)))
  assert_false(schema.is_valid("empty", @ion.IonValue::typed_null(Int)))
  let constraints = schema.find("cycle").unwrap().constraints()
  guard constraints[0] is AnyOf([ValidValues(nulls), _]) else {
    fail("expected nullable cycle constraint")
  }
  assert_eq(nulls.length(), 1)
  assert_true(nulls[0].is_null() && nulls[0].ion_type() == Null)
}

///|
test "ISL 1 annotation modifiers and offset digits are checked" {
  for
    body in [
      "annotations:unknown::[a]", "annotations:required::required::[a]", "annotations:[required::optional::a]",
      "timestamp_offset:[\"+ab:00\"]",
    ] {
    assert_true(
      load_error("$ion_schema_1_0 type::{name:t, " + body + "}")
      is Some(@ion.IonError::DataModel(_)),
      msg=body,
    )
  }
}

///|
test "undefined built-in-like names and unsupported reserved constraints are rejected" {
  for type_name in ["'null'", "$missing"] {
    assert_true(
      load_error("$ion_schema_2_0 type::{name:t, type:" + type_name + "}")
      is Some(@ion.IonError::DataModel(_)),
    )
  }
  assert_true(
    load_error("$ion_schema_2_0 type::{name:t, id:\"x\"}")
    is Some(@ion.IonError::Unsupported(_)),
  )
}
