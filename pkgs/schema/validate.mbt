// Validating Ion values against a loaded schema.

///|
/// A single way in which a value fails to satisfy a schema type.
pub struct Violation {
  path : String
  message : String
} derive(Debug)

///|
/// The location within the value where the violation occurred (`$`, `$.field`,
/// `$[0]`, ...).
pub fn Violation::path(self : Violation) -> String {
  self.path
}

///|
/// The human-readable reason for the violation.
pub fn Violation::message(self : Violation) -> String {
  self.message
}

///|
/// Validate `value` against the named schema type, returning every violation
/// found. An empty result means the value is valid.
pub fn Schema::validate(
  self : Schema,
  type_name : String,
  value : @ion.IonValue,
) -> Array[Violation] {
  let out : Array[Violation] = []
  match self.find(type_name) {
    None =>
      out.push({ path: "$", message: "unknown schema type: " + type_name, })
    Some(definition) =>
      for constraint in definition.constraints() {
        check_constraint(self, constraint, value, "$", out)
      }
  }
  out
}

///|
/// Whether `value` satisfies the named schema type.
pub fn Schema::is_valid(
  self : Schema,
  type_name : String,
  value : @ion.IonValue,
) -> Bool {
  self.validate(type_name, value).is_empty()
}

///|
/// Whether `n` is within `lower..=upper` (or `lower..` when `upper` is `None`).
fn in_range(n : Int, lower : Int, upper : Int?) -> Bool {
  if n < lower {
    return false
  }
  match upper {
    Some(max) => n <= max
    None => true
  }
}

///|
/// Whether `value` satisfies `constraint`, discarding any detail.
fn satisfies(
  schema : Schema,
  constraint : Constraint,
  value : @ion.IonValue,
) -> Bool {
  let out : Array[Violation] = []
  check_constraint(schema, constraint, value, "$", out)
  out.is_empty()
}

