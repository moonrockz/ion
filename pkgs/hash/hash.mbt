// Ion Hash: an encoding-independent hash of an Ion value.
//
// Implements Ion Hash 1.0
// (<https://amazon-ion.github.io/ion-hash/docs/spec.html>): a value is
// serialized to a canonical byte sequence that does not depend on the encoding
// (text or binary) or on symbol IDs, then hashed. Because structs are
// unordered, their field hashes are sorted before hashing.

///|
/// The 32-byte SHA-256 Ion Hash of `value`.
pub fn ion_hash(value : @ion.IonValue) -> Bytes raise @ion.IonError {
  ion_hash_with(value, sha256)
}

///|
/// The SHA-256 Ion Hash of `value`, as lowercase hexadecimal.
pub fn ion_hash_hex(value : @ion.IonValue) -> String raise @ion.IonError {
  hex(bytes_to_array(ion_hash(value)))
}

///|
/// The Ion Hash of `value` under a caller-supplied digest function `h`:
/// `h(s(value))`. The same `h` computes struct field hashes, as the
/// specification requires. With the identity function this returns the
/// serialization `s(value)` itself, so a conformance test can compare those
/// bytes directly.
pub fn ion_hash_with(
  value : @ion.IonValue,
  hash : (Array[Byte]) -> Array[Byte],
) -> Bytes raise @ion.IonError {
  Bytes::from_array(hash(serialize_with(value, hash)))
}

///|
/// SHA-256 of a byte sequence.
fn sha256(bytes : Array[Byte]) -> Array[Byte] {
  let hasher = @crypto.SHA256::new()
  hasher.update(Bytes::from_array(bytes))
  let digest = hasher.finalize()
  let result : Array[Byte] = []
  for index in 0..<digest.length() {
    result.push(digest[index])
  }
  result
}

///|
/// Lowercase hexadecimal of a byte sequence.
fn hex(bytes : Array[Byte]) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder()
  for byte in bytes {
    let value = byte.to_int()
    sb.write_view(digits[value >> 4:(value >> 4) + 1])
    sb.write_view(digits[value & 0xF:(value & 0xF) + 1])
  }
  sb.to_string()
}

///|
/// The UTF-8 bytes of a string.
fn utf8_bytes(text : String) -> Array[Byte] {
  @utf8.encode(text).to_array()
}

///|
/// The Ion Hash serialization `s(value)` of a value, including its annotations.
/// Struct field hashes use `hash` (the caller's `h`).
fn serialize_with(
  value : @ion.IonValue,
  hash : (Array[Byte]) -> Array[Byte],
) -> Array[Byte] raise @ion.IonError {
  if value.has_annotations() {
    let out : Array[Byte] = [0x0B, 0xE0]
    for annotation in value.annotations() {
      append_bytes(out, symbol_serialization(annotation))
    }
    append_bytes(out, body_serialization(value.with_annotations([]), hash))
    out.push(0x0E)
    out
  } else {
    body_serialization(value, hash)
  }
}

///|
/// A symbol's text: its own, or the Ion 1.0 system text for its symbol ID.
fn symbol_text(token : @ion.SymbolToken) -> String? {
  match token.text() {
    Some(text) => Some(text)
    None =>
      match token.sid() {
        Some(sid) => @ion.system_symbol_text(sid)
        None => None
      }
  }
}

///|
/// `TQ || escape(representation)` for a symbol. Text — the symbol's own, or a
/// resolved system symbol ID — uses Q=0; symbol ID zero uses Q=1 and no
/// representation. Any other textless symbol is an error, because its text
/// cannot be recovered.
fn symbol_body(token : @ion.SymbolToken) -> Array[Byte] raise @ion.IonError {
  let out : Array[Byte] = []
  match symbol_text(token) {
    Some(text) => {
      out.push(0x70)
      append_escaped(out, utf8_bytes(text))
    }
    None =>
      match token.sid() {
        Some(0) => out.push(0x71)
        _ =>
          raise @ion.IonError::DataModel(
            "cannot hash a symbol whose text is unknown",
          )
      }
  }
  out
}

