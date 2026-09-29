// Black-box tests for the Ion Schema loader and validator.

///|
fn load(text : String) -> @schema.Schema? {
  let schema = @schema.Schema::load_from_text(text) catch { _ => return None }
  Some(schema)
}

///|
fn accepts(schema_text : String, type_name : String, ion_text : String) -> Bool {
  let schema = match load(schema_text) {
    Some(schema) => schema
    None => return false
  }
  let value = @text.read_ion(ion_text) catch { _ => return false }
  schema.is_valid(type_name, value)
}

///|
test "a core type does not match nulls, and its $ type matches its typed null" {
  let schema = "type::{ name: my_int, type: int } type::{ name: maybe_int, type: $int }"
  assert_true(accepts(schema, "my_int", "42"))
  assert_true(!accepts(schema, "my_int", "null.int"))
  assert_true(!accepts(schema, "my_int", "\"x\""))
  assert_true(!accepts(schema, "my_int", "null"))
  assert_true(accepts(schema, "maybe_int", "42"))
  assert_true(accepts(schema, "maybe_int", "null.int"))
  assert_true(!accepts(schema, "maybe_int", "null"))
  assert_true(!accepts(schema, "maybe_int", "null.string"))
}

///|
test "$null_or admits null.null but no other null" {
  let schema = "type::{ name: t, type: $null_or::string }"
  assert_true(accepts(schema, "t", "null"))
  assert_true(accepts(schema, "t", "a::null"))
  assert_true(accepts(schema, "t", "\"x\""))
  assert_true(!accepts(schema, "t", "null.string"))
}

///|
test "text, lob, number, and any cover several Ion types" {
  let schema = "type::{ name: t, type: text } type::{ name: n, type: number } type::{ name: a, type: any }"
  assert_true(accepts(schema, "t", "sym"))
  assert_true(accepts(schema, "t", "\"str\""))
  assert_true(!accepts(schema, "t", "1"))
  assert_true(accepts(schema, "n", "1.5"))
  assert_true(!accepts(schema, "n", "null.int"))
  assert_true(accepts(schema, "a", "{}"))
  assert_true(!accepts(schema, "a", "null"))
}

///|
test "element applies to the field values of a struct" {
  let schema = "type::{ name: ints, element: int }"
  assert_true(accepts(schema, "ints", "{a: 1, b: 2}"))
  assert_true(!accepts(schema, "ints", "{a: 1, b: x}"))
  assert_true(!accepts(schema, "ints", "null.struct"))
}

///|
test "valid_values ignores the value's annotations" {
  let schema = "type::{ name: t, valid_values: [true] }"
  assert_true(accepts(schema, "t", "foo::true"))
  // A range in valid_values is not supported, and annotations are not allowed.
  assert_true(load("type::{ name: t, valid_values: [range::[1, 2]] }") is None)
  assert_true(load("type::{ name: t, valid_values: [a::1] }") is None)
}

///|
test "element constraint applies to every element" {
  let schema = "type::{ name: int_list, type: list, element: int }"
  assert_true(accepts(schema, "int_list", "[1, 2, 3]"))
  assert_true(accepts(schema, "int_list", "[]"))
  assert_true(!accepts(schema, "int_list", "[1, \"x\"]"))
  assert_true(!accepts(schema, "int_list", "1"))
}

///|
test "element occurrence range counts elements" {
  let schema = "type::{ name: pair, element: { type: int, occurs: range::[2, max] } }"
  assert_true(accepts(schema, "pair", "[1, 2]"))
  assert_true(accepts(schema, "pair", "[1, 2, 3]"))
  assert_true(!accepts(schema, "pair", "[1]"))
}

///|
test "fields constraint honors required and optional fields" {
  let schema = "type::{ name: person, fields: { name: { type: string, occurs: required }, age: int } }"
  assert_true(accepts(schema, "person", "{name: \"a\"}"))
  assert_true(accepts(schema, "person", "{name: \"a\", age: 3}"))
  assert_true(!accepts(schema, "person", "{}"))
  assert_true(!accepts(schema, "person", "{name: 1}"))
}

///|
test "valid_values" {
  let schema = "type::{ name: color, valid_values: [red, green, blue] }"
  assert_true(accepts(schema, "color", "red"))
  assert_true(!accepts(schema, "color", "yellow"))
}