///|
/// Check `value` against `constraint`, appending violations to `out`.
fn check_constraint(
  schema : Schema,
  constraint : Constraint,
  value : @ion.IonValue,
  path : String,
  out : Array[Violation],
) -> Unit {
  match constraint {
    IsType(types) => {
      let actual = value.ion_type()
      // A typed null is not a value of its type; `$int` and `$null_or::`
      // admit nulls.
      let mut ok = false
      for allowed in types {
        if allowed == actual {
          ok = true
        }
      }
      if !ok || value.is_null() {
        let found = if value.is_null() {
          "null.\{actual.to_text()}"
        } else {
          actual.to_text()
        }
        out.push({
          path,
          message: "expected \{describe_types(types)} but found \{found}",
        })
      }
    }
    NullOr(inner) =>
      if !(value.is_null() && value.ion_type() == @ion.IonType::Null) {
        check_constraint(schema, inner, value, path, out)
      }
    TypeRef(name) =>
      match schema.find(name) {
        None => out.push({ path, message: "unknown schema type: " + name, })
        Some(definition) =>
          for inner in definition.constraints() {
            check_constraint(schema, inner, value, path, out)
          }
      }
    Element(inner, occurs) =>
      match value.kind() {
        @ion.IonValueKind::List(items) =>
          check_elements(schema, inner, occurs, items, path, out)
        @ion.IonValueKind::Sexp(items) =>
          check_elements(schema, inner, occurs, items, path, out)
        @ion.IonValueKind::Struct(fields) =>
          check_elements(
            schema,
            inner,
            occurs,
            fields.map(field => field.value()),
            path,
            out,
          )
        _ =>
          out.push({
            path,
            message: "an element constraint requires a list, sexp, or struct",
          })
      }
    Fields(field_constraints) =>
      match value.kind() {
        @ion.IonValueKind::Struct(fields) =>
          check_fields(schema, field_constraints, fields, path, out)
        _ =>
          out.push({ path, message: "a fields constraint requires a struct", })
      }
    ValidValues(values) => {
      // The value's own annotations do not count.
      let bare = value.with_annotations([])
      let mut ok = false
      for candidate in values {
        if bare.equals(candidate) {
          ok = true
        }
      }
      if !ok {
        out.push({ path, message: "value is not one of the allowed values", })
      }
    }
    InRange(range) =>
      if !range.contains(value) {
        out.push({ path, message: "value is not in the range", })
      }
    Matches(regex) => {
      let text = match value.kind() {
        @ion.IonValueKind::String(text) => Some(text)
        @ion.IonValueKind::Symbol(token) => token.text()
        _ => None
      }
      match text {
        Some(text) =>
          if !regex.matches(text) {
            out.push({
              path,
              message: "value does not match the regex \{regex.source()}",
            })
          }
        None =>
          out.push({
            path,
            message: "a regex constraint requires a string or symbol",
          })
      }
    }
    ByteLength(lower, upper) =>
      check_measure(
        byte_length(value),
        lower,
        upper,
        "byte length",
        "a blob or clob",
        path,
        out,
      )
    Utf8ByteLength(lower, upper) =>
      check_measure(
        utf8_byte_length(value),
        lower,
        upper,
        "UTF-8 byte length",
        "a string or symbol",
        path,
        out,
      )
    Precision(lower, upper) =>
      check_measure(
        decimal_of(value).map(d => digits(d.coefficient())),
        lower,
        upper,
        "precision",
        "a decimal",
        path,
        out,
      )
    Exponent(lower, upper) =>
      check_measure(
        decimal_of(value).map(d => d.exponent()),
        lower,
        upper,
        "exponent",
        "a decimal",
        path,
        out,
      )
    TimestampPrecision(lower, upper) =>
      check_measure(
        timestamp_of(value).map(timestamp_precision),
        lower,
        upper,
        "timestamp precision",
        "a timestamp",
        path,
        out,
      )
    TimestampOffsets(offsets) =>
      match timestamp_of(value) {
        None =>
          out.push({
            path,
            message: "a timestamp_offset constraint requires a timestamp",
          })
        Some(timestamp) => {
          let offset = timestamp
            .offset()
            .unwrap_or(@ion.TimestampOffset::Unknown)
          if !offsets.contains(offset) {
            out.push({ path, message: "the timestamp's offset is not allowed", })
          }
        }
      }
    Ieee754Float(format) =>
      match value.kind() {
        @ion.IonValueKind::Float(f) =>
          if !fits_format(f, format) {
            out.push({
              path,
              message: "the float is not exact in \{format.to_repr()}",
            })
          }
        _ =>
          out.push({
            path,
            message: "an ieee754_float constraint requires a float",
          })
      }
    FieldNames(inner) =>
      match value.kind() {
        @ion.IonValueKind::Struct(fields) =>
          for field in fields {
            check_constraint(
              schema,
              inner,
              @ion.IonValue::symbol_token(field.name()),
              path + ".(field name)",
              out,
            )
          }
        _ =>
          out.push({
            path,
            message: "a field_names constraint requires a struct",
          })
      }
    DistinctFieldNames =>
      match value.kind() {
        @ion.IonValueKind::Struct(fields) => {
          let names = fields.map(field => field.name().text())
          for index, name in names {
            if names[:index].contains(name) {
              out.push({ path, message: "a field name repeats", })
              break
            }
          }
        }
        _ =>
          out.push({
            path,
            message: "a field_names constraint requires a struct",
          })
      }
    DistinctElements => {
      let items = match value.kind() {
        @ion.IonValueKind::List(items) | @ion.IonValueKind::Sexp(items) => items
        @ion.IonValueKind::Struct(fields) => fields.map(field => field.value())
        _ => []
      }
      for index, item in items {
        if items[:index].iter().any(other => other.equals(item)) {
          out.push({ path, message: "an element repeats", })
          break
        }
      }
    }
    ClosedFields(names) =>
      match value.kind() {
        @ion.IonValueKind::Struct(fields) =>
          for field in fields {
            match field.name().text() {
              Some(name) if names.contains(name) => ()
              name =>
                out.push({
                  path,
                  message: "the closed struct has the field \{name.unwrap_or("with unknown text")}",
                })
            }
          }
        _ =>
          out.push({ path, message: "a fields constraint requires a struct", })
      }
    Annotations(inner) => {
      let symbols = @ion.IonValue::list(
        value.annotations().map(token => @ion.IonValue::symbol_token(token)),
      )
      check_constraint(schema, inner, symbols, path + "::", out)
    }
    ContainerLength(lower, upper) =>
      match container_length(value) {
        None =>
          out.push({
            path,
            message: "a container_length constraint requires a container",
          })
        Some(length) =>
          if !in_range(length, lower, upper) {
            out.push({
              path,
              message: "container length \{length} is out of range",
            })
          }
      }
    CodepointLength(lower, upper) =>
      match codepoint_length(value) {
        None =>
          out.push({
            path,
            message: "a codepoint_length constraint requires a string or symbol",
          })
        Some(length) =>
          if !in_range(length, lower, upper) {
            out.push({
              path,
              message: "code point length \{length} is out of range",
            })
          }
      }
    AllOf(constraints) =>
      for inner in constraints {
        check_constraint(schema, inner, value, path, out)
      }
    AnyOf(constraints) => {
      let mut ok = false
      for inner in constraints {
        if satisfies(schema, inner, value) {
          ok = true
        }
      }
      if !ok {
        out.push({ path, message: "value does not satisfy any_of", })
      }
    }
    OneOf(constraints) => {
      let mut count = 0
      for inner in constraints {
        if satisfies(schema, inner, value) {
          count += 1
        }
      }
      if count != 1 {
        out.push({
          path,
          message: "value satisfies \{count} of the one_of constraints, expected exactly 1",
        })
      }
    }
    Not(inner) =>
      if satisfies(schema, inner, value) {
        out.push({ path, message: "value satisfies a 'not' constraint", })
      }
    Nothing =>
      out.push({ path, message: "no value satisfies a 'nothing' constraint", })
    Contains(required) =>
      match value.kind() {
        @ion.IonValueKind::List(items) =>
          check_contains(required, items, path, out)
        @ion.IonValueKind::Sexp(items) =>
          check_contains(required, items, path, out)
        @ion.IonValueKind::Struct(fields) => {
          let members : Array[@ion.IonValue] = []
          for field in fields {
            members.push(field.value())
          }
          check_contains(required, members, path, out)
        }
        _ =>
          out.push({
            path,
            message: "a contains constraint requires a list, sexp, or struct",
          })
      }
  }
}

