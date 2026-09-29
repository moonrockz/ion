// Loading Ion Schema documents into the constraint model.

///|
/// Reject the annotations of a constraint or an inline type, other than those
/// a type reference may have: `$null_or::` in ISL 2.0, and `nullable::` in
/// ISL 1.0, where an inline type may also be `type::`. The constraints that
/// take other modifiers, such as `distinct::` or `range::`, check their own.
fn reject_unknown_annotations(
  value : @ion.IonValue,
  context : String,
  ctx : Context,
) -> Unit raise @ion.IonError {
  let allowed = match (ctx.version, value.kind()) {
    (Isl10, @ion.IonValueKind::Struct(_)) => ["nullable", "type"]
    (Isl10, _) => ["nullable"]
    (Isl20, _) => ["$null_or"]
  }
  for token in value.annotations() {
    let name = token.require_text()
    if !allowed.contains(name) {
      raise @ion.IonError::DataModel(
        "the annotation '\{name}' is not allowed on " + context,
      )
    }
  }
}

///|
/// Load a schema from Ion Schema text.
pub fn Schema::load_from_text(
  text : StringView,
  resolver? : (String) -> Array[@ion.IonValue] raise @ion.IonError,
) -> Schema raise @ion.IonError {
  Schema::load(@text.read_ion_datagram(text), resolver?)
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
/// The integer value of an Ion `int`.
fn int_of(value : @ion.IonValue) -> Int raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Int(n) => n.to_int()
    _ => raise @ion.IonError::DataModel("expected an integer")
  }
}

///|
/// Load a `type::{ ... }` definition in the scope of `ctx`.
fn load_type_definition(
  fields : Array[@ion.Field],
  ctx : Context,
) -> TypeDefinition raise @ion.IonError {
  { name: type_name(fields), constraints: load_type_fields(fields, ctx), }
}

///|
/// Load the constraints of a type definition, named or inline. An inline type
/// has no name. It may have an `occurs` when it is `variably_occurring`, in
/// `fields` or `ordered_elements`, and not `nullable`; ISL 1.0 allows a valid
/// `occurs` in any type, and ignores it where it does not apply.
///
/// In ISL 1.0, a type with no `type` constraint has `type: any`, and a field
/// that is not an ISL 1.0 keyword is open content. `content: closed` loads as
/// the names of the type's `fields`, which are the only fields allowed.
fn load_type_fields(
  fields : Array[@ion.Field],
  ctx : Context,
  inline? : Bool = false,
  variably_occurring? : Bool = false,
  nullable? : Bool = false,
) -> Array[Constraint] raise @ion.IonError {
  let constraints : Array[Constraint] = []
  let mut closed = false
  for field in fields {
    let key = field.name().require_text()
    let value = field.value()
    if key == "name" {
      if inline {
        raise @ion.IonError::DataModel("an inline type must not have a name")
      }
      continue
    }
    match ctx.version {
      Isl10 =>
        match key {
          "occurs" => {
            let occurs = load_occurs(value)
            if occurs.upper == Some(0) {
              raise @ion.IonError::DataModel("occurs must allow at least 1")
            }
            if nullable {
              raise @ion.IonError::DataModel(
                "a type with 'occurs' cannot be 'nullable::'",
              )
            }
          }
          "content" => {
            if !(value.kind() is @ion.IonValueKind::Symbol(token) &&
              token.text() == Some("closed") &&
              !value.has_annotations()) {
              raise @ion.IonError::DataModel(
                "content must be the symbol closed",
              )
            }
            closed = true
          }
          _ =>
            if isl10_constraints.contains(key) {
              constraints.push(load_constraint(key, value, ctx))
            }
        }
      Isl20 => {
        if key == "occurs" {
          if !variably_occurring {
            raise @ion.IonError::DataModel(
              "'occurs' is allowed only in 'fields' and 'ordered_elements'",
            )
          }
          if nullable {
            raise @ion.IonError::DataModel(
              "a type with 'occurs' cannot be '$null_or::'",
            )
          }
          continue
        }
        if is_user_field(key, ctx.user_fields) {
          continue
        }
        constraints.push(load_constraint(key, value, ctx))
      }
    }
  }
  if ctx.version == Isl10 {
    if field_value(fields, "type") is None {
      constraints.insert(0, isl10_any())
    }
    if closed {
      let names = match
        field_value(fields, "fields").map(value => value.kind()) {
        Some(@ion.IonValueKind::Struct(declared)) =>
          declared.map(field => field.name().require_text())
        _ => []
      }
      constraints.push(ClosedFields(names))
    }
  }
  constraints
}

