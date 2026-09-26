// Loading Ion Schema documents into the constraint model.

///|
/// Load a schema from a parsed schema document: a sequence of
/// `type::{ ... }` definitions, optionally preceded by an Ion Schema version
/// marker such as `$ion_schema_2_0`. Any other top-level value is rejected as
/// unsupported rather than silently ignored.
pub fn Schema::load(
  values : Array[@ion.IonValue],
) -> Schema raise @ion.IonError {
  let types : Array[TypeDefinition] = []
  for value in values {
    if has_annotation(value, "type") {
      match value.kind() {
        @ion.IonValueKind::Struct(fields) =>
          types.push(load_type_definition(fields))
        _ =>
          raise @ion.IonError::DataModel(
            "a 'type' definition must be an Ion struct",
          )
      }
    } else if is_schema_version_marker(value) {
      continue
    } else {
      raise @ion.IonError::Unsupported(
        "only 'type::' definitions are supported at the top level of a schema",
      )
    }
  }
  Schema::from_types(types)
}

///|
/// Whether a top-level value is an Ion Schema version marker such as
/// `$ion_schema_2_0`.
fn is_schema_version_marker(value : @ion.IonValue) -> Bool {
  match value.kind() {
    @ion.IonValueKind::Symbol(token) =>
      match token.text() {
        Some(text) => text.has_prefix("$ion_schema_")
        None => false
      }
    _ => false
  }
}

///|
/// Reject annotations this implementation does not understand, so an
/// unimplemented modifier (such as `closed::`) can never silently widen a
/// schema. `$null_or` is the one handled modifier.
fn reject_unknown_annotations(
  value : @ion.IonValue,
  context : String,
) -> Unit raise @ion.IonError {
  for token in value.annotations() {
    let name = token.require_text()
    if name != "$null_or" {
      raise @ion.IonError::Unsupported(
        "unsupported annotation on " + context + ": " + name,
      )
    }
  }
}

///|
/// Load a schema from Ion Schema text.
pub fn Schema::load_from_text(text : StringView) -> Schema raise @ion.IonError {
  Schema::load(@text.read_ion_datagram(text))
}

///|
/// Whether a value carries the named annotation.
fn has_annotation(value : @ion.IonValue, name : String) -> Bool {
  for token in value.annotations() {
    if token.text() == Some(name) {
      return true
    }
  }
  false
}

///|
/// The value of the named struct field, when present.
fn field_value(fields : Array[@ion.Field], name : String) -> @ion.IonValue? {
  for field in fields {
    if field.name().text() == Some(name) {
      return Some(field.value())
    }
  }
  None
}

///|
/// The text of a symbol or string value.
fn text_of(value : @ion.IonValue) -> String raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::String(text) => text
    @ion.IonValueKind::Symbol(token) => token.require_text()
    _ => raise @ion.IonError::DataModel("expected a symbol or a string")
  }
}

///|
/// The integer value of an Ion `int`.
fn int_of(value : @ion.IonValue) -> Int raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Int(n) => n.to_int()
    _ => raise @ion.IonError::DataModel("expected an integer")
  }
}

///|
/// Load a `type::{ ... }` definition.
fn load_type_definition(
  fields : Array[@ion.Field],
) -> TypeDefinition raise @ion.IonError {
  let name = match field_value(fields, "name") {
    Some(value) => text_of(value)
    None => raise @ion.IonError::DataModel("a type definition needs a 'name'")
  }
  let constraints : Array[Constraint] = []
  for field in fields {
    let key = field.name().require_text()
    if key == "name" {
      continue
    }
    constraints.push(load_constraint(key, field.value()))
  }
  { name, constraints, }
}

///|
/// Load one constraint by its field name.
fn load_constraint(
  key : String,
  value : @ion.IonValue,
) -> Constraint raise @ion.IonError {
  reject_unknown_annotations(value, "constraint '" + key + "'")
  match key {
    "type" => load_type_constraint(value)
    "element" => Element(load_inline_type(value), occurs_of(value))
    "fields" => Fields(load_fields(value))
    "valid_values" => ValidValues(as_list(value))
    "container_length" => {
      let (lower, upper) = load_range(value)
      ContainerLength(lower, upper)
    }
    "codepoint_length" => {
      let (lower, upper) = load_range(value)
      CodepointLength(lower, upper)
    }
    "one_of" => OneOf(load_constraint_list(value))
    "any_of" => AnyOf(load_constraint_list(value))
    "all_of" => AllOf(load_constraint_list(value))
    "not" => Not(load_inline_type(value))
    _ =>
      raise @ion.IonError::Unsupported(
        "unsupported Ion Schema constraint: " + key,
      )
  }
}

///|
/// Load a `type:` constraint, honoring the `$null_or::` annotation.
fn load_type_constraint(
  value : @ion.IonValue,
) -> Constraint raise @ion.IonError {
  if has_annotation(value, "$null_or") {
    NullOr(load_type_constraint_bare(value))
  } else {
    load_type_constraint_bare(value)
  }
}

