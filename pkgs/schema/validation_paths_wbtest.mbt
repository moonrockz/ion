///|
fn explicit_schema(constraint : Constraint) -> Schema {
  Schema::from_types([TypeDefinition::{ name: "t", constraints: [constraint], }])
}

///|
test "programmatic unresolved type references report value and document paths" {
  let schema = explicit_schema(TypeRef("missing"))
  for
    violations in [
      schema.validate("t", @ion.IonValue::int(1)),
      schema.validate_document("t", []),
      schema.validate_document("missing", []),
    ] {
    assert_eq(violations.length(), 1)
    assert_eq(violations[0].path(), "$")
    assert_eq(violations[0].message(), "unknown schema type: missing")
  }
}

///|
test "document constraints compose through references and logical operators" {
  let schema = Schema::load_from_text(
    "$ion_schema_2_0 type::{name: doc, type: document, element: int} type::{name: alias, type: doc} type::{name: nullable_doc, type: $null_or::doc}",
  )
  for name in ["alias", "nullable_doc"] {
    assert_true(schema.is_valid_document(name, [@ion.IonValue::int(1)]))
    let bad = schema.validate_document(name, [@ion.IonValue::string("bad")])
    assert_eq(bad.length(), 1)
    assert_eq(bad[0].path(), "$[0]")
  }
  let required = Constraint::Element(IsType([Int]))
  for
    (constraint, valid, invalid) in [
      (
        Constraint::AllOf([IsDocument, required]),
        [@ion.IonValue::int(1)],
        [@ion.IonValue::string("bad")],
      ),
      (
        Constraint::AnyOf([IsType([String]), required]),
        [@ion.IonValue::int(1)],
        [@ion.IonValue::string("bad")],
      ),
      (
        Constraint::OneOf([IsDocument, Element(IsType([String]))]),
        [@ion.IonValue::int(1)],
        [@ion.IonValue::string("bad")],
      ),
      (
        Constraint::Not(Element(IsType([String]))),
        [@ion.IonValue::int(1)],
        [@ion.IonValue::string("bad")],
      ),
    ] {
    let schema = explicit_schema(constraint)
    assert_true(schema.is_valid_document("t", valid))
    assert_false(schema.is_valid_document("t", invalid))
  }
  assert_false(
    explicit_schema(OneOf([IsType([Int])])).is_valid_document("t", []),
  )
}

///|
test "text measures reject unknown symbol text and incompatible scalar types" {
  let unknown = @ion.IonValue::symbol_token(@ion.SymbolToken::from_sid(0))
  for
    constraint in [
      Constraint::Utf8ByteLength(0, None),
      CodepointLength(0, None),
    ] {
    let schema = explicit_schema(constraint)
    assert_false(schema.is_valid("t", unknown))
    assert_false(schema.is_valid("t", @ion.IonValue::int(1)))
  }
}

///|
test "programmatic cyclic definitions share the public validation guard" {
  for constraint in [TypeRef("t"), Not(TypeRef("t")), NullOr(TypeRef("t"))] {
    let schema = explicit_schema(constraint)
    for
      violations in [
        schema.validate("t", @ion.IonValue::int(1)),
        schema.validate_document("t", []),
      ] {
      assert_eq(violations.length(), 1)
      assert_eq(violations[0].message(), "cyclic schema type reference: t")
    }
  }
}
