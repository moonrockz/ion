// The thirteen core types of the Amazon Ion data model.
//
// See the specification: <https://amazon-ion.github.io/ion-docs/docs/spec.html>

///|
/// The thirteen core Ion types.
///
/// `Null` is the untyped `null`; every other type also has a typed null value
/// (`null.int`, `null.list`, ...), whose Ion type is the type itself.
pub(all) enum IonType {
  Null
  Bool
  Int
  Float
  Decimal
  Timestamp
  Symbol
  String
  Clob
  Blob
  List
  Sexp
  Struct
} derive(Eq, Hash, Debug)

///|
/// Every Ion type, in the order used throughout the specification.
pub fn IonType::all() -> Array[IonType] {
  [
    IonType::Null,
    IonType::Bool,
    IonType::Int,
    IonType::Float,
    IonType::Decimal,
    IonType::Timestamp,
    IonType::Symbol,
    IonType::String,
    IonType::Clob,
    IonType::Blob,
    IonType::List,
    IonType::Sexp,
    IonType::Struct,
  ]
}

///|
/// The Ion text name of this type (`null`, `int`, `sexp`, ...).
pub fn IonType::to_text(self : IonType) -> String {
  match self {
    IonType::Null => "null"
    IonType::Bool => "bool"
    IonType::Int => "int"
    IonType::Float => "float"
    IonType::Decimal => "decimal"
    IonType::Timestamp => "timestamp"
    IonType::Symbol => "symbol"
    IonType::String => "string"
    IonType::Clob => "clob"
    IonType::Blob => "blob"
    IonType::List => "list"
    IonType::Sexp => "sexp"
    IonType::Struct => "struct"
  }
}

///|
/// Whether this type is one of the three container types.
pub fn IonType::is_container(self : IonType) -> Bool {
  match self {
    IonType::List | IonType::Sexp | IonType::Struct => true
    _ => false
  }
}

///|
/// Parse the textual name of an Ion type, as it appears after `null.` or in an
/// Ion Schema `type` constraint. Returns `None` for an unknown name. Both
/// `null` and `$null` (the Ion Schema spelling) name the untyped null type.
pub fn IonType::from_text(name : StringView) -> IonType? {
  match name.to_owned() {
    "null" | "$null" => Some(IonType::Null)
    "bool" => Some(IonType::Bool)
    "int" => Some(IonType::Int)
    "float" => Some(IonType::Float)
    "decimal" => Some(IonType::Decimal)
    "timestamp" => Some(IonType::Timestamp)
    "symbol" => Some(IonType::Symbol)
    "string" => Some(IonType::String)
    "clob" => Some(IonType::Clob)
    "blob" => Some(IonType::Blob)
    "list" => Some(IonType::List)
    "sexp" => Some(IonType::Sexp)
    "struct" => Some(IonType::Struct)
    _ => None
  }
}

///|
/// Whether this type may be the target of a `null.<type>` literal.
pub fn IonType::has_typed_null(self : IonType) -> Bool {
  self != IonType::Null
}
