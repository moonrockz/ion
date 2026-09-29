// Loading Ion Schema documents into the constraint model.

///|
/// Reject the annotations of a constraint or an inline type, other than
/// `$null_or::`. An ISL modifier that is not implemented yet (`closed::`,
/// `distinct::`, `required::`) raises `Unsupported`, so it can never silently
/// widen a schema. Any other annotation, such as `range::` where no range is
/// taken, is not ISL 2.0 and raises `DataModel`.
fn reject_unknown_annotations(
  value : @ion.IonValue,
  context : String,
) -> Unit raise @ion.IonError {
  for token in value.annotations() {
    let name = token.require_text()
    if name == "closed" || name == "distinct" || name == "required" {
      raise @ion.IonError::Unsupported(
        "unsupported annotation on " + context + ": " + name,
      )
    }
    if name != "$null_or" {
      raise @ion.IonError::DataModel(
        "the annotation '\{name}' is not allowed on " + context,
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
/// Load a `type::{ ... }` definition. `user_fields` are the reserved symbols
/// the schema header declares as user fields of a type.
fn load_type_definition(
  fields : Array[@ion.Field],
  user_fields : Array[String],
) -> TypeDefinition raise @ion.IonError {
  let name = match field_value(fields, "name") {
    Some(value) => text_of(value)
    None => raise @ion.IonError::DataModel("a type definition needs a 'name'")
  }
  let constraints : Array[Constraint] = []
  for field in fields {
    let key = field.name().require_text()
    if key == "name" || is_user_field(key, user_fields) {
      continue
    }
    constraints.push(load_constraint(key, field.value(), user_fields))
  }
  { name, constraints, }
}

///|
/// Load one constraint by its field name.
fn load_constraint(
  key : String,
  value : @ion.IonValue,
  user_fields : Array[String],
) -> Constraint raise @ion.IonError {
  if !implemented_constraints.contains(key) {
    if isl_keywords.contains(key) {
      raise @ion.IonError::Unsupported(
        "unsupported Ion Schema constraint: " + key,
      )
    }
    raise @ion.IonError::DataModel(
      "'\{key}' is not an Ion Schema 2.0 keyword; declare it in the header's user_reserved_fields to use it as a user field",
    )
  }
  // These take annotations of their own, which their loaders check.
  if key != "container_length" &&
    key != "codepoint_length" &&
    key != "valid_values" &&
    key != "regex" {
    reject_unknown_annotations(value, "constraint '" + key + "'")
  }
  match key {
    "type" => load_type_constraint(value, user_fields)
    "element" => Element(load_inline_type(value, user_fields), occurs_of(value))
    "fields" => Fields(load_fields(value, user_fields))
    "valid_values" => load_valid_values(value)
    "container_length" => {
      let (lower, upper) = load_range(value)
      ContainerLength(lower, upper)
    }
    "codepoint_length" => {
      let (lower, upper) = load_range(value)
      CodepointLength(lower, upper)
    }
    "one_of" => OneOf(load_constraint_list(value, user_fields))
    "any_of" => AnyOf(load_constraint_list(value, user_fields))
    "all_of" => AllOf(load_constraint_list(value, user_fields))
    "not" => Not(load_inline_type(value, user_fields))
    "contains" => Contains(as_list(value))
    "regex" => Matches(load_regex(value))
    _ => panic()
  }
}

///|
/// The constraints `load_constraint` loads.
let implemented_constraints : Array[String] = [
  "type", "element", "fields", "valid_values", "container_length", "codepoint_length",
  "one_of", "any_of", "all_of", "not", "contains", "regex",
]

///|
/// Load a `type:` constraint, honoring the `$null_or::` annotation.
fn load_type_constraint(
  value : @ion.IonValue,
  user_fields : Array[String],
) -> Constraint raise @ion.IonError {
  if has_annotation(value, "$null_or") {
    NullOr(load_type_constraint_bare(value, user_fields))
  } else {
    load_type_constraint_bare(value, user_fields)
  }
}

///|
/// Load a `type:` constraint, ignoring annotations.
fn load_type_constraint_bare(
  value : @ion.IonValue,
  user_fields : Array[String],
) -> Constraint raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Symbol(token) => {
      let name = token.require_text()
      match built_in_type(name) {
        Some(constraint) => constraint
        None => TypeRef(name)
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
    @ion.IonValueKind::Struct(_) => load_inline_type(value, user_fields)
    _ =>
      raise @ion.IonError::DataModel(
        "a type constraint must be a symbol, a list of symbols, or an inline type",
      )
  }
}

///|
/// The Ion types that a built-in type name without a `$` covers.
fn built_in_ion_types(name : String) -> Array[@ion.IonType]? {
  match name {
    "text" => Some([@ion.IonType::String, @ion.IonType::Symbol])
    "lob" => Some([@ion.IonType::Blob, @ion.IonType::Clob])
    "number" =>
      Some([@ion.IonType::Int, @ion.IonType::Float, @ion.IonType::Decimal])
    "any" =>
      Some([
        @ion.IonType::Bool,
        @ion.IonType::Int,
        @ion.IonType::Float,
        @ion.IonType::Decimal,
        @ion.IonType::Timestamp,
        @ion.IonType::Symbol,
        @ion.IonType::String,
        @ion.IonType::Clob,
        @ion.IonType::Blob,
        @ion.IonType::List,
        @ion.IonType::Sexp,
        @ion.IonType::Struct,
      ])
    "null" | "$null" => None
    _ =>
      match @ion.IonType::from_text(name) {
        Some(t) => Some([t])
        None => None
      }
  }
}

///|
/// The constraint of an ISL 2.0 built-in type. A name without a `$`, such as
/// `int` or `text`, covers the non-null values of its Ion types. A name with a
/// `$`, such as `$int` or `$text`, also covers the typed nulls of those types.
/// `$null` covers `null.null`, `$any` every value, and `nothing` no value.
fn built_in_type(name : String) -> Constraint? {
  match name {
    "$any" => Some(Constraint::any())
    "$null" =>
      Some(ValidValues([@ion.IonValue::typed_null(@ion.IonType::Null)]))
    "nothing" => Some(Nothing)
    _ if name.has_prefix("$") =>
      match built_in_ion_types(name.view(start_offset=1).to_owned()) {
        Some(types) =>
          Some(
            AnyOf([
              IsType(types),
              ValidValues(types.map(t => @ion.IonValue::typed_null(t))),
            ]),
          )
        _ => None
      }
    _ => built_in_ion_types(name).map(types => IsType(types))
  }
}

///|
/// Load a `valid_values` constraint: a list of values and ranges, or one
/// range. No other value in the list may have annotations.
fn load_valid_values(value : @ion.IonValue) -> Constraint raise @ion.IonError {
  if value.has_annotations() {
    return InRange(load_value_range(value))
  }
  let values : Array[@ion.IonValue] = []
  let ranges : Array[Constraint] = []
  for item in as_list(value) {
    if has_annotation(item, "range") {
      ranges.push(InRange(load_value_range(item)))
    } else if item.has_annotations() {
      raise @ion.IonError::DataModel(
        "a value in 'valid_values' must not have annotations",
      )
    } else {
      values.push(item)
    }
  }
  if ranges.is_empty() {
    ValidValues(values)
  } else if values.is_empty() && ranges.length() == 1 {
    ranges[0]
  } else {
    AnyOf([ValidValues(values)] + ranges)
  }
}

///|
/// Load a nested type, which is either a symbol or an inline `{ ... }` type.
fn load_inline_type(
  value : @ion.IonValue,
  user_fields : Array[String],
) -> Constraint raise @ion.IonError {
  reject_unknown_annotations(value, "inline type")
  match value.kind() {
    @ion.IonValueKind::Struct(fields) => {
      let constraints : Array[Constraint] = []
      for field in fields {
        let key = field.name().require_text()
        if key == "occurs" || key == "name" || is_user_field(key, user_fields) {
          continue
        }
        constraints.push(load_constraint(key, field.value(), user_fields))
      }
      if constraints.length() == 1 {
        constraints[0]
      } else {
        AllOf(constraints)
      }
    }
    _ => load_type_constraint(value, user_fields)
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
/// Load a length or count: a non-negative integer, or a `range::[lower,
/// upper]` of integers, where a bound may be `exclusive::`, `lower` may be
/// `min`, and `upper` may be `max`. The result is the inclusive range, with
/// `None` for no upper bound.
fn load_range(value : @ion.IonValue) -> (Int, Int?) raise @ion.IonError {
  if !value.has_annotations() {
    let single = int_of(value)
    if single < 0 {
      raise @ion.IonError::DataModel("a length or count must not be negative")
    }
    return (single, Some(single))
  }
  let (lower_value, upper_value) = range_bounds(value)
  let lower = load_int_bound(lower_value, "min")
  let upper = load_int_bound(upper_value, "max")
  if lower is None && upper is None {
    raise @ion.IonError::DataModel("a range needs at least one bound")
  }
  let lower = match lower {
    Some((n, exclusive)) => if exclusive { n + 1 } else { n }
    None => 0
  }
  let upper = upper.map(bound => if bound.1 { bound.0 - 1 } else { bound.0 })
  if lower < 0 {
    raise @ion.IonError::DataModel("a length or count must not be negative")
  }
  if upper is Some(upper) && upper < lower {
    raise @ion.IonError::DataModel("the range contains no value")
  }
  (lower, upper)
}

///|
/// Load one bound of an integer range: the integer and whether it is
/// exclusive, or `None` for `min` or `max`.
fn load_int_bound(
  value : @ion.IonValue,
  open : String,
) -> (Int, Bool)? raise @ion.IonError {
  let (bound, exclusive) = match load_bound(value, open) {
    Unbounded => return None
    Inclusive(bound) => (bound, false)
    Exclusive(bound) => (bound, true)
  }
  match bound.kind() {
    @ion.IonValueKind::Int(n) => Some((n.to_int(), exclusive))
    _ =>
      raise @ion.IonError::DataModel(
        "the bounds of this range must be integers",
      )
  }
}

///|
/// Load a `fields: { ... }` constraint.
fn load_fields(
  value : @ion.IonValue,
  user_fields : Array[String],
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
        let ty = load_inline_type(type_value, user_fields)
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
  user_fields : Array[String],
) -> Array[Constraint] raise @ion.IonError {
  let items = as_list(value)
  let result : Array[Constraint] = []
  for item in items {
    result.push(load_inline_type(item, user_fields))
  }
  result
}

///|
/// Load a `regex`: a non-empty string, annotated with the flags `i` and `m`
/// at most once each.
fn load_regex(value : @ion.IonValue) -> Regex raise @ion.IonError {
  let mut ignore_case = false
  let mut multiline = false
  for token in value.annotations() {
    match token.text() {
      Some("i") if !ignore_case => ignore_case = true
      Some("m") if !multiline => multiline = true
      _ =>
        raise @ion.IonError::DataModel(
          "a regex flag must be 'i' or 'm', each at most once",
        )
    }
  }
  match value.kind() {
    @ion.IonValueKind::String(source) if source != "" =>
      Regex::new(source, ignore_case~, multiline~)
    _ => raise @ion.IonError::DataModel("a regex must be a non-empty string")
  }
}