///|
/// Load a `type:` constraint, ignoring annotations.
fn load_type_constraint_bare(
  value : @ion.IonValue,
) -> Constraint raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Symbol(token) => {
      let name = token.require_text()
      match @ion.IonType::from_text(name) {
        Some(t) => IsType([t])
        None => if name == "$any" { Constraint::any() } else { TypeRef(name) }
      }
    }
    @ion.IonValueKind::List(items) => {
      let types : Array[@ion.IonType] = []
      for item in items {
        match item.kind() {
          @ion.IonValueKind::Symbol(token) => {
            let name = token.require_text()
            match @ion.IonType::from_text(name) {
              Some(t) => types.push(t)
              None =>
                raise @ion.IonError::Unsupported(
                  "unsupported type reference: " + name,
                )
            }
          }
          _ =>
            raise @ion.IonError::DataModel("type list entries must be symbols")
        }
      }
      IsType(types)
    }
    _ =>
      raise @ion.IonError::DataModel(
        "a type constraint must be a symbol or a list of symbols",
      )
  }
}

///|
/// Load a nested type, which is either a symbol or an inline `{ ... }` type.
fn load_inline_type(value : @ion.IonValue) -> Constraint raise @ion.IonError {
  reject_unknown_annotations(value, "inline type")
  match value.kind() {
    @ion.IonValueKind::Struct(fields) => {
      let constraints : Array[Constraint] = []
      for field in fields {
        let key = field.name().require_text()
        if key == "occurs" || key == "name" {
          continue
        }
        constraints.push(load_constraint(key, field.value()))
      }
      if constraints.length() == 1 {
        constraints[0]
      } else {
        AllOf(constraints)
      }
    }
    _ => load_type_constraint(value)
  }
}

///|
/// Load an `occurs` value, when present.
fn occurs_of(value : @ion.IonValue) -> Occurs? raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Struct(fields) =>
      match field_value(fields, "occurs") {
        Some(occurs) => Some(load_occurs(occurs))
        None => None
      }
    _ => None
  }
}

///|
/// Load an `occurs` value.
fn load_occurs(value : @ion.IonValue) -> Occurs raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Symbol(token) => {
      let name = token.require_text()
      match name {
        "required" => Occurs::required()
        "optional" => Occurs::optional()
        _ => raise @ion.IonError::DataModel("unknown occurs value: " + name)
      }
    }
    @ion.IonValueKind::Int(n) => {
      let count = n.to_int()
      if count < 0 {
        raise @ion.IonError::DataModel("occurs count must be non-negative")
      }
      Occurs::new(count, Some(count))
    }
    @ion.IonValueKind::List(_) => {
      let (lower, upper) = load_range(value)
      Occurs::new(lower, upper)
    }
    _ => raise @ion.IonError::DataModel("invalid occurs value")
  }
}

///|
/// Load a `range::[lower, upper]`, where `upper` may be `max` for unbounded.
fn load_range(value : @ion.IonValue) -> (Int, Int?) raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::List(items) => {
      if items.length() != 2 {
        raise @ion.IonError::DataModel(
          "a range needs a lower and an upper bound",
        )
      }
      let lower = int_of(items[0])
      let upper = match items[1].kind() {
        @ion.IonValueKind::Int(n) => Some(n.to_int())
        @ion.IonValueKind::Symbol(token) =>
          if token.text() == Some("max") {
            None
          } else {
            raise @ion.IonError::DataModel("invalid range upper bound")
          }
        _ => raise @ion.IonError::DataModel("invalid range upper bound")
      }
      (lower, upper)
    }
    _ => {
      let single = int_of(value)
      (single, Some(single))
    }
  }
}

///|
/// Load a `fields: { ... }` constraint.
fn load_fields(
  value : @ion.IonValue,
) -> Array[FieldConstraint] raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Struct(fields) => {
      let result : Array[FieldConstraint] = []
      for field in fields {
        let name = field.name().require_text()
        if name == "closed" || name == "content" {
          raise @ion.IonError::Unsupported(
            "the 'closed' fields modifier is not supported yet",
          )
        }
        let type_value = field.value()
        let ty = load_inline_type(type_value)
        let occurs = match occurs_of(type_value) {
          Some(occurs) => occurs
          None => Occurs::optional()
        }
        result.push({ name, ty, occurs, })
      }
      result
    }
    _ => raise @ion.IonError::DataModel("a fields constraint must be a struct")
  }
}

///|
/// A value that must be a list, as an array.
fn as_list(value : @ion.IonValue) -> Array[@ion.IonValue] raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::List(items) => items
    _ => raise @ion.IonError::DataModel("expected a list")
  }
}

///|
/// Load a list of nested constraints.
fn load_constraint_list(
  value : @ion.IonValue,
) -> Array[Constraint] raise @ion.IonError {
  let items = as_list(value)
  let result : Array[Constraint] = []
  for item in items {
    result.push(load_inline_type(item))
  }
  result
}