///|
/// `s(symbol)`: a symbol serialized as `B || TQ || escape(representation) || E`.
fn symbol_serialization(
  token : @ion.SymbolToken,
) -> Array[Byte] raise @ion.IonError {
  let out : Array[Byte] = [0x0B]
  append_bytes(out, symbol_body(token))
  out.push(0x0E)
  out
}

///|
/// The Ion binary type code `T` for an Ion type.
fn type_code(t : @ion.IonType) -> Int {
  match t {
    @ion.IonType::Null => 0
    @ion.IonType::Bool => 1
    @ion.IonType::Int => 2
    @ion.IonType::Float => 4
    @ion.IonType::Decimal => 5
    @ion.IonType::Timestamp => 6
    @ion.IonType::Symbol => 7
    @ion.IonType::String => 8
    @ion.IonType::Clob => 9
    @ion.IonType::Blob => 10
    @ion.IonType::List => 11
    @ion.IonType::Sexp => 12
    @ion.IonType::Struct => 13
  }
}

///|
/// The magnitude of a `BigInt`, as a non-negative value.
fn magnitude(value : BigInt) -> BigInt {
  if value.compare_int(0) < 0 {
    value.neg()
  } else {
    value
  }
}

///|
/// `s(value)` for a value whose annotations the caller has already handled.
fn body_serialization(
  value : @ion.IonValue,
  hash : (Array[Byte]) -> Array[Byte],
) -> Array[Byte] raise @ion.IonError {
  let out : Array[Byte] = [0x0B]
  match value.kind() {
    @ion.IonValueKind::Null(t) =>
      out.push(((type_code(t) << 4) | 0x0F).to_byte())
    @ion.IonValueKind::Bool(b) =>
      out.push((0x10 | (if b { 1 } else { 0 })).to_byte())
    @ion.IonValueKind::Int(n) =>
      if n.is_zero() {
        out.push(0x20)
      } else if n.compare_int(0) < 0 {
        out.push(0x30)
        let rep : Array[Byte] = []
        append_uint(rep, magnitude(n))
        append_escaped(out, rep)
      } else {
        out.push(0x20)
        let rep : Array[Byte] = []
        append_uint(rep, n)
        append_escaped(out, rep)
      }
    @ion.IonValueKind::Float(f) => {
      out.push(0x40)
      append_escaped(out, float_representation(f))
    }
    @ion.IonValueKind::Decimal(d) => {
      out.push(0x50)
      append_escaped(out, decimal_representation(d))
    }
    @ion.IonValueKind::Timestamp(ts) => {
      out.push(0x60)
      append_escaped(out, timestamp_representation(ts))
    }
    @ion.IonValueKind::Symbol(token) => append_bytes(out, symbol_body(token))
    @ion.IonValueKind::String(text) => {
      out.push(0x80)
      append_escaped(out, utf8_bytes(text))
    }
    @ion.IonValueKind::Clob(bytes) => {
      out.push(0x90)
      append_escaped(out, bytes.to_array())
    }
    @ion.IonValueKind::Blob(bytes) => {
      out.push(0xA0)
      append_escaped(out, bytes.to_array())
    }
    @ion.IonValueKind::List(items) => {
      out.push(0xB0)
      for item in items {
        append_bytes(out, serialize_with(item, hash))
      }
    }
    @ion.IonValueKind::Sexp(items) => {
      out.push(0xC0)
      for item in items {
        append_bytes(out, serialize_with(item, hash))
      }
    }
    @ion.IonValueKind::Struct(fields) => {
      out.push(0xD0)
      append_escaped(out, struct_representation(fields, hash))
    }
  }
  out.push(0x0E)
  out
}