///|
/// Check a container's elements against `inner`.
fn check_elements(
  schema : Schema,
  inner : Constraint,
  occurs : Occurs?,
  items : Array[@ion.IonValue],
  path : String,
  out : Array[Violation],
) -> Unit {
  match occurs {
    Some(occurs) =>
      if !occurs.allows(items.length()) {
        out.push({
          path,
          message: "element count \{items.length()} is out of range",
        })
      }
    None => ()
  }
  for index in 0..<items.length() {
    check_constraint(
      schema,
      inner,
      items[index],
      path + "[" + index.to_string() + "]",
      out,
    )
  }
}

///|
/// Check a struct's fields against the field constraints.
fn check_fields(
  schema : Schema,
  field_constraints : Array[FieldConstraint],
  fields : Array[@ion.Field],
  path : String,
  out : Array[Violation],
) -> Unit {
  for constraint in field_constraints {
    let matching : Array[@ion.Field] = []
    for field in fields {
      if field.name().text() == Some(constraint.name) {
        matching.push(field)
      }
    }
    let field_path = path + "." + constraint.name
    if !constraint.occurs.allows(matching.length()) {
      out.push({
        path: field_path,
        message: "field occurs \{matching.length()} time(s)",
      })
    }
    for field in matching {
      check_constraint(schema, constraint.ty, field.value(), field_path, out)
    }
  }
}

///|
/// The number of elements or fields in a container.
fn container_length(value : @ion.IonValue) -> Int? {
  match value.kind() {
    @ion.IonValueKind::List(items) | @ion.IonValueKind::Sexp(items) =>
      Some(items.length())
    @ion.IonValueKind::Struct(fields) => Some(fields.length())
    _ => None
  }
}

///|
/// The number of code points in a string or symbol.
fn codepoint_length(value : @ion.IonValue) -> Int? {
  match value.kind() {
    @ion.IonValueKind::String(text) => Some(text.char_length())
    @ion.IonValueKind::Symbol(token) =>
      match token.text() {
        Some(text) => Some(text.char_length())
        None => None
      }
    _ => None
  }
}

///|
/// Render a list of allowed types for an error message.
fn describe_types(types : Array[@ion.IonType]) -> String {
  let names : Array[String] = []
  for t in types {
    names.push(t.to_text())
  }
  "one of [" + names.join(", ") + "]"
}

///|
pub extend Violation with @debug.Debug::{to_repr}

