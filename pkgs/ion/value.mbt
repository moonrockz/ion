// The Ion value model.
//
// Every Ion value is an ordered list of annotation symbol tokens plus one of
// the core value kinds. Keeping annotations on the value (instead of in every
// kind) lets the reader, the writer, and a schema validator reach them
// uniformly.

///|
/// The core kind of an Ion value, without annotations.
pub(all) enum IonValueKind {
  /// A null of the given type; `Null(IonType::Null)` is untyped `null`.
  Null(IonType)
  Bool(Bool)
  Int(BigInt)
  Float(Double)
  Decimal(Decimal)
  Timestamp(Timestamp)
  Symbol(SymbolToken)
  String(String)
  Clob(Bytes)
  Blob(Bytes)
  List(Array[IonValue])
  Sexp(Array[IonValue])
  Struct(Array[Field])
} derive(Debug)

///|
/// A field of an Ion struct: a symbol *token* name and a value.
///
/// The name is a token, not a value, so it cannot carry annotations.
pub struct Field {
  name : SymbolToken
  value : IonValue
} derive(Debug)

///|
/// An Ion value: zero or more annotations followed by the core value.
pub struct IonValue {
  annotations : Array[SymbolToken]
  kind : IonValueKind
} derive(Debug)

///|
/// Build a value from a kind, with no annotations.
pub fn IonValue::new(kind : IonValueKind) -> IonValue {
  { annotations: [], kind, }
}

///|
/// The core kind of this value.
pub fn IonValue::kind(self : IonValue) -> IonValueKind {
  self.kind
}

///|
/// The annotations on this value, in order.
pub fn IonValue::annotations(self : IonValue) -> Array[SymbolToken] {
  self.annotations
}

///|
/// Whether this value carries at least one annotation.
pub fn IonValue::has_annotations(self : IonValue) -> Bool {
  !self.annotations.is_empty()
}

///|
/// A copy of this value with `annotation` appended to its annotations.
pub fn IonValue::with_annotation(
  self : IonValue,
  annotation : SymbolToken,
) -> IonValue {
  { annotations: [..self.annotations, annotation], kind: self.kind, }
}

///|
/// A copy of this value with the given annotations, replacing any existing
/// ones.
pub fn IonValue::with_annotations(
  self : IonValue,
  annotations : Array[SymbolToken],
) -> IonValue {
  { annotations, kind: self.kind, }
}

///|
/// The Ion type of this value. For a typed null such as `null.int` this is the
/// null's type (`int`), not `null`.
pub fn IonValue::ion_type(self : IonValue) -> IonType {
  match self.kind {
    IonValueKind::Null(t) => t
    IonValueKind::Bool(_) => IonType::Bool
    IonValueKind::Int(_) => IonType::Int
    IonValueKind::Float(_) => IonType::Float
    IonValueKind::Decimal(_) => IonType::Decimal
    IonValueKind::Timestamp(_) => IonType::Timestamp
    IonValueKind::Symbol(_) => IonType::Symbol
    IonValueKind::String(_) => IonType::String
    IonValueKind::Clob(_) => IonType::Clob
    IonValueKind::Blob(_) => IonType::Blob
    IonValueKind::List(_) => IonType::List
    IonValueKind::Sexp(_) => IonType::Sexp
    IonValueKind::Struct(_) => IonType::Struct
  }
}

///|
/// Whether this value is a null of any type.
pub fn IonValue::is_null(self : IonValue) -> Bool {
  self.kind is IonValueKind::Null(_)
}

///|
/// Whether this value is the untyped `null` (`null.null`).
pub fn IonValue::is_untyped_null(self : IonValue) -> Bool {
  match self.kind {
    IonValueKind::Null(IonType::Null) => true
    _ => false
  }
}

///|
/// The untyped `null` value.
pub fn IonValue::untyped_null() -> IonValue {
  IonValue::new(IonValueKind::Null(IonType::Null))
}

///|
/// A typed null such as `null.int`.
pub fn IonValue::typed_null(t : IonType) -> IonValue {
  IonValue::new(IonValueKind::Null(t))
}

///|
/// A `Bool` value.
pub fn IonValue::bool(value : Bool) -> IonValue {
  IonValue::new(IonValueKind::Bool(value))
}

///|
/// An `int` value from an `Int`.
pub fn IonValue::int(value : Int) -> IonValue {
  IonValue::new(IonValueKind::Int(BigInt::from_int(value)))
}

///|
/// An `int` value from an arbitrary-precision `BigInt`.
pub fn IonValue::big_int(value : BigInt) -> IonValue {
  IonValue::new(IonValueKind::Int(value))
}

///|
/// A `float` value.
pub fn IonValue::float(value : Double) -> IonValue {
  IonValue::new(IonValueKind::Float(value))
}

///|
/// A `decimal` value.
pub fn IonValue::decimal(value : Decimal) -> IonValue {
  IonValue::new(IonValueKind::Decimal(value))
}

///|
/// A `timestamp` value.
pub fn IonValue::timestamp(value : Timestamp) -> IonValue {
  IonValue::new(IonValueKind::Timestamp(value))
}

