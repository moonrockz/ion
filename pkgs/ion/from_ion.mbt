// Decoding MoonBit values from Ion.
//
// `FromIon` is the inverse of `ToIon`. Each type reads exactly the Ion type
// that its `ToIon` writes and nothing else: a symbol is not a `String`, a
// decimal is not a `Double`, a clob is not `Bytes`. Annotations on the value
// are ignored. A failure raises `FromIonError`, which names the path from the
// decoded root to the value that failed and keeps that value's kind.

///|
/// Types that can be decoded from an Ion value. Implement this trait for
/// application types; call it as `let x : T = FromIon::from_ion(value)`.
///
/// A container impl decodes each element and, when the element fails, adds
/// its own step to the error with [`FromIonError::within`].
pub(open) trait FromIon {
  fn from_ion(Ion) -> Self raise FromIonError
}

///|
/// One step of the path from a decoded root to a nested value.
pub(all) enum PathSegment {
  /// A struct field, by name.
  Name(String)
  /// A list element, by index.
  Index(Int32)
} derive(Debug, Eq)

///|
pub extend PathSegment with @debug.Debug::{to_repr}

///|
pub extend PathSegment with Eq::{equal, not_equal}

///|
/// The values a numeric target can hold.
pub(all) enum ValueRange {
  /// The integers from `min` to `max`, inclusive.
  Integers(min~ : BigInt, max~ : BigInt)
  /// The finite values of a 32-bit `Float`, and NaN and the infinities.
  Float32
} derive(Debug, Eq)

///|
pub extend ValueRange with @debug.Debug::{to_repr}

///|
pub extend ValueRange with Eq::{equal, not_equal}

///|
/// Why an Ion value does not decode as the requested type. Every case names
/// the `path` from the decoded root to the value that failed, outermost step
/// first; an empty path is the root.
pub(all) suberror FromIonError {
  /// The value, or a null of any type, is not the Ion type the target reads.
  TypeMismatch(
    path~ : Array[PathSegment],
    expected~ : IonType,
    actual~ : IonValueKind
  )
  /// The value has the right Ion type but does not fit the target.
  OutOfRange(
    path~ : Array[PathSegment],
    actual~ : IonValueKind,
    range~ : ValueRange
  )
  /// A list or string has the wrong number of elements or characters for a
  /// tuple or a `Char`.
  WrongLength(
    path~ : Array[PathSegment],
    actual~ : IonValueKind,
    expected~ : Int32
  )
  /// A struct repeats a field name that the target can hold only once.
  DuplicateField(path~ : Array[PathSegment], name~ : String)
  /// A symbol value or a field name has no known text.
  MissingSymbolText(path~ : Array[PathSegment], token~ : SymbolToken)
  /// The JSON form of the value does not decode as the target. `message` is
  /// the JSON decoder's own message.
  JsonDecode(path~ : Array[PathSegment], message~ : String)
} derive(Debug)

///|
pub extend FromIonError with @debug.Debug::{to_repr}

///|
/// The path from the decoded root to the value that failed.
pub fn FromIonError::path(self : FromIonError) -> Array[PathSegment] {
  match self {
    TypeMismatch(path~, ..)
    | OutOfRange(path~, ..)
    | WrongLength(path~, ..)
    | DuplicateField(path~, ..)
    | MissingSymbolText(path~, ..)
    | JsonDecode(path~, ..) => path
  }
}

///|
/// The same error, one level further out: `segment` goes in front of the
/// path. A container calls this when one of its elements fails.
pub fn FromIonError::within(
  self : FromIonError,
  segment : PathSegment,
) -> FromIonError {
  let path : Array[PathSegment] = Array(capacity=self.path().length() + 1)
  path.push(segment)
  path.append(self.path())
  match self {
    TypeMismatch(expected~, actual~, ..) =>
      TypeMismatch(path~, expected~, actual~)
    OutOfRange(actual~, range~, ..) => OutOfRange(path~, actual~, range~)
    WrongLength(actual~, expected~, ..) =>
      WrongLength(path~, actual~, expected~)
    DuplicateField(name~, ..) => DuplicateField(path~, name~)
    MissingSymbolText(token~, ..) => MissingSymbolText(path~, token~)
    JsonDecode(message~, ..) => JsonDecode(path~, message~)
  }
}