///|
/// Check that every `required` value appears among `members`, by Ion
/// equivalence. For a struct, `members` are its field values.
fn check_contains(
  required : Array[@ion.IonValue],
  members : Array[@ion.IonValue],
  path : String,
  out : Array[Violation],
) -> Unit {
  for index in 0..<required.length() {
    let mut found = false
    for candidate in members {
      if candidate.equals(required[index]) {
        found = true
      }
    }
    if !found {
      out.push({
        path,
        message: "the container does not contain the value at index \{index}",
      })
    }
  }
}

///|
/// Check a measure of a value against an inclusive range. `None` means the
/// value is not `applies_to`, and does not satisfy the constraint.
fn check_measure(
  measured : Int?,
  lower : Int,
  upper : Int?,
  measure : String,
  applies_to : String,
  path : String,
  out : Array[Violation],
) -> Unit {
  match measured {
    None =>
      out.push({
        path,
        message: "the \{measure} constraint requires \{applies_to}",
      })
    Some(n) =>
      if !in_range(n, lower, upper) {
        out.push({ path, message: "\{measure} \{n} is out of range", })
      }
  }
}

///|
/// The number of bytes in a non-null blob or clob.
fn byte_length(value : @ion.IonValue) -> Int? {
  match value.kind() {
    @ion.IonValueKind::Blob(bytes) | @ion.IonValueKind::Clob(bytes) =>
      Some(bytes.length())
    _ => None
  }
}

///|
/// The number of bytes in the UTF-8 encoding of a string or symbol.
fn utf8_byte_length(value : @ion.IonValue) -> Int? {
  let text = match value.kind() {
    @ion.IonValueKind::String(text) => text
    @ion.IonValueKind::Symbol(token) =>
      match token.text() {
        Some(text) => text
        None => return None
      }
    _ => return None
  }
  let mut length = 0
  for c in text {
    let code = c.to_int()
    length += if code < 0x80 {
      1
    } else if code < 0x800 {
      2
    } else if code < 0x10000 {
      3
    } else {
      4
    }
  }
  Some(length)
}

///|
/// A non-null decimal.
fn decimal_of(value : @ion.IonValue) -> @ion.Decimal? {
  match value.kind() {
    @ion.IonValueKind::Decimal(d) => Some(d)
    _ => None
  }
}

///|
/// A non-null timestamp.
fn timestamp_of(value : @ion.IonValue) -> @ion.Timestamp? {
  match value.kind() {
    @ion.IonValueKind::Timestamp(t) => Some(t)
    _ => None
  }
}

///|
/// A timestamp's precision, as `TimestampPrecision` counts it.
fn timestamp_precision(timestamp : @ion.Timestamp) -> Int {
  match timestamp.precision() {
    Year => -4
    Month => -3
    Day => -2
    Minute => -1
    Second =>
      match timestamp.fraction() {
        Some(fraction) if fraction.exponent() < 0 => -fraction.exponent()
        _ => 0
      }
  }
}

///|
/// Whether a float is exactly a value of `format`. `nan` and the infinities
/// are values of every format.
fn fits_format(f : Double, format : FloatFormat) -> Bool {
  // The significand bits (with the leading one) and the lowest normal
  // exponent and highest exponent of the format.
  let (bits, lowest, highest) = match format {
    Binary16 => (11, -14, 15)
    Binary32 => (24, -126, 127)
    Binary64 => return true
  }
  if f.is_nan() || f.is_inf() || f == 0.0 {
    return true
  }
  // f = mantissa * 2^exponent, with an odd mantissa.
  let raw = f.reinterpret_as_uint64()
  let biased = ((raw >> 52) & 0x7FFUL).to_int()
  let fraction = raw & 0xF_FFFF_FFFF_FFFFUL
  let mut mantissa = if biased == 0 { fraction } else { fraction | (1UL << 52) }
  let mut exponent = if biased == 0 { -1074 } else { biased - 1075 }
  while (mantissa & 1UL) == 0UL {
    mantissa = mantissa >> 1
    exponent += 1
  }
  let width = 64 - mantissa.clz()
  // The position of the leading bit, and the smallest step at that position.
  let top = width - 1 + exponent
  let step = (if top < lowest { lowest } else { top }) - (bits - 1)
  top <= highest && exponent >= step
}
