// Ion binary type descriptors.
//
// A binary value begins with a one-byte type descriptor: the high nibble is the
// type code and the low nibble is the length. The length nibble `14` (0xE)
// means a VarUInt length follows, and `15` (0xF) means the value is a typed
// null. See the Ion binary encoding specification.

///|
/// The high nibble of an Ion binary type descriptor.
pub(all) enum IonTypeCode {
  Null
  Bool
  PosInt
  NegInt
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
  /// The annotation wrapper, whose payload is a length-prefixed annotation list
  /// followed by the annotated value.
  Annotation
  /// Reserved for future use.
  Reserved
} derive(Eq, Hash, Debug)

///|
/// The length nibble that means a VarUInt length follows the descriptor.
pub let length_follows : Int = 14

///|
/// The length nibble that means the value is a typed null.
pub let length_null : Int = 15

///|
/// The numeric type code (`0`-`15`) of this code.
pub fn IonTypeCode::to_int(self : IonTypeCode) -> Int {
  match self {
    IonTypeCode::Null => 0
    IonTypeCode::Bool => 1
    IonTypeCode::PosInt => 2
    IonTypeCode::NegInt => 3
    IonTypeCode::Float => 4
    IonTypeCode::Decimal => 5
    IonTypeCode::Timestamp => 6
    IonTypeCode::Symbol => 7
    IonTypeCode::String => 8
    IonTypeCode::Clob => 9
    IonTypeCode::Blob => 10
    IonTypeCode::List => 11
    IonTypeCode::Sexp => 12
    IonTypeCode::Struct => 13
    IonTypeCode::Annotation => 14
    IonTypeCode::Reserved => 15
  }
}

///|
/// The type code for a numeric type code, defaulting to `Reserved` for an
/// out-of-range value.
pub fn IonTypeCode::from_int(code : Int) -> IonTypeCode {
  match code {
    0 => IonTypeCode::Null
    1 => IonTypeCode::Bool
    2 => IonTypeCode::PosInt
    3 => IonTypeCode::NegInt
    4 => IonTypeCode::Float
    5 => IonTypeCode::Decimal
    6 => IonTypeCode::Timestamp
    7 => IonTypeCode::Symbol
    8 => IonTypeCode::String
    9 => IonTypeCode::Clob
    10 => IonTypeCode::Blob
    11 => IonTypeCode::List
    12 => IonTypeCode::Sexp
    13 => IonTypeCode::Struct
    14 => IonTypeCode::Annotation
    _ => IonTypeCode::Reserved
  }
}

///|
/// The type code that normally encodes a value of the given Ion type. Note that
/// `int` splits into `PosInt` and `NegInt` by sign; this returns `PosInt`.
pub fn IonTypeCode::from_ion_type(t : @ion.IonType) -> IonTypeCode {
  match t {
    @ion.IonType::Null => IonTypeCode::Null
    @ion.IonType::Bool => IonTypeCode::Bool
    @ion.IonType::Int => IonTypeCode::PosInt
    @ion.IonType::Float => IonTypeCode::Float
    @ion.IonType::Decimal => IonTypeCode::Decimal
    @ion.IonType::Timestamp => IonTypeCode::Timestamp
    @ion.IonType::Symbol => IonTypeCode::Symbol
    @ion.IonType::String => IonTypeCode::String
    @ion.IonType::Clob => IonTypeCode::Clob
    @ion.IonType::Blob => IonTypeCode::Blob
    @ion.IonType::List => IonTypeCode::List
    @ion.IonType::Sexp => IonTypeCode::Sexp
    @ion.IonType::Struct => IonTypeCode::Struct
  }
}

///|
/// The Ion type a type code denotes. Both int codes map to `int`, and the
/// annotation wrapper and reserved code have no standalone Ion type, so they
/// return `None`.
pub fn IonTypeCode::to_ion_type(self : IonTypeCode) -> @ion.IonType? {
  match self {
    IonTypeCode::Null => Some(@ion.IonType::Null)
    IonTypeCode::Bool => Some(@ion.IonType::Bool)
    IonTypeCode::PosInt | IonTypeCode::NegInt => Some(@ion.IonType::Int)
    IonTypeCode::Float => Some(@ion.IonType::Float)
    IonTypeCode::Decimal => Some(@ion.IonType::Decimal)
    IonTypeCode::Timestamp => Some(@ion.IonType::Timestamp)
    IonTypeCode::Symbol => Some(@ion.IonType::Symbol)
    IonTypeCode::String => Some(@ion.IonType::String)
    IonTypeCode::Clob => Some(@ion.IonType::Clob)
    IonTypeCode::Blob => Some(@ion.IonType::Blob)
    IonTypeCode::List => Some(@ion.IonType::List)
    IonTypeCode::Sexp => Some(@ion.IonType::Sexp)
    IonTypeCode::Struct => Some(@ion.IonType::Struct)
    IonTypeCode::Annotation | IonTypeCode::Reserved => None
  }
}

///|
/// The Ion binary version marker: `E0 01 00 EA`.
pub fn binary_version_marker() -> Bytes {
  Bytes::from_array([0xE0, 0x01, 0x00, 0xEA])
}

///|
/// Whether `bytes` begins with the Ion binary version marker.
pub fn has_binary_version_marker(bytes : BytesView) -> Bool {
  bytes.length() >= 4 && bytes[:4] == binary_version_marker()
}

///|
/// Build a type-descriptor byte from a type code and a length nibble.
pub fn type_descriptor(type_code : IonTypeCode, length_nibble : Int) -> Int {
  type_code.to_int() * 16 + (length_nibble & 0x0F)
}

///|
/// The type code of a type-descriptor byte.
pub fn descriptor_type_code(descriptor : Int) -> IonTypeCode {
  IonTypeCode::from_int((descriptor >> 4) & 0x0F)
}

///|
/// The length nibble of a type-descriptor byte.
pub fn descriptor_length_nibble(descriptor : Int) -> Int {
  descriptor & 0x0F
}

///|
/// Whether a type-descriptor byte denotes a typed null.
pub fn descriptor_is_null(descriptor : Int) -> Bool {
  descriptor_length_nibble(descriptor) == length_null
}

///|
pub extend IonTypeCode with Eq::{not_equal, equal}

///|
pub extend IonTypeCode with Hash::{hash, hash_combine}

///|
pub extend IonTypeCode with @debug.Debug::{to_repr}