///|
/// The ISL 1.0 constraints, which `load_constraint` loads. `occurs` and
/// `content` are keywords too, which `load_type_fields` loads.
let isl10_constraints : Array[String] = [
  "all_of", "annotations", "any_of", "byte_length", "codepoint_length", "container_length",
  "contains", "element", "fields", "not", "one_of", "ordered_elements", "precision",
  "regex", "scale", "timestamp_offset", "timestamp_precision", "type", "utf8_byte_length",
  "valid_values",
]

///|
/// The ISL 1.0 core type `any`: any value that is not null, or a document.
fn isl10_any() -> Constraint {
  AnyOf([IsType(all_ion_types), IsDocument])
}

///|
/// The Ion types other than null.
let all_ion_types : Array[@ion.IonType] = [
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
]

///|
/// Load one constraint by its field name.
fn load_constraint(
  key : String,
  value : @ion.IonValue,
  ctx : Context,
) -> Constraint raise @ion.IonError {
  if ctx.version == Isl20 && !implemented_constraints.contains(key) {
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
  if !checks_own_annotations.contains(key) {
    reject_unknown_annotations(value, "constraint '" + key + "'", ctx)
  }
  match key {
    "type" => load_type_constraint(value, ctx)
    "element" if ctx.version == Isl10 => Element(load_inline_type(value, ctx))
    "fields" if ctx.version == Isl10 => {
      if value.has_annotations() {
        raise @ion.IonError::DataModel("'fields' takes no annotation")
      }
      Fields(load_fields(value, ctx))
    }
    "annotations" if ctx.version == Isl10 => load_isl10_annotations(value)
    "scale" => {
      // The scale is the number of digits after the decimal point: the
      // negated exponent.
      let (lower, upper) = load_range(value)
      Exponent(
        match upper {
          Some(upper) => -upper
          None => -2_147_483_648
        },
        Some(-lower),
      )
    }
    "element" => {
      let (bare, distinct) = take_modifier(value, "distinct")
      let element = Element(load_inline_type(bare, ctx))
      if distinct {
        AllOf([element, DistinctElements])
      } else {
        element
      }
    }
    "field_names" => {
      let (bare, distinct) = take_modifier(value, "distinct")
      let names = FieldNames(load_inline_type(bare, ctx))
      if distinct {
        AllOf([names, DistinctFieldNames])
      } else {
        names
      }
    }
    "fields" => {
      let (bare, closed) = take_modifier(value, "closed")
      if bare.has_annotations() {
        raise @ion.IonError::DataModel(
          "'fields' takes no annotation but closed",
        )
      }
      let fields = load_fields(bare, ctx)
      if closed {
        AllOf([Fields(fields), ClosedFields(fields.map(field => field.name))])
      } else {
        Fields(fields)
      }
    }
    "annotations" => Annotations(load_annotations(value, ctx))
    "ordered_elements" => {
      let items = match value.kind() {
        @ion.IonValueKind::List(items) if !value.has_annotations() => items
        _ =>
          raise @ion.IonError::DataModel(
            "ordered_elements must be a non-null list of types",
          )
      }
      let slots : Array[(Constraint, Occurs)] = []
      for item in items {
        slots.push(
          (
            load_inline_type(item, ctx, variably_occurring=true),
            occurs_of(item).unwrap_or(Occurs::required()),
          ),
        )
      }
      OrderedElements(slots)
    }
    "valid_values" => load_valid_values(value, ctx.version)
    "container_length" => {
      let (lower, upper) = load_range(value)
      ContainerLength(lower, upper)
    }
    "codepoint_length" => {
      let (lower, upper) = load_range(value)
      CodepointLength(lower, upper)
    }
    "one_of" => OneOf(load_constraint_list(value, ctx))
    "any_of" => AnyOf(load_constraint_list(value, ctx))
    "all_of" => AllOf(load_constraint_list(value, ctx))
    "not" => Not(load_inline_type(value, ctx))
    "contains" => Contains(as_list(value))
    "regex" => Matches(load_regex(value))
    "byte_length" => {
      let (lower, upper) = load_range(value)
      ByteLength(lower, upper)
    }
    "utf8_byte_length" => {
      let (lower, upper) = load_range(value)
      Utf8ByteLength(lower, upper)
    }
    "precision" => {
      let (lower, upper) = load_ordered_range(value, Some(1), int_of)
      Precision(lower, upper)
    }
    "exponent" => {
      let (lower, upper) = load_ordered_range(value, None, int_of)
      Exponent(lower, upper)
    }
    "timestamp_precision" => {
      let (lower, upper) = load_ordered_range(value, None, precision_of)
      TimestampPrecision(lower, upper)
    }
    "timestamp_offset" => TimestampOffsets(load_offsets(value))
    "ieee754_float" => Ieee754Float(load_float_format(value))
    _ => panic()
  }
}

///|
/// The constraints `load_constraint` loads.
let implemented_constraints : Array[String] = [
  "type", "element", "fields", "valid_values", "container_length", "codepoint_length",
  "one_of", "any_of", "all_of", "not", "contains", "regex", "byte_length", "utf8_byte_length",
  "precision", "exponent", "timestamp_precision", "timestamp_offset", "ieee754_float",
  "field_names", "annotations", "ordered_elements",
]

///|
/// The constraints whose loaders check their own annotations.
let checks_own_annotations : Array[String] = [
  "container_length", "codepoint_length", "valid_values", "regex", "byte_length",
  "utf8_byte_length", "precision", "exponent", "timestamp_precision", "timestamp_offset",
  "ieee754_float", "element", "field_names", "fields", "annotations", "ordered_elements",
  "scale",
]

///|
/// A value without its first annotation, when that is the modifier `name`,
/// and whether it was there. The value's other annotations stay, for the
/// loader to check.
fn take_modifier(
  value : @ion.IonValue,
  name : String,
) -> (@ion.IonValue, Bool) raise @ion.IonError {
  match value.annotations() {
    [first, .. rest] if first.text() == Some(name) => {
      if rest.iter().any(token => token.text() == Some(name)) {
        raise @ion.IonError::DataModel("'\{name}::' appears twice")
      }
      (value.with_annotations(rest.to_owned()), true)
    }
    _ => (value, false)
  }
}

///|
/// Load an `annotations` constraint. The standard form is a type, which the
/// value's annotations, as a list of symbols, must satisfy. The simplified
/// form is a list of symbols annotated with `required::`, `closed::`, or
/// both: `required` means each symbol is an annotation of the value, and
/// `closed` means the value has no other annotation.
fn load_annotations(
  value : @ion.IonValue,
  ctx : Context,
) -> Constraint raise @ion.IonError {
  guard value.kind() is @ion.IonValueKind::List(items) else {
    return load_inline_type(value, ctx)
  }
  let modifiers = value.annotations().map(token => token.text())
  let required = modifiers.contains(Some("required"))
  let closed = modifiers.contains(Some("closed"))
  let expected = (if required { 1 } else { 0 }) + (if closed { 1 } else { 0 })
  if modifiers.is_empty() || modifiers.length() != expected {
    raise @ion.IonError::DataModel(
      "an annotations list must be annotated with required::, closed::, or both",
    )
  }
  let symbols : Array[@ion.IonValue] = []
  for item in items {
    match item.kind() {
      @ion.IonValueKind::Symbol(_) if !item.has_annotations() =>
        symbols.push(item)
      _ =>
        raise @ion.IonError::DataModel(
          "an annotations list holds symbols without annotations",
        )
    }
  }
  let parts : Array[Constraint] = []
  if required {
    parts.push(Contains(symbols))
  }
  if closed {
    parts.push(Element(ValidValues(symbols)))
  }
  if parts.length() == 1 {
    parts[0]
  } else {
    AllOf(parts)
  }
}

///|
/// Load an ISL 1.0 `annotations` constraint: a list of symbols, each
/// optionally `required::` or `optional::`, annotated with any of
/// `required::`, `ordered::`, and `closed::`. A symbol is required when it is
/// `required::`, or when the list is `required::` and the symbol is not
/// `optional::`.
///
/// - Without `ordered`, each required symbol is an annotation of the value,
///   and, when `closed`, the value has no annotation but these symbols.
/// - With `ordered` and `closed`, the value's annotations are the symbols in
///   order, each once, or not at all if it is not required.
/// - With `ordered` alone, the required symbols are among the value's
///   annotations in order, with any others before, between, or after them.
fn load_isl10_annotations(
  value : @ion.IonValue,
) -> Constraint raise @ion.IonError {
  let items = match value.kind() {
    @ion.IonValueKind::List(items) => items
    _ =>
      raise @ion.IonError::DataModel(
        "annotations must be a non-null list of symbols",
      )
  }
  let modifiers : Array[String] = []
  for token in value.annotations() {
    let name = token.require_text()
    if !["required", "ordered", "closed"].contains(name) ||
      modifiers.contains(name) {
      raise @ion.IonError::DataModel(
        "an annotations list takes required::, ordered::, and closed::, each at most once",
      )
    }
    modifiers.push(name)
  }
  let symbols : Array[(@ion.IonValue, Bool)] = []
  for item in items {
    let required = match item.annotations().map(token => token.text()) {
      [] => modifiers.contains("required")
      [Some("required")] => true
      [Some("optional")] => false
      _ =>
        raise @ion.IonError::DataModel(
          "an annotation may be only required:: or optional::",
        )
    }
    match item.kind() {
      @ion.IonValueKind::Symbol(_) =>
        symbols.push((item.with_annotations([]), required))
      _ =>
        raise @ion.IonError::DataModel(
          "an annotations list holds non-null symbols",
        )
    }
  }
  let one = (symbol : @ion.IonValue) => ValidValues([symbol])
  let any_number = (Constraint::any(), Occurs::new(0, None))
  let constraint = match
    (modifiers.contains("ordered"), modifiers.contains("closed")) {
    (true, true) =>
      OrderedElements(
        symbols.map(pair => {
          let (symbol, required) = pair
          (
            one(symbol),
            if required {
              Occurs::required()
            } else {
              Occurs::optional()
            },
          )
        }),
      )
    (true, false) => {
      let slots = [any_number]
      for pair in symbols {
        if pair.1 {
          slots.push((one(pair.0), Occurs::required()))
          slots.push(any_number)
        }
      }
      OrderedElements(slots)
    }
    (false, closed) => {
      let parts : Array[Constraint] = []
      let required = symbols.filter(pair => pair.1).map(pair => pair.0)
      if !required.is_empty() {
        parts.push(Contains(required))
      }
      if closed {
        parts.push(Element(ValidValues(symbols.map(pair => pair.0))))
      }
      if parts.length() == 1 {
        parts[0]
      } else {
        AllOf(parts)
      }
    }
  }
  Annotations(constraint)
}

///|
/// The integer for a named timestamp precision, as `TimestampPrecision`
/// counts it.
fn precision_of(value : @ion.IonValue) -> Int raise @ion.IonError {
  let name = match value.kind() {
    @ion.IonValueKind::Symbol(token) => token.text()
    _ => None
  }
  match name {
    Some("year") => -4
    Some("month") => -3
    Some("day") => -2
    Some("minute") => -1
    Some("second") => 0
    Some("millisecond") => 3
    Some("microsecond") => 6
    Some("nanosecond") => 9
    _ =>
      raise @ion.IonError::DataModel(
        "a timestamp precision must be year, month, day, minute, second, millisecond, microsecond, or nanosecond",
      )
  }
}

///|
/// Load a `timestamp_offset` list: one or more strings `[+|-]hh:mm`, where
/// `-00:00` is the unknown offset.
fn load_offsets(
  value : @ion.IonValue,
) -> Array[@ion.TimestampOffset] raise @ion.IonError {
  let invalid = @ion.IonError::DataModel(
    "timestamp_offset must be a non-empty list of offsets such as \"+01:30\" or \"-00:00\"",
  )
  let items = match value.kind() {
    @ion.IonValueKind::List(items) if !value.has_annotations() &&
      !items.is_empty() => items
    _ => raise invalid
  }
  items.map(item => {
    let text = match item.kind() {
      @ion.IonValueKind::String(text) if !item.has_annotations() => text
      _ => raise invalid
    }
    let chars : Array[Char] = text.iter().collect()
    let digit = (index : Int) => {
      let c = chars[index]
      if c >= '0' && c <= '9' {
        c.to_int() - '0'.to_int()
      } else {
        raise invalid
      }
    }
    if chars.length() != 6 ||
      !(chars[0] == '+' || chars[0] == '-') ||
      chars[3] != ':' {
      raise invalid
    }
    let hours = digit(1) * 10 + digit(2)
    let minutes = digit(4) * 10 + digit(5)
    if hours > 23 || minutes > 59 {
      raise invalid
    }
    if text == "-00:00" {
      @ion.TimestampOffset::Unknown
    } else {
      let total = hours * 60 + minutes
      @ion.TimestampOffset::Known(if chars[0] == '-' { -total } else { total })
    }
  })
}

///|
/// Load an `ieee754_float` format: `binary16`, `binary32`, or `binary64`.
fn load_float_format(value : @ion.IonValue) -> FloatFormat raise @ion.IonError {
  let name = match value.kind() {
    @ion.IonValueKind::Symbol(token) if !value.has_annotations() => token.text()
    _ => None
  }
  match name {
    Some("binary16") => Binary16
    Some("binary32") => Binary32
    Some("binary64") => Binary64
    _ =>
      raise @ion.IonError::DataModel(
        "ieee754_float must be binary16, binary32, or binary64",
      )
  }
}

///|
/// Load a `type:` constraint: a type name, or an inline
/// type or import, with `$null_or::` if nullable.
fn load_type_constraint(
  value : @ion.IonValue,
  ctx : Context,
) -> Constraint raise @ion.IonError {
  load_inline_type(value, ctx)
}

///|
/// Load a `type:` constraint, ignoring annotations.
fn load_type_constraint_bare(
  value : @ion.IonValue,
  ctx : Context,
) -> Constraint raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Symbol(token) => {
      let name = token.require_text()
      match built_in_type(name) {
        _ if name == "any" && ctx.version == Isl10 => isl10_any()
        Some(constraint) => constraint
        None => ctx.resolve(name)
      }
    }
    _ =>
      raise @ion.IonError::DataModel(
        "a type must be a type name, an inline type, or an inline import",
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
    "any" => Some(all_ion_types)
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
    "document" => Some(IsDocument)
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
/// range. No other value in the list may have annotations. In ISL 1.0, no
/// bound of a timestamp range may have the unknown offset.
fn load_valid_values(
  value : @ion.IonValue,
  version : IslVersion,
) -> Constraint raise @ion.IonError {
  let load = (range : @ion.IonValue) => {
    let loaded = load_value_range(range)
    if version == Isl10 && loaded.has_unknown_offset() {
      raise @ion.IonError::DataModel(
        "an Ion Schema 1.0 timestamp range bound must have a known offset",
      )
    }
    InRange(loaded)
  }
  if value.has_annotations() {
    return load(value)
  }
  let values : Array[@ion.IonValue] = []
  let ranges : Array[Constraint] = []
  for item in as_list(value) {
    if has_annotation(item, "range") {
      ranges.push(load(item))
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
  ctx : Context,
  variably_occurring? : Bool = false,
) -> Constraint raise @ion.IonError {
  reject_unknown_annotations(value, "inline type", ctx)
  let nullable = has_annotation(
    value,
    match ctx.version {
      Isl10 => "nullable"
      Isl20 => "$null_or"
    },
  )
  let inner = match value.kind() {
    @ion.IonValueKind::Struct(fields) if field_value(fields, "id") is Some(_) =>
      ctx.inline_import(fields)
    @ion.IonValueKind::Struct(fields) => {
      let constraints = load_type_fields(
        fields,
        ctx,
        inline=true,
        variably_occurring~,
        nullable~,
      )
      if constraints.length() == 1 {
        constraints[0]
      } else {
        AllOf(constraints)
      }
    }
    _ => load_type_constraint_bare(value, ctx)
  }
  match (nullable, ctx.version) {
    (false, _) => inner
    (true, Isl20) => NullOr(inner)
    (true, Isl10) => {
      let nulls = [@ion.IonValue::typed_null(@ion.IonType::Null)]
      for ion_type in ctx.base_types(value, Set([])) {
        nulls.push(@ion.IonValue::typed_null(ion_type))
      }
      AnyOf([ValidValues(nulls), inner])
    }
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
/// Load a length or count: a non-negative integer, or a range of them.
fn load_range(value : @ion.IonValue) -> (Int, Int?) raise @ion.IonError {
  load_ordered_range(value, Some(0), int_of)
}

///|
/// Load an exact value or a `range::[lower, upper]` of values that `read`
/// turns into integers, where a bound may be `exclusive::`, `lower` may be
/// `min`, and `upper` may be `max`. The result is the inclusive range, with
/// `None` for no upper bound. No value may be below `floor`.
fn load_ordered_range(
  value : @ion.IonValue,
  floor : Int?,
  read : (@ion.IonValue) -> Int raise @ion.IonError,
) -> (Int, Int?) raise @ion.IonError {
  let too_low = () => {
    @ion.IonError::DataModel(
      "the value is below the lowest allowed, \{floor.unwrap_or(0)}",
    )
  }
  if !value.has_annotations() {
    let single = read(value)
    if floor is Some(floor) && single < floor {
      raise too_low()
    }
    return (single, Some(single))
  }
  let (lower_value, upper_value) = range_bounds(value)
  let lower = bound_value(lower_value, "min")
  let upper = bound_value(upper_value, "max")
  if lower is None && upper is None {
    raise @ion.IonError::DataModel("a range needs at least one bound")
  }
  let lower = match lower {
    Some((bound, exclusive)) => read(bound) + (if exclusive { 1 } else { 0 })
    None => floor.unwrap_or(-2_147_483_648)
  }
  let upper = match upper {
    Some((bound, exclusive)) =>
      Some(read(bound) - (if exclusive { 1 } else { 0 }))
    None => None
  }
  if floor is Some(floor) && lower < floor {
    raise too_low()
  }
  if upper is Some(upper) && upper < lower {
    raise @ion.IonError::DataModel("the range contains no value")
  }
  (lower, upper)
}

///|
/// Load a `fields: { ... }` constraint.
fn load_fields(
  value : @ion.IonValue,
  ctx : Context,
) -> Array[FieldConstraint] raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Struct(fields) => {
      if fields.is_empty() {
        raise @ion.IonError::DataModel("'fields' must name at least one field")
      }
      let result : Array[FieldConstraint] = []
      for field in fields {
        let name = field.name().require_text()
        if result.iter().any(other => other.name == name) {
          raise @ion.IonError::DataModel(
            "'fields' names the field '\{name}' twice",
          )
        }
        let type_value = field.value()
        let ty = load_inline_type(type_value, ctx, variably_occurring=true)
        let occurs = match occurs_of(type_value) {
          Some(occurs) => occurs
          None => Occurs::optional()
        }
        if occurs.upper == Some(0) {
          raise @ion.IonError::DataModel(
            "the field '\{name}' cannot occur 0 times",
          )
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
  ctx : Context,
) -> Array[Constraint] raise @ion.IonError {
  let items = as_list(value)
  let result : Array[Constraint] = []
  for item in items {
    result.push(load_inline_type(item, ctx))
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

///|
/// The Ion types whose typed nulls the ISL 1.0 `nullable::` of a type
/// reference allows: those of the type's base type, which is the type its
/// `type` constraint names, or `any` without one. `visiting` holds the type
/// keys on the path, so that a cycle of references ends.
fn Context::base_types(
  self : Context,
  reference : @ion.IonValue,
  visiting : Set[String],
) -> Array[@ion.IonType] raise @ion.IonError {
  let definition = match reference.kind() {
    @ion.IonValueKind::Symbol(token) => {
      let name = token.require_text()
      match name {
        "document" =>
          raise @ion.IonError::DataModel("a document cannot be nullable")
        "any" | "$any" => return all_ion_types
        "nothing" | "$null" => return []
        _ => ()
      }
      let ion_name = if name.has_prefix("$") {
        name.view(start_offset=1).to_owned()
      } else {
        name
      }
      if built_in_ion_types(ion_name) is Some(types) {
        return types
      }
      match self.scope.get(name) {
        Some(key) => key
        None =>
          raise @ion.IonError::DataModel(
            "no type named '\{name}' is defined or imported",
          )
      }
    }
    @ion.IonValueKind::Struct(fields) =>
      match field_value(fields, "id") {
        Some(_) => {
          let (id, name, _) = import_fields(fields, ["id", "type", "as"])
          type_key(Some(id), name.unwrap_or(""))
        }
        None =>
          return match field_value(fields, "type") {
            Some(inner) => self.base_types(inner, visiting)
            None => all_ion_types
          }
      }
    _ => return all_ion_types
  }
  if visiting.contains(definition) {
    return []
  }
  visiting.add(definition)
  match self.loader.definitions.get(definition) {
    Some((fields, ctx)) =>
      match field_value(fields, "type") {
        Some(inner) => ctx.base_types(inner, visiting)
        None => all_ion_types
      }
    None => all_ion_types
  }
}