///|
/// A human-readable message: the path in `$` notation (`$.name[0]`), then
/// what was expected and what was found.
pub fn FromIonError::message(self : FromIonError) -> String {
  let builder = StringBuilder()
  builder.write_string("$")
  for segment in self.path() {
    match segment {
      Name(name) if is_plain_name(name) => {
        builder.write_string(".")
        builder.write_string(name)
      }
      Name(name) => {
        builder.write_string("[")
        builder.write_string(name.escape())
        builder.write_string("]")
      }
      Index(index) => {
        builder.write_string("[")
        builder.write_string(index.to_string())
        builder.write_string("]")
      }
    }
  }
  builder.write_string(": ")
  match self {
    TypeMismatch(expected~, actual~, ..) => {
      builder.write_string("expected ")
      builder.write_string(expected.to_text())
      builder.write_string(", found ")
      builder.write_string(kind_text(actual))
    }
    OutOfRange(actual~, range~, ..) => {
      builder.write_string(kind_text(actual))
      match actual {
        Int(number) => {
          builder.write_string(" ")
          builder.write_string(number.to_string())
        }
        Float(number) => {
          builder.write_string(" ")
          builder.write_string(number.to_string())
        }
        _ => ()
      }
      builder.write_string(" is outside the range ")
      match range {
        Integers(min~, max~) => {
          builder.write_string(min.to_string())
          builder.write_string(" to ")
          builder.write_string(max.to_string())
        }
        Float32 => builder.write_string("of a 32-bit float")
      }
    }
    WrongLength(actual~, expected~, ..) => {
      builder.write_string("expected ")
      builder.write_string(kind_text(actual))
      builder.write_string(" of length ")
      builder.write_string(expected.to_string())
      match actual {
        String(text) if has_unpaired_surrogate(text) =>
          builder.write_string(", found a string with an unpaired surrogate")
        _ => {
          builder.write_string(", found length ")
          builder.write_string(kind_length(actual).to_string())
        }
      }
    }
    DuplicateField(name~, ..) => {
      builder.write_string("duplicate field name ")
      builder.write_string(name.escape())
    }
    MissingSymbolText(token~, ..) => {
      builder.write_string("symbol ")
      match token.sid() {
        Some(sid) => builder.write_string("$" + sid.to_string())
        None => builder.write_string("with no symbol ID")
      }
      builder.write_string(" has no known text")
    }
    JsonDecode(message~, ..) => builder.write_string(message)
  }
  builder.to_string()
}

///|
/// Whether `name` can follow a `.` in a path: an identifier.
fn is_plain_name(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  for index, character in name {
    match character {
      'a'..<='z' | 'A'..<='Z' | '_' | '$' => ()
      '0'..<='9' if index > 0 => ()
      _ => return false
    }
  }
  true
}

///|
/// How a message names the kind of a value: its Ion type, or the null and
/// its type, as Ion text writes it (`null`, `null.int`).
fn kind_text(kind : IonValueKind) -> String {
  match kind {
    Null(Null) => "null"
    Null(ion_type) => "null." + ion_type.to_text()
    other => IonValue::{ annotations: [], kind: other, }.ion_type().to_text()
  }
}

///|
/// The number of elements of a container or characters of a string.
fn kind_length(kind : IonValueKind) -> Int32 {
  match kind {
    String(text) => text.iter().count()
    List(items) | Sexp(items) => items.length()
    Struct(fields) => fields.length()
    _ => 0
  }
}

///|
/// Whether `text` holds a UTF-16 surrogate that is not part of a pair. Such a
/// string has no Unicode scalar value there; the readers never produce one,
/// but a string built in code can hold one.
fn has_unpaired_surrogate(text : String) -> Bool {
  text.iter().any(character => character.to_int().is_surrogate())
}