///|
/// A float's representation: its canonical 8-octet IEEE-754 pattern, with
/// `+0e0` omitted and the special values pinned.
fn float_representation(value : Double) -> Array[Byte] {
  if value.is_nan() {
    return [0x7F, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
  }
  if value.is_pos_inf() {
    return [0x7F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
  }
  if value.is_neg_inf() {
    return [0xFF, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
  }
  let out : Array[Byte] = []
  if value == 0.0 && value.reinterpret_as_int64() >= 0 {
    // +0e0 has no representation.
    return out
  }
  let bits = value.reinterpret_as_uint64()
  for index in 0..<8 {
    out.push(((bits >> ((7 - index) * 8)).to_int() & 0xFF).to_byte())
  }
  out
}

///|
/// A decimal's representation: `VarInt` exponent then `Int` coefficient, with
/// the coefficient omitted when it is (positive) zero and `0d0` encoded as an
/// empty representation.
fn decimal_representation(d : @ion.Decimal) -> Array[Byte] {
  let out : Array[Byte] = []
  let coefficient = d.coefficient()
  let exponent = d.exponent()
  let negative = d.is_negative()
  let positive_zero = coefficient.is_zero() && !negative
  if positive_zero && exponent == 0 {
    return out
  }
  append_var_int(out, magnitude_int(exponent), exponent < 0)
  if !positive_zero {
    append_int(out, magnitude(coefficient), negative)
  }
  out
}

///|
/// The magnitude of an `Int`.
fn magnitude_int(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
/// A timestamp's representation: `VarInt` offset, `VarUInt` year, then the
/// present (contiguous) components. The date and time are normalized to UTC
/// when the offset is known (`-00:00` has no offset to apply), and a zero
/// fractional second is omitted when its exponent is greater than `-1`.
fn timestamp_representation(ts : @ion.Timestamp) -> Array[Byte] {
  let out : Array[Byte] = []
  match ts.offset() {
    Some(@ion.TimestampOffset::Known(minutes)) =>
      append_var_int(out, magnitude_int(minutes), minutes < 0)
    _ => append_var_int(out, 0, true)
  }
  let utc = ts.as_utc()
  append_var_uint(out, utc.year())
  for
    component in [
      utc.month(),
      utc.day(),
      utc.hour(),
      utc.minute(),
      utc.second(),
    ] {
    match component {
      Some(value) => append_var_uint(out, value)
      None => ()
    }
  }
  match ts.fraction() {
    Some(fraction) => {
      let coefficient = fraction.coefficient()
      let exponent = fraction.exponent()
      if !(coefficient.is_zero() && exponent > -1) {
        append_var_int(out, magnitude_int(exponent), exponent < 0)
        if !coefficient.is_zero() {
          append_int(out, magnitude(coefficient), false)
        }
      }
    }
    None => ()
  }
  out
}

///|
/// A struct's representation: the sorted field hashes, concatenated.
fn struct_representation(
  fields : Array[@ion.Field],
  hash : (Array[Byte]) -> Array[Byte],
) -> Array[Byte] raise @ion.IonError {
  let hashes : Array[Array[Byte]] = []
  for field in fields {
    let buffer : Array[Byte] = []
    append_bytes(buffer, symbol_serialization(field.name()))
    append_bytes(buffer, serialize_with(field.value(), hash))
    hashes.push(hash(buffer))
  }
  hashes.sort_by(compare_bytes)
  let out : Array[Byte] = []
  for digest in hashes {
    append_bytes(out, digest)
  }
  out
}

///|
/// Lexicographic comparison of octets as unsigned integers.
fn compare_bytes(a : Array[Byte], b : Array[Byte]) -> Int {
  let shared = if a.length() < b.length() { a.length() } else { b.length() }
  for index in 0..<shared {
    let left = a[index].to_int()
    let right = b[index].to_int()
    if left != right {
      return if left < right { -1 } else { 1 }
    }
  }
  if a.length() == b.length() {
    0
  } else if a.length() < b.length() {
    -1
  } else {
    1
  }
}

///|
/// Copy a byte sequence into a growable array.
fn bytes_to_array(bytes : Bytes) -> Array[Byte] {
  let result : Array[Byte] = []
  for index in 0..<bytes.length() {
    result.push(bytes[index])
  }
  result
}
