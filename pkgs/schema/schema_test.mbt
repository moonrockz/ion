// Black-box tests for the Ion Schema loader and validator.

///|
/// ISL 2.0 schema text: `text` after the version marker `$ion_schema_2_0`,
/// unless it has a version marker of its own. Without one, a schema is ISL 1.0.
fn isl2(text : String) -> String {
  if text.contains("$ion_schema_") {
    text
  } else {
    "$ion_schema_2_0 " + text
  }
}

///|
fn load(text : String) -> @schema.Schema? {
  let schema = @schema.Schema::load_from_text(isl2(text)) catch {
    _ => return None
  }
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
test "type-reference annotations are rejected on constraint lists" {
  for (version, annotation) in [("1_0", "nullable"), ("2_0", "$null_or")] {
    for constraint in ["contains", "all_of", "any_of", "one_of"] {
      let item = if constraint == "contains" { "1" } else { "int" }
      let schema = "$ion_schema_\{version} type::{ name: t, \{constraint}: \{annotation}::[\{item}] }"
      assert_true(
        load_error(schema) is Some(@ion.IonError::DataModel(_)),
        msg=schema,
      )
    }
  }
}

///|
test "type-reference annotations still load on references and list items" {
  for (version, annotation) in [("1_0", "nullable"), ("2_0", "$null_or")] {
    for
      constraint in [
        "type: \{annotation}::int",
        "element: \{annotation}::int",
        "not: \{annotation}::int",
        "fields: { a: \{annotation}::int }",
        "all_of: [\{annotation}::int]",
        "any_of: [\{annotation}::int]",
        "one_of: [\{annotation}::int]",
        "ordered_elements: [\{annotation}::int]",
        "type: \{annotation}::{ type: int }",
      ] {
      let schema = "$ion_schema_\{version} type::{ name: t, \{constraint} }"
      assert_true(load(schema) is Some(_), msg=schema)
    }
  }
  assert_true(
    load("$ion_schema_1_0 type::{ name: t, type: type::{ type: int } }")
    is Some(_),
  )
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
  // Annotations are not allowed in the list.
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
test "schemas that ISL 2.0 does not allow do not load" {
  for
    bad in [
      // `occurs` belongs only in `fields` and `ordered_elements`.
      "element: { type: int, occurs: range::[2, max] }", "type: { occurs: optional, type: int }",
      "not: { occurs: 1, type: int }", "any_of: [{ occurs: 1, type: int }]", "fields: { a: $null_or::{ type: int, occurs: 2 } }",
      // An inline type has no name.
       "element: { name: n, type: int }",
      // A type is one reference, not a list.
       "type: [int, string]", "fields: { a: [int] }",
      // `fields` names at least one field, each once, and none 0 times.
       "fields: {}", "fields: { a: int, a: int }", "fields: { a: { occurs: 0 } }",
    ] {
    assert_true(
      load_error("type::{ name: t, \{bad} }")
      is Some(@ion.IonError::DataModel(_)),
      msg=bad,
    )
  }
  // `occurs` in `fields` and `ordered_elements` is fine.
  assert_true(
    load(
      "type::{ name: t, fields: { a: { type: int, occurs: 2 } }, ordered_elements: [{ type: int, occurs: optional }] }",
    )
    is Some(_),
  )
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
  let _ = @schema.Schema::load_from_text(isl2(text)) catch {
    error => return Some(error)
  }
  None
}

///|
test "imports without a resolver raise Unsupported" {
  assert_true(
    load_error("type::{ name: t, type: { id: \"a.isl\", type: a } }")
    is Some(@ion.IonError::Unsupported(_)),
  )
}

///|
test "ordered_elements matches types in order, as often as each occurs" {
  let schema =
    #|type::{
    #|  name: row,
    #|  ordered_elements: [symbol, { type: int, occurs: optional }, { type: number, occurs: range::[0, max] }, bool],
    #|}
  for
    text in ["[a, true]", "[a, 1, true]", "(a 1 2 3.5 false)", "[a, 1.5, true]"] {
    assert_true(accepts(schema, "row", text), msg=text)
  }
  for
    text in ["[]", "[a]", "[1, true]", "[a, true, true]", "{a: 1}", "null.list"] {
    assert_true(!accepts(schema, "row", text), msg=text)
  }
  // Long input needs no backtracking.
  let many = "[a, " + "1, ".repeat(2000) + "true]"
  assert_true(accepts(schema, "row", many))
}

///|
test "documents" {
  let schema = @schema.Schema::load_from_text(
    (
      #|$ion_schema_2_0
      #|type::{ name: ints, element: int, container_length: range::[1, 3] }
      #|type::{ name: doc, type: document }
      #|type::{ name: tagged, annotations: closed::[] }
    ),
  )
  let values = [@ion.IonValue::int(1), @ion.IonValue::int(2)]
  assert_true(schema.is_valid_document("ints", values))
  assert_true(!schema.is_valid_document("ints", []))
  assert_true(!schema.is_valid_document("ints", [@ion.IonValue::symbol("a")]))
  assert_true(schema.is_valid_document("doc", values))
  assert_true(!schema.is_valid("doc", @ion.IonValue::sexp(values)))
  // A document has no annotations to constrain.
  assert_true(!schema.is_valid_document("tagged", values))
}

///|
test "imports: scope, aliases, cycles, and self imports" {
  let schemas : Map[String, String] = {
    "a.isl": "schema_header::{ imports: [{ id: \"b.isl\" }] } type::{ name: a, fields: { b: b } }",
    "b.isl": "schema_header::{ imports: [{ id: \"a.isl\" }, { id: \"c.isl\" }] } type::{ name: b, type: $null_or::a }",
    "c.isl": "type::{ name: c, type: int }",
    "self.isl": "schema_header::{ imports: [{ id: \"self.isl\" }] } type::{ name: s }",
  }
  let resolver = (id : String) => {
    match schemas.get(id) {
      Some(text) => @text.read_ion_datagram(isl2(text))
      None => raise @ion.IonError::DataModel("no schema " + id)
    }
  }
  let load_with = (text : String) => {
    try @schema.Schema::load_from_text(isl2(text), resolver~) catch {
      _ => None
    } noraise {
      schema => Some(schema)
    }
  }
  // a and b import each other.
  let schema = load_with(
    "schema_header::{ imports: [{ id: \"a.isl\", type: a, as: top }] } type::{ name: t, type: top }",
  ).unwrap()
  assert_true(schema.is_valid("t", @text.read_ion("{ b: { b: null } }")))
  assert_true(!schema.is_valid("t", @text.read_ion("{ b: 1 }")))
  assert_true(schema.find("a.isl#a") is Some(_))
  // Inline imports, and whole-schema imports.
  assert_true(
    load_with("type::{ name: t, type: { id: \"c.isl\", type: c } }") is Some(_),
  )
  assert_true(
    load_with(
      "schema_header::{ imports: [{ id: \"c.isl\" }] } type::{ name: t, type: c }",
    )
    is Some(_),
  )
  // c is imported by b, not by this schema.
  assert_true(
    load_with(
      "schema_header::{ imports: [{ id: \"b.isl\" }] } type::{ name: t, type: c }",
    )
    is None,
  )
  for
    bad in [
      "schema_header::{ imports: [{ id: \"self.isl\" }] }", "schema_header::{ imports: [{ id: \"none.isl\" }] }",
      "schema_header::{ imports: [{ id: \"c.isl\", type: d }] }", "schema_header::{ imports: [{ id: \"c.isl\", as: d }] }",
      "schema_header::{ imports: [{ id: \"c.isl\" }] } type::{ name: c }", "type::{ name: t, type: { id: \"c.isl\", type: c, as: d } }",
      "type::{ name: t, type: missing }", "type::{ name: t } type::{ name: t }",
    ] {
    assert_true(load_with(bad) is None, msg=bad)
  }
}

///|
test "field_names, distinct, closed fields, and annotations" {
  let schema =
    #|type::{ name: short_names, field_names: distinct::{ codepoint_length: range::[1, 3] } }
    #|type::{ name: unique, element: distinct::int }
    #|type::{ name: point, fields: closed::{ x: int, y: int } }
    #|type::{ name: tagged, annotations: closed::required::[a, b] }
    #|type::{ name: one_tag, annotations: { container_length: 1 } }
  assert_true(accepts(schema, "short_names", "{a: 1, bcd: 2}"))
  assert_true(!accepts(schema, "short_names", "{a: 1, a: 2}"))
  assert_true(!accepts(schema, "short_names", "{abcd: 1}"))
  assert_true(accepts(schema, "unique", "[1, 2, 3]"))
  assert_true(!accepts(schema, "unique", "[1, 2, 1]"))
  assert_true(!accepts(schema, "unique", "{a: 1, b: 1}"))
  assert_true(accepts(schema, "point", "{x: 1}"))
  assert_true(!accepts(schema, "point", "{x: 1, z: 2}"))
  assert_true(accepts(schema, "tagged", "b::a::1"))
  assert_true(!accepts(schema, "tagged", "a::1"))
  assert_true(!accepts(schema, "tagged", "a::b::c::1"))
  assert_true(accepts(schema, "one_tag", "x::1"))
  assert_true(!accepts(schema, "one_tag", "1"))
  for
    bad in [
      "annotations: [a]", "annotations: required::[a::b]", "annotations: open::[a]",
      "fields: open::{ a: int }", "element: distinct::distinct::int",
    ] {
    assert_true(
      load_error("type::{ name: t, \{bad} }")
      is Some(@ion.IonError::DataModel(_)),
      msg=bad,
    )
  }
}

///|
test "the top level: version marker, header, types, footer, and open content" {
  let schema = load(
    (
      #|"open content" $ion_schema_2_0
      #|schema_header::{ user_reserved_fields: { type: [doc] }, Author: "Ada" }
      #|extra camelCase::{ a: 1 }
      #|type::{ name: t, type: int, doc: "a user field", Note: 1 }
      #|schema_footer::{}
      #|type::{ name: after_the_footer }
    ),
  ).unwrap()
  assert_true(schema.find("t") is Some(_))
  assert_true(schema.find("after_the_footer") is None)
  for
    bad in [
      "$ion_schema_2_0 $ion_schema_2_0", "type::{ name: t } $ion_schema_2_0", "$ion_schema_2_1",
      "a::$ion_schema_2_0", "$ion_schema_2_0 snake_case::1", "schema_header::{} schema_header::{}",
      "type::{ name: t } schema_header::{}", "schema_header::type::{}", "schema_header::null.struct",
      "schema_footer::[]", "type::{ name: t, doc: 1 }", "schema_header::{ reserved_name: 1 }",
      "schema_header::{ user_reserved_fields: { type: [fields] } }", "schema_header::{ user_reserved_fields: { types: [a] } }",
      "schema_header::{ imports: [], imports: [] }",
    ] {
    assert_true(load_error(bad) is Some(@ion.IonError::DataModel(_)), msg=bad)
  }
  assert_true(
    load_error("schema_header::{ imports: [{ id: \"a.isl\" }] }")
    is Some(@ion.IonError::Unsupported(_)),
  )
}

///|
test "a reference to a type that does not exist is an error" {
  assert_true(
    load_error("type::{ name: t, type: missing }")
    is Some(@ion.IonError::DataModel(_)),
  )
  let schema = load("type::{ name: t, type: int }").unwrap()
  assert_true(!schema.is_valid("missing", @ion.IonValue::int(1)))
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
test "a length range takes exclusive bounds, and must be non-negative and satisfiable" {
  let schema = "type::{ name: short, container_length: range::[exclusive::0, exclusive::3] }"
  assert_true(!accepts(schema, "short", "[]"))
  assert_true(accepts(schema, "short", "[1, 2]"))
  assert_true(!accepts(schema, "short", "[1, 2, 3]"))
  for
    bad in [
      "range::[-1, 3]", "range::[3, 2]", "range::[exclusive::1, exclusive::2]", "range::[min, max]",
      "range::[1, 2d0]", "-1", "range::[exclusive::min, 2]",
    ] {
    let error = load_error("type::{ name: t, codepoint_length: \{bad} }")
    assert_true(error is Some(@ion.IonError::DataModel(_)))
  }
}

///|
test "valid_values takes ranges of numbers and of timestamps" {
  let schema =
    #|type::{ name: n, valid_values: range::[exclusive::0, 1.5] }
    #|type::{ name: mixed, valid_values: [a, range::[10, max], range::[min, -10]] }
    #|type::{ name: t, valid_values: range::[2000T, exclusive::2001-01-01T00:00Z] }
  // Numbers compare by exact value, whatever their Ion type.
  assert_true(accepts(schema, "n", "1"))
  assert_true(accepts(schema, "n", "15e-1"))
  assert_true(accepts(schema, "n", "x::1.5000"))
  assert_true(!accepts(schema, "n", "0e0"))
  assert_true(!accepts(schema, "n", "1.50000000000000000000001"))
  assert_true(!accepts(schema, "n", "nan"))
  assert_true(!accepts(schema, "n", "null.int"))
  assert_true(!accepts(schema, "n", "2000T"))
  assert_true(accepts(schema, "mixed", "a"))
  assert_true(accepts(schema, "mixed", "1d1"))
  assert_true(accepts(schema, "mixed", "-inf"))
  assert_true(!accepts(schema, "mixed", "0"))
  // Timestamps compare by instant.
  assert_true(accepts(schema, "t", "2000-06-01T"))
  assert_true(!accepts(schema, "t", "2000-12-31T23:59:59.999-01:00"))
  assert_true(!accepts(schema, "t", "2001T"))
  assert_true(!accepts(schema, "t", "1999-12-31T23:59Z"))
  // A range that contains no value, or mixes kinds, does not load.
  for
    bad in [
      "range::[1, 0]", "range::[exclusive::1, exclusive::1]", "range::[2000T, 3000.0]",
      "range::[min, max]", "range::[1, exclusive::max]", "range::[null.int, 2]",
    ] {
    let error = load_error("type::{ name: t, valid_values: \{bad} }")
    assert_true(error is Some(@ion.IonError::DataModel(_)))
  }
}

///|
test "byte, precision, exponent, and timestamp constraints" {
  let schema =
    #|type::{ name: blob5, byte_length: 5 }
    #|type::{ name: utf8, utf8_byte_length: range::[3, exclusive::5] }
    #|type::{ name: money, precision: range::[1, 5], exponent: -2 }
    #|type::{ name: coarse, timestamp_precision: range::[min, day] }
    #|type::{ name: fine, timestamp_precision: range::[exclusive::second, max] }
    #|type::{ name: local, timestamp_offset: ["+01:00", "-00:00"] }
  assert_true(accepts(schema, "blob5", "{{\"12345\"}}"))
  assert_true(!accepts(schema, "blob5", "{{\"1234\"}}"))
  assert_true(!accepts(schema, "blob5", "\"12345\""))
  // é is two bytes and 😀 four.
  assert_true(accepts(schema, "utf8", "\"aé\""))
  assert_true(accepts(schema, "utf8", "abcd"))
  assert_true(accepts(schema, "utf8", "\"😀\""))
  assert_true(!accepts(schema, "utf8", "\"😀a\""))
  assert_true(accepts(schema, "money", "123.45"))
  assert_true(!accepts(schema, "money", "1234.56"))
  assert_true(!accepts(schema, "money", "12.3"))
  assert_true(!accepts(schema, "money", "12.30e0"))
  assert_true(accepts(schema, "coarse", "2020-01T"))
  assert_true(!accepts(schema, "coarse", "2020-01-01T00:00Z"))
  assert_true(accepts(schema, "fine", "2020-01-01T00:00:00.0Z"))
  assert_true(!accepts(schema, "fine", "2020-01-01T00:00:00Z"))
  assert_true(accepts(schema, "local", "2020-01-01T00:00+01:00"))
  assert_true(accepts(schema, "local", "2020T"))
  assert_true(!accepts(schema, "local", "2020-01-01T00:00Z"))
  for
    bad in [
      "precision: 0", "exponent: range::[2, 1]", "byte_length: -1", "timestamp_precision: hour",
      "timestamp_precision: range::[day, month]", "timestamp_offset: []", "timestamp_offset: [\"+24:00\"]",
      "timestamp_offset: [\"Z\"]",
    ] {
    assert_true(
      load_error("type::{ name: t, \{bad} }")
      is Some(@ion.IonError::DataModel(_)),
      msg=bad,
    )
  }
}

///|
test "ieee754_float accepts the floats a format holds exactly" {
  let schema =
    #|type::{ name: half, ieee754_float: binary16 }
    #|type::{ name: single, ieee754_float: binary32 }
  for
    text in [
      "nan", "+inf", "0e0", "-0e0", "2048e0", "65504e0", "5.960464477539063e-8",
      "0.5e0",
    ] {
    assert_true(accepts(schema, "half", text), msg=text)
  }
  for
    text in [
      "2049e0", "65520e0", "2.9802322387695312e-8", "0.1e0", "1", "null.float",
    ] {
    assert_true(!accepts(schema, "half", text), msg=text)
  }
  assert_true(accepts(schema, "single", "16777216e0"))
  assert_true(!accepts(schema, "single", "16777217e0"))
  assert_true(accepts(schema, "single", "1.401298464324817e-45"))
  assert_true(!accepts(schema, "single", "0.1e0"))
  assert_true(
    load_error("type::{ name: t, ieee754_float: $null_or::binary16 }")
    is Some(@ion.IonError::DataModel(_)),
  )
}

///|
/// Whether the ISL 1.0 schema `schema_text` loads, and its type `type_name`
/// accepts the value `ion_text`.
fn accepts_isl1(
  schema_text : String,
  type_name : String,
  ion_text : String,
) -> Bool {
  let schema = @schema.Schema::load_from_text(schema_text) catch {
    _ => return false
  }
  let value = @text.read_ion(ion_text) catch { _ => return false }
  schema.is_valid(type_name, value)
}

///|
test "ISL 1.0: a schema with no version marker, and the default type any" {
  for marker in ["", "$ion_schema_1_0 "] {
    let schema = marker + "type::{ name: t, codepoint_length: 1 }"
    assert_true(accepts_isl1(schema, "t", "a"), msg=schema)
    // The default type is any, which has no nulls, not ISL 2.0's $any.
    assert_true(!accepts_isl1(schema, "t", "null"), msg=schema)
    assert_true(!accepts_isl1(schema, "t", "null.symbol"), msg=schema)
  }
  let schema = @schema.Schema::load_from_text("type::{ name: t }")
  assert_true(schema.is_valid("t", @ion.IonValue::int(1)))
  // any covers documents too.
  assert_true(schema.is_valid_document("t", []))
}

///|
test "ISL 1.0: nullable:: allows null.null and the typed nulls of the base type" {
  let schema =
    #|$ion_schema_1_0
    #|type::{ name: short, type: nullable::{ type: string, codepoint_length: 1 } }
    #|type::{ name: counts, element: nullable::count }
    #|type::{ name: count, type: int, valid_values: range::[1, max] }
  for text in ["null", "a::null", "null.string", "\"a\""] {
    assert_true(accepts_isl1(schema, "short", text), msg=text)
  }
  for text in ["null.symbol", "\"ab\"", "a"] {
    assert_true(!accepts_isl1(schema, "short", text), msg=text)
  }
  assert_true(accepts_isl1(schema, "counts", "[1, null, null.int]"))
  assert_true(!accepts_isl1(schema, "counts", "[0]"))
  assert_true(!accepts_isl1(schema, "counts", "[null.float]"))
}

///|
test "ISL 1.0: content: closed, scale, and occurs" {
  let schema =
    #|type::{ name: point, content: closed, fields: { x: int, y: int } }
    #|type::{ name: cents, type: decimal, scale: 2 }
    #|type::{ name: short_scale, scale: range::[0, 1] }
    #|type::{ name: pair, element: { type: int, occurs: 2 } }
  assert_true(accepts_isl1(schema, "point", "{ x: 1 }"))
  assert_true(!accepts_isl1(schema, "point", "{ x: 1, z: 2 }"))
  assert_true(accepts_isl1(schema, "cents", "1.23"))
  assert_true(!accepts_isl1(schema, "cents", "1.2"))
  assert_true(accepts_isl1(schema, "short_scale", "12."))
  assert_true(accepts_isl1(schema, "short_scale", "1.2"))
  assert_true(!accepts_isl1(schema, "short_scale", "1.23"))
  // occurs has no meaning in element, but loads.
  assert_true(accepts_isl1(schema, "pair", "[1, 2, 3]"))
}

///|
test "ISL 1.0: annotations lists that are required, ordered, and closed" {
  let schema =
    #|type::{ name: some, annotations: [required::a, b] }
    #|type::{ name: exact, annotations: closed::ordered::[a, optional::b, c] }
    #|type::{ name: in_order, annotations: required::ordered::[a, b] }
  assert_true(accepts_isl1(schema, "some", "x::a::1"))
  assert_true(!accepts_isl1(schema, "some", "b::1"))
  assert_true(accepts_isl1(schema, "exact", "a::c::1"))
  assert_true(accepts_isl1(schema, "exact", "a::b::c::1"))
  assert_true(!accepts_isl1(schema, "exact", "a::c::b::1"))
  assert_true(!accepts_isl1(schema, "exact", "a::x::c::1"))
  assert_true(accepts_isl1(schema, "in_order", "x::a::y::b::z::1"))
  assert_true(!accepts_isl1(schema, "in_order", "b::a::1"))
}

///|
test "ISL 1.0: schemas that ISL 1.0 does not allow do not load" {
  for
    bad in [
      "schema_header::{}", "schema_footer::{}", "type::{ name: t, content: open }",
      "type::{ name: t, type: $null_or::int }", "type::{ name: t, type: nullable::document }",
      "type::{ name: t, fields: { a: nullable::{ type: int, occurs: 2 } } }", "type::{ name: t, occurs: 0 }",
      "type::{ name: t, annotations: { container_length: 1 } }", "type::{ name: t, annotations: required::[a::b] }",
      "type::{ name: t, valid_values: range::[2000T, max] }",
    ] {
    let error = try @schema.Schema::load_from_text(bad) catch {
      error => Some(error)
    } noraise {
      _ => None
    }
    assert_true(error is Some(@ion.IonError::DataModel(_)), msg=bad)
  }
  // ISL 1.0 has no reserved symbols, so these are open content.
  let open = @schema.Schema::load_from_text(
    "schema_header::{ reserved_name: 1 } snake_case::1 type::{ name: t, exponent: 1, doc: 1 } schema_footer::{}",
  )
  assert_true(open.is_valid("t", @ion.IonValue::int(1)))
}

///|
test "ISL 1.0 and ISL 2.0 schemas import each other, and keep their meaning" {
  let schemas : Map[String, String] = {
    "old.isl": "$ion_schema_1_0 type::{ name: no_nulls, not: struct }",
    "new.isl": "$ion_schema_2_0 type::{ name: nulls, not: struct }",
  }
  let resolver = (id : String) => {
    match schemas.get(id) {
      Some(text) => @text.read_ion_datagram(text)
      None => raise @ion.IonError::DataModel("no schema " + id)
    }
  }
  for marker in ["$ion_schema_1_0", "$ion_schema_2_0"] {
    let schema = @schema.Schema::load_from_text(
      marker +
      " schema_header::{ imports: [{ id: \"old.isl\" }, { id: \"new.isl\" }] } type::{ name: a, type: no_nulls } type::{ name: b, type: nulls } schema_footer::{}",
      resolver~,
    )
    assert_true(
      !schema.is_valid("a", @ion.IonValue::typed_null(@ion.IonType::Null)),
      msg=marker,
    )
    assert_true(
      schema.is_valid("b", @ion.IonValue::typed_null(@ion.IonType::Null)),
      msg=marker,
    )
  }
}