///|
/// A type mismatch at the root.
fn mismatch(expected : IonType, value : Ion) -> FromIonError {
  TypeMismatch(path=[], expected~, actual=value.kind)
}

///|
/// The Ion int in `value`, when it is between `min` and `max`.
fn int_between(
  value : Ion,
  min : BigInt,
  max : BigInt,
) -> BigInt raise FromIonError {
  match value.kind {
    Int(number) if number < min || number > max =>
      raise OutOfRange(path=[], actual=value.kind, range=Integers(min~, max~))
    Int(number) => number
    _ => raise mismatch(Int, value)
  }
}

///|
pub impl FromIon for Unit with fn from_ion(value : Ion) -> Unit raise FromIonError {
  match value.kind {
    Null(Null) => ()
    _ => raise mismatch(Null, value)
  }
}

///|
pub impl FromIon for Bool with fn from_ion(value : Ion) -> Bool raise FromIonError {
  match value.kind {
    Bool(flag) => flag
    _ => raise mismatch(Bool, value)
  }
}

///|
pub impl FromIon for Int32 with fn from_ion(value : Ion) -> Int32 raise FromIonError {
  int_between(value, -2147483648N, 2147483647N).to_int()
}

///|
pub impl FromIon for Int64 with fn from_ion(value : Ion) -> Int64 raise FromIonError {
  int_between(value, -9223372036854775808N, 9223372036854775807N).to_int64()
}

///|
pub impl FromIon for UInt32 with fn from_ion(value : Ion) -> UInt32 raise FromIonError {
  int_between(value, 0N, 4294967295N).to_uint()
}

///|
pub impl FromIon for UInt64 with fn from_ion(value : Ion) -> UInt64 raise FromIonError {
  int_between(value, 0N, 18446744073709551615N).to_uint64()
}

///|
pub impl FromIon for BigInt with fn from_ion(value : Ion) -> BigInt raise FromIonError {
  match value.kind {
    Int(number) => number
    _ => raise mismatch(Int, value)
  }
}

///|
pub impl FromIon for Double with fn from_ion(value : Ion) -> Double raise FromIonError {
  match value.kind {
    Float(number) => number
    _ => raise mismatch(Float, value)
  }
}

///|
/// Rounds to the nearest `Float`. A finite value that rounds to an infinity
/// is out of range.
pub impl FromIon for Float with fn from_ion(value : Ion) -> Float raise FromIonError {
  match value.kind {
    Float(number) => {
      let rounded = Float::from_double(number)
      if rounded.to_double().is_inf() && !number.is_inf() {
        raise OutOfRange(path=[], actual=value.kind, range=Float32)
      }
      rounded
    }
    _ => raise mismatch(Float, value)
  }
}

///|
pub impl FromIon for String with fn from_ion(value : Ion) -> String raise FromIonError {
  match value.kind {
    String(text) => text
    _ => raise mismatch(String, value)
  }
}

///|
pub impl FromIon for Bytes with fn from_ion(value : Ion) -> Bytes raise FromIonError {
  match value.kind {
    Blob(bytes) => bytes
    _ => raise mismatch(Blob, value)
  }
}

///|
pub impl FromIon for Decimal with fn from_ion(value : Ion) -> Decimal raise FromIonError {
  match value.kind {
    Decimal(decimal) => decimal
    _ => raise mismatch(Decimal, value)
  }
}

///|
pub impl FromIon for Timestamp with fn from_ion(value : Ion) -> Timestamp raise FromIonError {
  match value.kind {
    Timestamp(timestamp) => timestamp
    _ => raise mismatch(Timestamp, value)
  }
}

///|
/// Reads any Ion symbol, including one with no known text.
pub impl FromIon for SymbolToken with fn from_ion(value : Ion) -> SymbolToken raise FromIonError {
  match value.kind {
    Symbol(token) => token
    _ => raise mismatch(Symbol, value)
  }
}

