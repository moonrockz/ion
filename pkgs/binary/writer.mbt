// The Ion binary encoder.
//
// Each value is written as a type descriptor, a length (in the low nibble, or a
// `VarUInt` when it does not fit), and the representation. A datagram starts
// with the version marker and, when the values use symbols the system table
// does not define, a local symbol table that declares them.

///|
/// The magnitude of an `Int`.
fn abs_int(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
/// The magnitude of a `BigInt`.
fn magnitude_of(value : BigInt) -> BigInt {
  if value.compare_int(0) < 0 {
    value.neg()
  } else {
    value
  }
}

///|
/// Prepend a type descriptor and length to a representation.
fn wrap(type_code : Int, representation : Array[Byte]) -> Array[Byte] {
  let length_field : Array[Byte] = []
  let nibble = push_length(length_field, representation.length())
  let out : Array[Byte] = [((type_code << 4) | nibble).to_byte()]
  for octet in length_field {
    out.push(octet)
  }
  for octet in representation {
    out.push(octet)
  }
  out
}

///|
/// The symbol ID assigned by the writer context, including imported symbols.
fn symbol_id(
  token : @ion.SymbolToken,
  symbols : @ion.SymbolTable,
) -> Int raise @ion.IonError {
  symbols.intern_token(token)
}

///|
/// A float's representation: its IEEE-754 binary64 pattern.
fn encode_float(value : Double) -> Array[Byte] {
  let bits = value.reinterpret_as_uint64()
  let out : Array[Byte] = []
  for index in 0..<8 {
    out.push(((bits >> ((7 - index) * 8)).to_int() & 0xFF).to_byte())
  }
  out
}

///|
/// A decimal's representation: a `VarInt` exponent then an `Int` coefficient,
/// with the coefficient omitted when it is (positive) zero and `0d0` written as
/// an empty representation.
fn encode_decimal(value : @ion.Decimal) -> Array[Byte] {
  let out : Array[Byte] = []
  let coefficient = value.coefficient()
  let exponent = value.exponent()
  let negative = value.is_negative()
  let positive_zero = coefficient.is_zero() && !negative
  if positive_zero && exponent == 0 {
    return out
  }
  push_var_int(out, abs_int(exponent), exponent < 0)
  if !positive_zero {
    push_int(out, magnitude_of(coefficient), negative)
  }
  out
}

///|
/// A timestamp's representation: a `VarInt` offset, a `VarUInt` year, then the
/// components present at that precision, and finally the fractional second. Ion
/// binary keeps the components in UTC, so they are shifted from local time.
fn encode_timestamp(value : @ion.Timestamp) -> Array[Byte] {
  let out : Array[Byte] = []
  match value.offset() {
    Some(@ion.TimestampOffset::Known(minutes)) =>
      push_var_int(out, abs_int(minutes), minutes < 0)
    _ => push_var_int(out, 0, true)
  }
  let utc = value.as_utc()
  push_var_uint(out, utc.year())
  for
    component in [
      utc.month(),
      utc.day(),
      utc.hour(),
      utc.minute(),
      utc.second(),
    ] {
    match component {
      Some(value) => push_var_uint(out, value)
      None => ()
    }
  }
  match utc.fraction() {
    Some(fraction) => {
      let coefficient = fraction.coefficient()
      let exponent = fraction.exponent()
      let negative = fraction.is_negative()
      let positive_zero = coefficient.is_zero() && !negative
      if !(positive_zero && exponent > -1) {
        push_var_int(out, abs_int(exponent), exponent < 0)
        if !positive_zero {
          push_int(out, magnitude_of(coefficient), negative)
        }
      }
    }
    None => ()
  }
  out
}

///|
/// A symbol's representation: its symbol ID.
fn encode_symbol(
  token : @ion.SymbolToken,
  symbols : @ion.SymbolTable,
) -> Array[Byte] raise @ion.IonError {
  let out : Array[Byte] = []
  push_uint(out, BigInt::from_int(symbol_id(token, symbols)))
  out
}

///|
/// The representations of a list of values, in order.
fn encode_all(
  values : Array[@ion.IonValue],
  symbols : @ion.SymbolTable,
) -> Array[Byte] raise @ion.IonError {
  let out : Array[Byte] = []
  for value in values {
    for octet in encode(value, symbols) {
      out.push(octet)
    }
  }
  out
}

///|
/// The representation of a struct: a `VarUInt` field-name symbol ID followed by
/// each field's value.
fn encode_fields(
  fields : Array[@ion.Field],
  symbols : @ion.SymbolTable,
) -> Array[Byte] raise @ion.IonError {
  let out : Array[Byte] = []
  for field in fields {
    push_var_uint(out, symbol_id(field.name(), symbols))
    for octet in encode(field.value(), symbols) {
      out.push(octet)
    }
  }
  out
}

///|
/// The representation of a value's kind, without its descriptor.
fn encode_body(
  kind : @ion.IonValueKind,
  symbols : @ion.SymbolTable,
) -> Array[Byte] raise @ion.IonError {
  match kind {
    @ion.IonValueKind::Null(t) =>
      [((IonTypeCode::from_ion_type(t).to_int() << 4) | 0x0F).to_byte()]
    @ion.IonValueKind::Bool(value) =>
      [(0x10 | (if value { 1 } else { 0 })).to_byte()]
    @ion.IonValueKind::Int(value) =>
      if value.is_zero() {
        [0x20]
      } else if value.compare_int(0) < 0 {
        wrap(3, magnitude_octets(value.neg()))
      } else {
        wrap(2, magnitude_octets(value))
      }
    @ion.IonValueKind::Float(value) => wrap(4, encode_float(value))
    @ion.IonValueKind::Decimal(value) => wrap(5, encode_decimal(value))
    @ion.IonValueKind::Timestamp(value) => wrap(6, encode_timestamp(value))
    @ion.IonValueKind::Symbol(token) => wrap(7, encode_symbol(token, symbols))
    @ion.IonValueKind::String(text) => wrap(8, @utf8.encode(text).to_array())
    @ion.IonValueKind::Clob(bytes) => wrap(9, bytes.to_array())
    @ion.IonValueKind::Blob(bytes) => wrap(10, bytes.to_array())
    @ion.IonValueKind::List(items) => wrap(11, encode_all(items, symbols))
    @ion.IonValueKind::Sexp(items) => wrap(12, encode_all(items, symbols))
    @ion.IonValueKind::Struct(fields) =>
      wrap(13, encode_fields(fields, symbols))
  }
}

///|
/// Encode one value, wrapping it in an annotation wrapper when it carries
/// annotations.
fn encode(
  value : @ion.IonValue,
  symbols : @ion.SymbolTable,
) -> Array[Byte] raise @ion.IonError {
  if value.has_annotations() {
    let annotations : Array[Byte] = []
    for annotation in value.annotations() {
      push_var_uint(annotations, symbol_id(annotation, symbols))
    }
    let inner : Array[Byte] = []
    push_var_uint(inner, annotations.length())
    for octet in annotations {
      inner.push(octet)
    }
    for octet in encode(value.with_annotations([]), symbols) {
      inner.push(octet)
    }
    wrap(14, inner)
  } else {
    encode_body(value.kind(), symbols)
  }
}

///|
/// The symbol table a datagram needs, retaining unknown shared imports and
/// reserving local unknown IDs before interning known text.
pub fn symbols_for_values(
  values : Array[@ion.IonValue],
) -> @ion.SymbolTable raise @ion.IonError {
  @ion.SymbolTable::for_values(values)
}

///|
/// A local symbol table declaring `symbols`, as a `$ion_symbol_table` annotated
/// struct, or `None` when the system table already defines every symbol.
pub fn local_symbol_table(
  symbols : @ion.SymbolTable,
) -> Bytes? raise @ion.IonError {
  match symbols.to_local_symbol_table() {
    Some(table) => Some(Bytes::from_array(encode(table, symbols)))
    None => None
  }
}

///|
/// Encode a value with an existing symbol table: the value alone, with neither
/// a version marker nor a symbol table of its own. A streaming writer builds
/// one table and encodes every value with it.
pub fn encode_value(
  value : @ion.IonValue,
  symbols : @ion.SymbolTable,
) -> Bytes raise @ion.IonError {
  Bytes::from_array(encode(value, symbols))
}

///|
/// Encode values as an Ion binary datagram: the version marker, a local symbol
/// table when it is needed, and the values.
pub fn write_binary(values : Array[@ion.IonValue]) -> Bytes raise @ion.IonError {
  let symbols = symbols_for_values(values)
  let out : Array[Byte] = []
  for octet in binary_version_marker().to_array() {
    out.push(octet)
  }
  match local_symbol_table(symbols) {
    Some(table) =>
      for octet in table.to_array() {
        out.push(octet)
      }
    None => ()
  }
  for value in values {
    for octet in encode(value, symbols) {
      out.push(octet)
    }
  }
  Bytes::from_array(out)
}

///|
/// Encode a single value as a datagram of its own.
pub fn write_binary_value(value : @ion.IonValue) -> Bytes raise @ion.IonError {
  write_binary([value])
}