///|
test "null_or accepts null and the annotated type" {
  let schema = "type::{ name: maybe_int, type: $null_or::int }"
  assert_true(accepts(schema, "maybe_int", "null"))
  assert_true(accepts(schema, "maybe_int", "7"))
  assert_true(!accepts(schema, "maybe_int", "\"x\""))
}

///|
test "one_of and not" {
  let schema = "type::{ name: t, one_of: [ { type: int }, { type: string } ] }"
  assert_true(accepts(schema, "t", "1"))
  assert_true(accepts(schema, "t", "\"a\""))
  assert_true(!accepts(schema, "t", "true"))
  let negated = "type::{ name: not_two, type: int, not: { valid_values: [2] } }"
  assert_true(accepts(negated, "not_two", "1"))
  assert_true(!accepts(negated, "not_two", "2"))
}

///|
test "type references resolve within the schema" {
  let schema = "type::{ name: small, type: int, valid_values: [1, 2, 3] } type::{ name: use, type: small }"
  assert_true(accepts(schema, "use", "2"))
  assert_true(!accepts(schema, "use", "9"))
}

///|
test "length constraints" {
  let containers = "type::{ name: pair, container_length: 2 }"
  assert_true(accepts(containers, "pair", "[1, 2]"))
  assert_true(!accepts(containers, "pair", "[1]"))
  let codes = "type::{ name: two_chars, codepoint_length: 2 }"
  assert_true(accepts(codes, "two_chars", "\"ab\""))
  assert_true(!accepts(codes, "two_chars", "\"abc\""))
}

///|
fn load_error(text : String) -> @ion.IonError? {
  let _ = @schema.Schema::load_from_text(text) catch {
    error => return Some(error)
  }
  None
}

///|
test "unsupported constructs raise Unsupported" {
  let annotations = load_error("type::{ name: t, annotations: [foo] }")
  assert_true(annotations is Some(@ion.IonError::Unsupported(_)))
  let ordered = load_error("type::{ name: t, ordered_elements: [int] }")
  assert_true(ordered is Some(@ion.IonError::Unsupported(_)))
  let closed = load_error("type::{ name: t, fields: closed::{ a: int } }")
  assert_true(closed is Some(@ion.IonError::Unsupported(_)))
}

///|
test "version markers are accepted and other top-level values are not" {
  let schema = load("$ion_schema_2_0 type::{ name: t, type: int }").unwrap()
  assert_true(schema.find("t") is Some(_))
  let stray = load_error("type::{ name: t, type: int } extra")
  assert_true(stray is Some(@ion.IonError::Unsupported(_)))
}

///|
test "unknown type references are reported" {
  let schema = load("type::{ name: t, type: missing }").unwrap()
  assert_true(!schema.is_valid("t", @ion.IonValue::int(1)))
}

///|
test "valid_values compares structs without field order" {
  let schema = "type::{ name: t, valid_values: [{ a: 1, b: 2 }] }"
  assert_true(accepts(schema, "t", "{ b: 2, a: 1 }"))
}

///|
test "contains matches values in a list, sexp, or struct" {
  let schema = "type::{ name: has_high, contains: [high] }"
  assert_true(accepts(schema, "has_high", "[low, high]"))
  assert_true(!accepts(schema, "has_high", "[low]"))
  assert_true(accepts(schema, "has_high", "(low high)"))
  assert_true(accepts(schema, "has_high", "{a: 1, b: high}"))
  assert_true(!accepts(schema, "has_high", "{a: 1}"))
  // A non-container cannot contain a value.
  assert_true(!accepts(schema, "has_high", "high"))
}

///|
test "length constraints accept a range" {
  let containers = "type::{ name: short, container_length: range::[1, 3] }"
  assert_true(accepts(containers, "short", "[1, 2]"))
  assert_true(!accepts(containers, "short", "[]"))
  assert_true(!accepts(containers, "short", "[1, 2, 3, 4]"))
  let codes = "type::{ name: code, codepoint_length: range::[2, max] }"
  assert_true(accepts(codes, "code", "\"abcdef\""))
  assert_true(!accepts(codes, "code", "\"a\""))
}

///|
test "an exclusive range bound is unsupported" {
  let error = load_error(
    "type::{ name: short, container_length: range::[exclusive::0, 3] }",
  )
  assert_true(error is Some(@ion.IonError::Unsupported(_)))
}