///|
/// Returns the value unchanged, annotations included.
pub impl FromIon for Ion with fn from_ion(value : Ion) -> Ion {
  value
}

///|
/// Reads an Ion list. An element error gains the element's index.
pub impl[T : FromIon] FromIon for Array[T] with fn from_ion(value : Ion) -> Array[
  T,
] raise FromIonError {
  match value.kind {
    List(items) => {
      let result : Array[T] = Array(capacity=items.length())
      for index, item in items {
        result.push(element(item, index))
      }
      result
    }
    _ => raise mismatch(List, value)
  }
}

///|
/// Reads an Ion struct in field order. Every field name needs known text, and
/// no name may repeat. A field error gains the field's name.
pub impl[T : FromIon] FromIon for Map[String, T] with fn from_ion(value : Ion) -> Map[
  String,
  T,
] raise FromIonError {
  match value.kind {
    Struct(fields) => {
      let result : Map[String, T] = Map([], capacity=fields.length())
      for field in fields {
        let name = symbol_text(field.name)
        if result.contains(name) {
          raise DuplicateField(path=[], name~)
        }
        result.set(
          name,
          FromIon::from_ion(field.value) catch {
            error => raise error.within(Name(name))
          },
        )
      }
      result
    }
    _ => raise mismatch(Struct, value)
  }
}

///|
/// The text of a symbol token: its own text, or the text of the Ion 1.0
/// system symbol with its symbol ID. A token imported from a shared table
/// has no text here.
fn symbol_token_text(token : SymbolToken) -> String? {
  match (token.text, token.import_location, token.sid) {
    (Some(text), _, _) => Some(text)
    (None, None, Some(sid)) => system_symbol_text(sid)
    (None, _, _) => None
  }
}

///|
/// Decode the element at `index` of a list; an error gains the index.
fn[T : FromIon] element(item : Ion, index : Int32) -> T raise FromIonError {
  FromIon::from_ion(item) catch {
    error => raise error.within(Index(index))
  }
}

///|
/// The elements of an Ion list of exactly `length` elements.
fn list_of(value : Ion, length : Int32) -> Array[Ion] raise FromIonError {
  match value.kind {
    List(items) if items.length() == length => items
    List(_) => raise WrongLength(path=[], actual=value.kind, expected=length)
    _ => raise mismatch(List, value)
  }
}

///|
/// Every null, typed or untyped, reads as `None`; any other value reads as
/// `Some` of the inner type.
pub impl[T : FromIon] FromIon for T? with fn from_ion(value : Ion) -> T? raise FromIonError {
  match value.kind {
    Null(_) => None
    _ => Some(FromIon::from_ion(value))
  }
}

///|
/// Reads an Ion string of exactly one Unicode scalar value. An unpaired
/// surrogate is not one.
pub impl FromIon for Char with fn from_ion(value : Ion) -> Char raise FromIonError {
  match value.kind {
    String(text) =>
      match text.iter().to_array() {
        [character] if !character.to_int().is_surrogate() => character
        _ => raise WrongLength(path=[], actual=value.kind, expected=1)
      }
    _ => raise mismatch(String, value)
  }
}

///|
/// Reads an Ion int from 0 to 255.
pub impl FromIon for Byte with fn from_ion(value : Ion) -> Byte raise FromIonError {
  int_between(value, 0N, 255N).to_int().to_byte()
}

///|
/// Reads an Ion list of exactly two elements.
pub impl[A : FromIon, B : FromIon] FromIon for (A, B) with fn from_ion(
  value : Ion,
) -> (A, B) raise FromIonError {
  let items = list_of(value, 2)
  (element(items[0], 0), element(items[1], 1))
}

///|
/// Reads an Ion list of exactly three elements.
pub impl[A : FromIon, B : FromIon, C : FromIon] FromIon for (A, B, C) with fn from_ion(
  value : Ion,
) -> (A, B, C) raise FromIonError {
  let items = list_of(value, 3)
  (element(items[0], 0), element(items[1], 1), element(items[2], 2))
}
