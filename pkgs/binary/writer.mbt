// The Ion binary encoder.
//
// Each value is written as a type descriptor, a length (in the low nibble, or a
// `VarUInt` when it does not fit), and the representation. A datagram starts
// with the version marker and, when the values use symbols the system table
// does not define, a local symbol table that declares them.

///|
/// The magnitude of an `Int`.
fn abs_int(value : Int32) -> Int32 {
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
/// Append a type descriptor and length for a representation of `length`
/// octets.
fn push_header(out : Array[Byte], type_code : Int32, length : Int32) -> Unit {
  if length < 14 {
    out.push(((type_code << 4) | length).to_byte())
  } else {
    out.push(((type_code << 4) | 14).to_byte())
    push_var_uint(out, length)
  }
}

///|
/// A type descriptor and length for a representation of `length` octets.
fn header_octets(type_code : Int32, length : Int32) -> Array[Byte] {
  let out : Array[Byte] = []
  push_header(out, type_code, length)
  out
}

///|
/// Prepend a type descriptor and length to a representation.
fn wrap(type_code : Int32, representation : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = Array(capacity=representation.length() + 6)
  push_header(out, type_code, representation.length())
  out.append(representation)
  out
}

///|
/// The symbol ID assigned by the writer context, including imported symbols.
fn symbol_id(
  token : @ion.SymbolToken,
  symbols : @ion.SymbolTable,
) -> Int32 raise @ion.IonError {
  symbols.intern_token(token)
}

///|
/// Encode a field-name ID in an existing writer context.
pub fn encode_field_name(
  token : @ion.SymbolToken,
  symbols : @ion.SymbolTable,
) -> Bytes raise @ion.IonError {
  let out : Array[Byte] = []
  push_var_uint(out, symbol_id(token, symbols))
  Bytes::from_array(out)
}

///|
/// Encode an already-buffered container body, with its length and annotations.
pub fn encode_container(
  kind : @ion.IonType,
  body : Bytes,
  annotations : Array[@ion.SymbolToken],
  symbols : @ion.SymbolTable,
) -> Bytes raise @ion.IonError {
  @ion.check_container_kind(kind)
  let value = wrap(IonTypeCode::from_ion_type(kind).to_int(), body.to_array())
  if annotations.is_empty() {
    return Bytes::from_array(value)
  }
  let ids : Array[Byte] = []
  for annotation in annotations {
    push_var_uint(ids, symbol_id(annotation, symbols))
  }
  let inner : Array[Byte] = []
  push_var_uint(inner, ids.length())
  inner.append(ids)
  inner.append(value)
  Bytes::from_array(wrap(14, inner))
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
/// The representation of a scalar: its descriptor, length and content.
fn encode_scalar(
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
    @ion.IonValueKind::List(_)
    | @ion.IonValueKind::Sexp(_)
    | @ion.IonValueKind::Struct(_) => abort("encode_start encodes containers")
  }
}

///|
/// A place in the body where a container's header goes. The header holds the
/// length of what follows it, so it is known only when the container closes.
priv struct HeaderGap {
  position : Int32
  mut header : Array[Byte]
}

///|
/// A container the encoder is inside.
priv struct OpenContainer {
  value : @ion.IonValue
  /// The index of its next child.
  mut next : Int32
  /// Its index in the gaps.
  gap : Int32
  /// Where its content starts in the body.
  start : Int32
  type_code : Int32
  /// Its annotation symbol IDs, as `VarUInt`s.
  ids : Array[Byte]
  /// The header octets of the containers inside it, which are not in the body.
  mut nested : Int32
}

///|
/// The symbol IDs of `annotations`, as `VarUInt`s.
fn annotation_ids(
  annotations : Array[@ion.SymbolToken],
  symbols : @ion.SymbolTable,
) -> Array[Byte] raise @ion.IonError {
  let ids : Array[Byte] = []
  for annotation in annotations {
    push_var_uint(ids, symbol_id(annotation, symbols))
  }
  ids
}

///|
/// An annotation wrapper around a value of `length` octets whose own header
/// is `header`, or `header` alone when there are no annotations.
fn annotated_header(
  ids : Array[Byte],
  header : Array[Byte],
  length : Int32,
) -> Array[Byte] {
  if ids.is_empty() {
    return header
  }
  let count : Array[Byte] = []
  push_var_uint(count, ids.length())
  let wrapped = count.length() + ids.length() + header.length() + length
  let out = header_octets(14, wrapped)
  out.append(count)
  out.append(ids)
  out.append(header)
  out
}

///|
/// Encode one value, with no recursion. The walk writes every octet of the
/// value once into one body, in document order, so symbols are interned in
/// document order: for each value, its field name, then its annotations, then
/// its symbol value. Each container leaves a gap for its header; the headers
/// are computed when their containers close and put into the gaps at the end.
fn encode(
  value : @ion.IonValue,
  symbols : @ion.SymbolTable,
) -> Array[Byte] raise @ion.IonError {
  if !value.has_annotations() &&
    !(value.kind() is (List(_) | Sexp(_) | Struct(_))) {
    return encode_scalar(value.kind(), symbols)
  }
  let body : Array[Byte] = []
  let gaps : Array[HeaderGap] = []
  let open : Array[OpenContainer] = []
  encode_start(body, gaps, open, value, symbols)
  while open.last() is Some(container) {
    let index = container.next
    match container.value.kind() {
      List(items) | Sexp(items) if index < items.length() => {
        container.next = index + 1
        encode_start(body, gaps, open, items[index], symbols)
      }
      Struct(fields) if index < fields.length() => {
        container.next = index + 1
        push_var_uint(body, symbol_id(fields[index].name(), symbols))
        encode_start(body, gaps, open, fields[index].value(), symbols)
      }
      _ => {
        ignore(open.pop())
        let length = body.length() - container.start + container.nested
        let header = annotated_header(
          container.ids,
          header_octets(container.type_code, length),
          length,
        )
        gaps[container.gap].header = header
        if open.last() is Some(parent) {
          parent.nested += container.nested + header.length()
        }
      }
    }
  }
  if gaps.is_empty() {
    return body
  }
  let out : Array[Byte] = Array(
    capacity=body.length() + open_header_octets(gaps),
  )
  let mut copied = 0
  for gap in gaps {
    out.append(body[copied:gap.position])
    out.append(gap.header)
    copied = gap.position
  }
  out.append(body[copied:])
  out
}

///|
/// The total length of the container headers in `gaps`.
fn open_header_octets(gaps : Array[HeaderGap]) -> Int32 {
  let mut total = 0
  for gap in gaps {
    total += gap.header.length()
  }
  total
}

///|
/// Encode `value` up to its children: its annotations, then a whole scalar,
/// or a gap for a container's header, with the container put on `open`. The
/// caller writes a struct field's name first.
fn encode_start(
  body : Array[Byte],
  gaps : Array[HeaderGap],
  open : Array[OpenContainer],
  value : @ion.IonValue,
  symbols : @ion.SymbolTable,
) -> Unit raise @ion.IonError {
  let ids = if value.has_annotations() {
    annotation_ids(value.annotations(), symbols)
  } else {
    []
  }
  let type_code = match value.kind() {
    List(_) => 11
    Sexp(_) => 12
    Struct(_) => 13
    scalar => {
      let representation = encode_scalar(scalar, symbols)
      if !ids.is_empty() {
        body.append(annotated_header(ids, [], representation.length()))
      }
      body.append(representation)
      return
    }
  }
  gaps.push({ position: body.length(), header: [], })
  open.push({
    value,
    next: 0,
    gap: gaps.length() - 1,
    start: body.length(),
    type_code,
    ids,
    nested: 0,
  })
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