///|
/// A `symbol` value with known text.
pub fn IonValue::symbol(value : String) -> IonValue {
  IonValue::new(IonValueKind::Symbol(SymbolToken::new(value)))
}

///|
/// A `symbol` value from a symbol token.
pub fn IonValue::symbol_token(value : SymbolToken) -> IonValue {
  IonValue::new(IonValueKind::Symbol(value))
}

///|
/// A `string` value.
pub fn IonValue::string(value : String) -> IonValue {
  IonValue::new(IonValueKind::String(value))
}

///|
/// A `clob` value.
pub fn IonValue::clob(value : Bytes) -> IonValue {
  IonValue::new(IonValueKind::Clob(value))
}

///|
/// A `blob` value.
pub fn IonValue::blob(value : Bytes) -> IonValue {
  IonValue::new(IonValueKind::Blob(value))
}

///|
/// A `list` value.
pub fn IonValue::list(values : Array[IonValue]) -> IonValue {
  IonValue::new(IonValueKind::List(values))
}

///|
/// An `sexp` value.
pub fn IonValue::sexp(values : Array[IonValue]) -> IonValue {
  IonValue::new(IonValueKind::Sexp(values))
}

///|
/// A `struct` value.
pub fn IonValue::from_fields(fields : Array[Field]) -> IonValue {
  IonValue::new(IonValueKind::Struct(fields))
}

///|
/// Build a struct field from a name literal.
pub fn Field::new(name : String, value : IonValue) -> Field {
  { name: SymbolToken::new(name), value, }
}

///|
/// Build a struct field from a name symbol token.
pub fn Field::from_token(name : SymbolToken, value : IonValue) -> Field {
  { name, value, }
}

///|
/// The field's name token.
pub fn Field::name(self : Field) -> SymbolToken {
  self.name
}

///|
/// The field's value.
pub fn Field::value(self : Field) -> IonValue {
  self.value
}

///|
/// The text of a symbol token used as a name, or `None` when only an ID is
/// known.
fn symbol_text(token : SymbolToken) -> String? {
  token.text()
}

///|
/// Structural equality following the Ion data model: annotations must match in
/// order, all NaNs are equivalent, positive and negative zero are not, list
/// and sexp elements are compared
/// pairwise, and struct fields are compared as an unordered multiset.
pub fn IonValue::equals(self : IonValue, other : IonValue) -> Bool {
  if self.annotations.length() != other.annotations.length() {
    return false
  }
  for index in 0..<self.annotations.length() {
    if symbol_text(self.annotations[index]) !=
      symbol_text(other.annotations[index]) {
      return false
    }
  }
  match (self.kind, other.kind) {
    (IonValueKind::Null(a), IonValueKind::Null(b)) => a == b
    (IonValueKind::Bool(a), IonValueKind::Bool(b)) => a == b
    (IonValueKind::Int(a), IonValueKind::Int(b)) => a.equal(b)
    (IonValueKind::Float(a), IonValueKind::Float(b)) =>
      // All NaNs are equivalent, and positive and negative zero are not.
      (a.is_nan() && b.is_nan()) ||
      a.reinterpret_as_uint64() == b.reinterpret_as_uint64()
    (IonValueKind::Decimal(a), IonValueKind::Decimal(b)) =>
      a.coefficient().equal(b.coefficient()) &&
      a.exponent() == b.exponent() &&
      a.is_negative_zero() == b.is_negative_zero()
    (IonValueKind::Timestamp(a), IonValueKind::Timestamp(b)) =>
      a.to_ion_string() == b.to_ion_string()
    (IonValueKind::Symbol(a), IonValueKind::Symbol(b)) =>
      symbol_text(a) == symbol_text(b)
    (IonValueKind::String(a), IonValueKind::String(b)) => a == b
    (IonValueKind::Clob(a), IonValueKind::Clob(b)) => a == b
    (IonValueKind::Blob(a), IonValueKind::Blob(b)) => a == b
    (IonValueKind::List(a), IonValueKind::List(b)) => values_equal(a, b)
    (IonValueKind::Sexp(a), IonValueKind::Sexp(b)) => values_equal(a, b)
    (IonValueKind::Struct(a), IonValueKind::Struct(b)) => fields_equal(a, b)
    _ => false
  }
}

///|
/// Element-wise equality of two value arrays.
fn values_equal(a : Array[IonValue], b : Array[IonValue]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for index in 0..<a.length() {
    if !a[index].equals(b[index]) {
      return false
    }
  }
  true
}

///|
/// Field-wise equality of two structs. The Ion data model treats a struct as an
/// unordered multiset of fields, so field order does not matter and repeated
/// names are matched one-for-one.
fn fields_equal(a : Array[Field], b : Array[Field]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let consumed : Array[Bool] = []
  for _ in 0..<b.length() {
    consumed.push(false)
  }
  for field_a in a {
    let mut matched = false
    for index in 0..<b.length() {
      if !consumed[index] &&
        symbol_text(field_a.name()) == symbol_text(b[index].name()) &&
        field_a.value().equals(b[index].value()) {
        consumed[index] = true
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}
