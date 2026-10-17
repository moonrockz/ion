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
pub struct Ion {
  annotations : Array[SymbolToken]
  kind : IonValueKind
} derive(Debug)

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
  Ion(IonValueKind::Null(IonType::Null))
}

///|
/// A typed null such as `null.int`.
pub fn IonValue::typed_null(t : IonType) -> IonValue {
  Ion(IonValueKind::Null(t))
}

///|
/// A `Bool` value.
pub fn IonValue::bool(value : Bool) -> IonValue {
  Ion(IonValueKind::Bool(value))
}

///|
/// An `int` value from an `Int`.
pub fn IonValue::int(value : Int32) -> IonValue {
  Ion(IonValueKind::Int(BigInt::from_int(value)))
}

///|
/// An `int` value from an arbitrary-precision `BigInt`.
pub fn IonValue::big_int(value : BigInt) -> IonValue {
  Ion(IonValueKind::Int(value))
}

///|
/// A `float` value.
pub fn IonValue::float(value : Double) -> IonValue {
  Ion(IonValueKind::Float(value))
}

///|
/// A `decimal` value.
pub fn IonValue::decimal(value : Decimal) -> IonValue {
  Ion(IonValueKind::Decimal(value))
}

///|
/// A `timestamp` value.
pub fn IonValue::timestamp(value : Timestamp) -> IonValue {
  Ion(IonValueKind::Timestamp(value))
}

///|
/// A `symbol` value with known text.
pub fn IonValue::symbol(value : String) -> IonValue {
  Ion(IonValueKind::Symbol(SymbolToken::SymbolToken(value)))
}

///|
/// A `symbol` value from a symbol token.
pub fn IonValue::symbol_token(value : SymbolToken) -> IonValue {
  Ion(IonValueKind::Symbol(value))
}

///|
/// A `string` value.
pub fn IonValue::string(value : String) -> IonValue {
  Ion(IonValueKind::String(value))
}

///|
/// A `clob` value.
pub fn IonValue::clob(value : Bytes) -> IonValue {
  Ion(IonValueKind::Clob(value))
}

///|
/// A `blob` value.
pub fn IonValue::blob(value : Bytes) -> IonValue {
  Ion(IonValueKind::Blob(value))
}

///|
/// A `list` value.
pub fn IonValue::list(values : Array[IonValue]) -> IonValue {
  Ion(IonValueKind::List(values))
}

///|
/// An `sexp` value.
pub fn IonValue::sexp(values : Array[IonValue]) -> IonValue {
  Ion(IonValueKind::Sexp(values))
}

///|
/// A `struct` value.
pub fn IonValue::from_fields(fields : Array[Field]) -> IonValue {
  Ion(IonValueKind::Struct(fields))
}

///|
/// Build a struct field from a name literal.
#alias(new, deprecated="Use `Field(...)` instead")
pub fn Field::Field(name : String, value : IonValue) -> Field {
  { name: SymbolToken::SymbolToken(name), value, }
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
