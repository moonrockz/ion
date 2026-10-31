///|
/// The original name for an Ion value, sharing the `Ion` data model and methods.
pub type IonValue = Ion

///|
/// Types that can be converted to an Ion value.
/// Implement this trait for application types, then construct with `Ion(value)`.
pub(open) trait ToIon {
  fn to_ion(Self) -> Ion
}

///|
/// Convert a value to Ion through its `ToIon` implementation.
pub fn[T : ToIon] Ion::Ion(value : T) -> Ion {
  ToIon::to_ion(value)
}

///|
pub impl ToIon for Bool with fn to_ion(self : Bool) -> Ion {
  IonValue::bool(self)
}

///|
pub impl ToIon for IonValueKind with fn to_ion(self : IonValueKind) -> Ion {
  { annotations: [], kind: self, }
}

///|
pub impl ToIon for Int32 with fn to_ion(self : Int32) -> Ion {
  IonValue::int(self)
}

///|
pub impl ToIon for Int64 with fn to_ion(self : Int64) -> Ion {
  IonValue::big_int(BigInt::from_int64(self))
}

///|
pub impl ToIon for UInt32 with fn to_ion(self : UInt32) -> Ion {
  IonValue::big_int(BigInt::from_uint(self))
}

///|
pub impl ToIon for UInt64 with fn to_ion(self : UInt64) -> Ion {
  IonValue::big_int(BigInt::from_uint64(self))
}

///|
pub impl ToIon for BigInt with fn to_ion(self : BigInt) -> Ion {
  IonValue::big_int(self)
}

///|
pub impl ToIon for Double with fn to_ion(self : Double) -> Ion {
  IonValue::float(self)
}

///|
pub impl ToIon for Float with fn to_ion(self : Float) -> Ion {
  IonValue::float(self.to_double())
}

///|
pub impl ToIon for String with fn to_ion(self : String) -> Ion {
  IonValue::string(self)
}

///|
pub impl ToIon for Unit with fn to_ion(_self : Unit) -> Ion {
  IonValue::untyped_null()
}

///|
pub impl ToIon for Bytes with fn to_ion(self : Bytes) -> Ion {
  IonValue::blob(self)
}

///|
pub impl ToIon for Decimal with fn to_ion(self : Decimal) -> Ion {
  IonValue::decimal(self)
}

///|
pub impl ToIon for Timestamp with fn to_ion(self : Timestamp) -> Ion {
  IonValue::timestamp(self)
}

///|
pub impl ToIon for SymbolToken with fn to_ion(self : SymbolToken) -> Ion {
  IonValue::symbol_token(self)
}

///|
pub impl ToIon for Ion with fn to_ion(self : Ion) -> Ion {
  self
}

///|
pub impl[T : ToIon] ToIon for Array[T] with fn to_ion(self : Array[T]) -> Ion {
  IonValue::list(self.map(value => Ion(value)))
}

///|
pub impl[T : ToIon] ToIon for Map[String, T] with fn to_ion(
  self : Map[String, T],
) -> Ion {
  let fields : Array[Field] = []
  for name, value in self {
    fields.push(Field(name, Ion(value)))
  }
  IonValue::from_fields(fields)
}

///|
/// `None` writes the untyped `null`; `Some(value)` writes `value`. Every null
/// reads back as `None`, so `Some(value)` does not round-trip when `value`
/// itself writes a null.
pub impl[T : ToIon] ToIon for T? with fn to_ion(self : T?) -> Ion {
  match self {
    None => IonValue::untyped_null()
    Some(value) => Ion(value)
  }
}

///|
/// A character writes an Ion string of that one character.
pub impl ToIon for Char with fn to_ion(self : Char) -> Ion {
  IonValue::string(self.to_string())
}

///|
/// A byte writes an Ion int from 0 to 255.
pub impl ToIon for Byte with fn to_ion(self : Byte) -> Ion {
  IonValue::int(self.to_int())
}

///|
/// A pair writes an Ion list of its two components.
pub impl[A : ToIon, B : ToIon] ToIon for (A, B) with fn to_ion(self : (A, B)) -> Ion {
  IonValue::list([Ion(self.0), Ion(self.1)])
}

///|
/// A triple writes an Ion list of its three components.
pub impl[A : ToIon, B : ToIon, C : ToIon] ToIon for (A, B, C) with fn to_ion(
  self : (A, B, C),
) -> Ion {
  IonValue::list([Ion(self.0), Ion(self.1), Ion(self.2)])
}
