// The Ion binary decoder.
//
// A stream is a sequence of values, each introduced by a type descriptor whose
// low nibble is the length of the representation (or `14` for a `VarUInt`
// length, or `15` for a typed null). An annotation wrapper is a value whose
// representation is an annotation list followed by the annotated value, and a
// local symbol table is an annotated struct that a reader consumes rather than
// returns.

///|
/// Whether a value's length follows its descriptor as a `VarUInt`: a length
/// nibble of 14, or 1 for a struct, which marks an ordered struct (one whose
/// fields are sorted by symbol ID).
fn has_var_uint_length(type_code : Int, nibble : Int) -> Bool {
  nibble == 0x0E || (type_code == 13 && nibble == 1)
}

///|
/// Whether the Ion binary version marker begins at `offset`.
pub fn has_version_marker(bytes : BytesView, offset : Int) -> Bool {
  offset + 4 <= bytes.length() &&
  bytes[offset].to_int() == 0xE0 &&
  bytes[offset + 1].to_int() == 0x01 &&
  bytes[offset + 2].to_int() == 0x00 &&
  bytes[offset + 3].to_int() == 0xEA
}

///|
/// The total octets of the value (or NOP padding) whose descriptor sits at
/// `offset` — the descriptor, its length field, and the representation — or
/// `None` when the input does not hold all of them yet.
fn frame(bytes : BytesView, offset : Int) -> Int? raise @ion.IonError {
  match value_size(bytes, offset) {
    Some(total) if offset + total <= bytes.length() => Some(total)
    _ => None
  }
}

///|
/// The total octets the value (or NOP padding) whose descriptor sits at
/// `offset` spans — the descriptor, its length field, and the representation —
/// once the descriptor and length field have arrived, even when the
/// representation has not. `None` means the length field is still incomplete.
/// A streaming reader uses it to wait for a whole value before decoding.
pub fn value_size(bytes : BytesView, offset : Int) -> Int? raise @ion.IonError {
  if offset >= bytes.length() {
    return None
  }
  let descriptor = bytes[offset].to_int()
  let type_code = descriptor >> 4
  let nibble = descriptor & 0x0F
  let mut header = 1
  let mut length = 0
  if type_code == 1 {
    // A bool's nibble is its value, not a length.
    ()
  } else if nibble == 0x0F {
    // A typed null has no representation.
    ()
  } else if has_var_uint_length(type_code, nibble) {
    let cursor = Cursor::new(bytes, offset + 1, bytes.length())
    let mut value = 0
    let mut done = false
    while !done {
      if cursor.at_end() {
        return None
      }
      if value > 0x00FF_FFFF {
        raise @ion.IonError::Syntax("VarUInt length is too large")
      }
      let octet = cursor.octet()
      value = (value << 7) | (octet & 0x7F)
      if (octet & 0x80) != 0 {
        done = true
      }
    }
    header = 1 + (cursor.pos - (offset + 1))
    length = value
  } else {
    length = nibble
  }
  Some(header + length)
}

///|
/// The Ion type a type code denotes in a typed null, rejecting the codes that
/// have no standalone type.
fn null_type(type_code : Int) -> @ion.IonType raise @ion.IonError {
  match IonTypeCode::from_int(type_code).to_ion_type() {
    Some(ty) => ty
    None => raise @ion.IonError::Syntax("invalid type code for a typed null")
  }
}

///|
/// Decode the value at `offset`: the value itself and the octets it occupied,
/// including any NOP padding skipped before it. Returns `None` when the input
/// does not hold the whole value, and when only padding remains — a streaming
/// reader reads more bytes and retries.
pub fn decode_value(
  bytes : BytesView,
  offset : Int,
  table : @ion.SymbolTable,
) -> (@ion.IonValue, Int)? raise @ion.IonError {
  let mut start = offset
  let mut result : (@ion.IonValue, Int)? = None
  while result is None {
    match frame(bytes, start) {
      None => return None
      Some(total) => {
        let descriptor = bytes[start].to_int()
        let type_code = descriptor >> 4
        let nibble = descriptor & 0x0F
        if type_code == 0 && nibble != 0x0F {
          // NOP padding: skip it and look for the value that follows.
          start += total
        } else {
          let cursor = Cursor::new(bytes, start, start + total)
          result = Some((decode_element(cursor, table), start + total - offset))
        }
      }
    }
  }
  result
}

///|
/// Decode one value at the cursor: a scalar, a container, or an annotation
/// wrapper. NOP padding is rejected, because a caller that allows it skips it
/// before decoding.
fn decode_element(
  cursor : Cursor,
  table : @ion.SymbolTable,
) -> @ion.IonValue raise @ion.IonError {
  let descriptor = cursor.octet()
  let type_code = descriptor >> 4
  let nibble = descriptor & 0x0F
  if type_code == 0 && nibble != 0x0F {
    raise @ion.IonError::Syntax("NOP padding is not allowed here")
  }
  if type_code == 14 {
    decode_annotated(cursor, nibble, table)
  } else {
    decode_typed(cursor, type_code, nibble, table)
  }
}

///|
/// Decode a value whose type descriptor has already been read.
fn decode_typed(
  cursor : Cursor,
  type_code : Int,
  nibble : Int,
  table : @ion.SymbolTable,
) -> @ion.IonValue raise @ion.IonError {
  if nibble == 0x0F {
    return @ion.IonValue::typed_null(null_type(type_code))
  }
  if type_code == 1 {
    // A bool's nibble carries the value.
    return decode_bool(nibble)
  }
  let length = if has_var_uint_length(type_code, nibble) {
    cursor.var_uint()
  } else {
    nibble
  }
  if type_code == 13 && nibble == 1 && length == 0 {
    raise @ion.IonError::Syntax("an ordered struct must not be empty")
  }
  let end = cursor.pos + length
  if end > cursor.limit {
    raise @ion.IonError::Syntax("a value overruns its container")
  }
  let value = match type_code {
    2 | 3 => decode_int(cursor, length, type_code == 3)
    4 => decode_float(cursor, length)
    5 | 6 => {
      // A decimal or a timestamp ends where its length says, not at the end
      // of its container, so it reads through a cursor that stops there.
      let inner = Cursor::new(cursor.bytes, cursor.pos, end)
      let value = if type_code == 5 {
        decode_decimal(inner, length)
      } else {
        decode_timestamp(inner, length)
      }
      cursor.pos = inner.pos
      value
    }
    7 => decode_symbol(cursor, length, table)
    8 => decode_string(cursor, length)
    9 => @ion.IonValue::clob(cursor.take(length).to_owned())
    10 => @ion.IonValue::blob(cursor.take(length).to_owned())
    11 | 12 => decode_sequence(cursor, end, table, type_code == 11)
    13 => decode_struct(cursor, end, table)
    _ => raise @ion.IonError::Syntax("reserved Ion binary type code")
  }
  if cursor.pos != end {
    raise @ion.IonError::Syntax("a value used more octets than its length")
  }
  value
}

///|
/// Decode a bool, whose value is the length nibble.
fn decode_bool(nibble : Int) -> @ion.IonValue raise @ion.IonError {
  match nibble {
    0 => @ion.IonValue::bool(false)
    1 => @ion.IonValue::bool(true)
    _ => raise @ion.IonError::Syntax("a bool must have length nibble 0 or 1")
  }
}

///|
/// Decode an int: a `UInt` magnitude, negative for type code 3.
fn decode_int(
  cursor : Cursor,
  length : Int,
  negative : Bool,
) -> @ion.IonValue raise @ion.IonError {
  if length == 0 {
    if negative {
      raise @ion.IonError::Syntax("a negative int needs a magnitude")
    }
    return @ion.IonValue::int(0)
  }
  let magnitude = cursor.uint(length)
  if negative {
    if magnitude.is_zero() {
      raise @ion.IonError::Syntax("negative zero is not a valid Ion int")
    }
    @ion.IonValue::big_int(magnitude.neg())
  } else {
    @ion.IonValue::big_int(magnitude)
  }
}

///|
/// Decode a float: 0 octets is `0e0`, 4 octets an IEEE-754 binary32, and 8
/// octets an IEEE-754 binary64.
fn decode_float(
  cursor : Cursor,
  length : Int,
) -> @ion.IonValue raise @ion.IonError {
  match length {
    0 => @ion.IonValue::float(0.0)
    4 => {
      let view = cursor.take(4)
      let mut bits = 0
      for index in 0..<4 {
        bits = (bits << 8) | view[index].to_int()
      }
      @ion.IonValue::float(
        Float::reinterpret_from_uint(bits.reinterpret_as_uint()).to_double(),
      )
    }
    8 => {
      let view = cursor.take(8)
      let mut bits : Int64 = 0L
      for index in 0..<8 {
        bits = (bits << 8) | view[index].to_int().to_int64()
      }
      @ion.IonValue::float(bits.reinterpret_as_double())
    }
    _ => raise @ion.IonError::Syntax("a float must be 0, 4, or 8 octets")
  }
}

///|
/// A signed integer value from a magnitude and a sign, preserving negative zero.
fn signed_decimal(
  magnitude : BigInt,
  negative : Bool,
  exponent : Int,
) -> @ion.Decimal {
  if negative && magnitude.is_zero() {
    @ion.Decimal::negative_zero_at(exponent)
  } else if negative {
    @ion.Decimal::new(magnitude.neg(), exponent)
  } else {
    @ion.Decimal::new(magnitude, exponent)
  }
}

///|
/// Decode a decimal: a `VarInt` exponent and an `Int` coefficient. A missing
/// coefficient is zero, and an empty representation is `0d0`.
fn decode_decimal(
  cursor : Cursor,
  length : Int,
) -> @ion.IonValue raise @ion.IonError {
  if length == 0 {
    return @ion.IonValue::decimal(@ion.Decimal::zero())
  }
  let (exponent, exponent_negative) = cursor.var_int()
  let remaining = cursor.remaining()
  let (coefficient, coefficient_negative) = if remaining > 0 {
    cursor.int(remaining)
  } else {
    (BigInt::from_int(0), false)
  }
  let exponent = if exponent_negative { -exponent } else { exponent }
  @ion.IonValue::decimal(
    signed_decimal(coefficient, coefficient_negative, exponent),
  )
}

///|
/// Decode a timestamp: a `VarInt` offset, a `VarUInt` year, then the components
/// present at that precision, and finally the fractional second. The
/// components are in UTC, so the result is shifted back to local time.
fn decode_timestamp(
  cursor : Cursor,
  length : Int,
) -> @ion.IonValue raise @ion.IonError {
  if length == 0 {
    raise @ion.IonError::Syntax(
      "a timestamp needs at least an offset and a year",
    )
  }
  let (offset_minutes, offset_negative) = cursor.var_int()
  let offset = if offset_negative && offset_minutes == 0 {
    @ion.TimestampOffset::Unknown
  } else if offset_negative {
    @ion.TimestampOffset::Known(-offset_minutes)
  } else {
    @ion.TimestampOffset::Known(offset_minutes)
  }
  let year = cursor.var_uint()
  let components : Array[Int] = []
  while !cursor.at_end() && components.length() < 5 {
    components.push(cursor.var_uint())
  }
  let month = if components.length() > 0 { Some(components[0]) } else { None }
  let day = if components.length() > 1 { Some(components[1]) } else { None }
  let hour = if components.length() > 2 { Some(components[2]) } else { None }
  let minute = if components.length() > 3 { Some(components[3]) } else { None }
  let second = if components.length() > 4 { Some(components[4]) } else { None }
  let mut fraction : @ion.Decimal? = None
  if !cursor.at_end() {
    let (exponent, exponent_negative) = cursor.var_int()
    let remaining = cursor.remaining()
    let (coefficient, coefficient_negative) = if remaining > 0 {
      cursor.int(remaining)
    } else {
      (BigInt::from_int(0), false)
    }
    let exponent = if exponent_negative { -exponent } else { exponent }
    if !(coefficient.is_zero() && exponent > -1) {
      fraction = Some(
        signed_decimal(coefficient, coefficient_negative, exponent),
      )
    }
  }
  // The components are in UTC. A timestamp with no time of day has no offset
  // to apply; the model leaves it out, matching Ion text.
  let has_time = hour is Some(_) && minute is Some(_)
  let utc = @ion.Timestamp::new(
    year~,
    month~,
    day~,
    hour~,
    minute~,
    second~,
    fraction~,
    offset=if has_time { Some(@ion.TimestampOffset::Known(0)) } else { None },
  )
  // The components must describe a real moment in UTC too.
  utc.validate()
  @ion.IonValue::timestamp(if has_time { utc.with_offset(offset) } else { utc })
}

///|
/// Decode a symbol: a `UInt` symbol ID.
fn decode_symbol(
  cursor : Cursor,
  length : Int,
  table : @ion.SymbolTable,
) -> @ion.IonValue raise @ion.IonError {
  let sid = if length == 0 { 0 } else { cursor.uint(length).to_int() }
  @ion.IonValue::symbol_token(table.lookup(sid))
}

///|
/// Decode a string: UTF-8 octets.
fn decode_string(
  cursor : Cursor,
  length : Int,
) -> @ion.IonValue raise @ion.IonError {
  let view = cursor.take(length)
  let text = @utf8.decode(view) catch {
    _ => raise @ion.IonError::Syntax("a string is not valid UTF-8")
  }
  @ion.IonValue::string(text)
}

///|
/// Decode a list or S-expression: its elements, in order.
fn decode_sequence(
  cursor : Cursor,
  end : Int,
  table : @ion.SymbolTable,
  is_list : Bool,
) -> @ion.IonValue raise @ion.IonError {
  let inner = cursor.scoped(end)
  let items : Array[@ion.IonValue] = []
  while !inner.at_end() {
    if inner.skip_padding() {
      continue
    }
    items.push(decode_element(inner, table))
  }
  cursor.seek(end)
  if is_list {
    @ion.IonValue::list(items)
  } else {
    @ion.IonValue::sexp(items)
  }
}

///|
/// Decode a struct: a `VarUInt` field-name symbol ID followed by its value, for
/// each field. NOP padding is not allowed inside a struct.
fn decode_struct(
  cursor : Cursor,
  end : Int,
  table : @ion.SymbolTable,
) -> @ion.IonValue raise @ion.IonError {
  let inner = cursor.scoped(end)
  let fields : Array[@ion.Field] = []
  while !inner.at_end() {
    let sid = inner.var_uint()
    // A field whose value is NOP padding is ignored, name and all.
    if inner.skip_padding() {
      continue
    }
    let name = table.lookup(sid)
    let value = decode_element(inner, table)
    fields.push(@ion.Field::from_token(name, value))
  }
  cursor.seek(end)
  @ion.IonValue::from_fields(fields)
}

///|
/// Decode an annotation wrapper: a length-prefixed list of annotation symbol
/// IDs followed by the annotated value.
fn decode_annotated(
  cursor : Cursor,
  nibble : Int,
  table : @ion.SymbolTable,
) -> @ion.IonValue raise @ion.IonError {
  let length = if nibble == 0x0E { cursor.var_uint() } else { nibble }
  let end = cursor.pos + length
  if end > cursor.limit {
    raise @ion.IonError::Syntax("an annotation wrapper overruns its container")
  }
  let annotation_length = cursor.var_uint()
  let annotation_end = cursor.pos + annotation_length
  if annotation_end > end {
    raise @ion.IonError::Syntax("an annotation list overruns its wrapper")
  }
  let annotations : Array[@ion.SymbolToken] = []
  while cursor.pos < annotation_end {
    let sid = cursor.var_uint()
    annotations.push(table.lookup(sid))
  }
  if cursor.at_end() {
    raise @ion.IonError::Syntax("an annotation wrapper has no value")
  }
  let descriptor = cursor.bytes[cursor.pos].to_int()
  let inner_type = descriptor >> 4
  let inner_nibble = descriptor & 0x0F
  if inner_type == 14 {
    raise @ion.IonError::Syntax("nested annotation wrappers are not allowed")
  }
  if inner_type == 0 && inner_nibble != 0x0F {
    raise @ion.IonError::Syntax(
      "NOP padding is not allowed in an annotation wrapper",
    )
  }
  let value = decode_element(cursor, table)
  if cursor.pos != end {
    raise @ion.IonError::Syntax("an annotated value has trailing octets")
  }
  if annotations.is_empty() {
    raise @ion.IonError::Syntax("an annotation wrapper needs an annotation")
  }
  value.with_annotations(annotations)
}

///|
/// Whether the octets from `offset` to the end are all NOP padding.
pub fn is_padding_only(
  bytes : BytesView,
  offset : Int,
) -> Bool raise @ion.IonError {
  let cursor = Cursor::new(bytes, offset, bytes.length())
  while !cursor.at_end() {
    if !cursor.skip_padding() {
      return false
    }
  }
  true
}

///|
/// Consume a top-level value as a reader sees it: a local symbol table updates
/// `symbols`, and an unannotated symbol with the text `$ion_1_0` is a no-op
/// (only the four-octet marker is a version marker in Ion binary); neither is
/// returned. Everything else is a value.
pub fn accept_value(
  symbols : @ion.SymbolTable,
  value : @ion.IonValue,
) -> @ion.IonValue? raise @ion.IonError {
  if value.annotations().is_empty() &&
    value.kind() is @ion.IonValueKind::Symbol(token) &&
    token.text() == Some("$ion_1_0") {
    return None
  }
  if symbols.apply_local_symbol_table(value) {
    None
  } else {
    Some(value)
  }
}

///|
/// Decode an Ion binary datagram. A leading version marker is optional: a bare
/// sequence of values is a valid Ion stream. `catalog` supplies the shared
/// symbol tables that local symbol tables import.
pub fn read_binary(
  bytes : BytesView,
  catalog? : @ion.Catalog = @ion.Catalog::new(),
) -> Array[@ion.IonValue] raise @ion.IonError {
  let table = @ion.SymbolTable::system(catalog~)
  let values : Array[@ion.IonValue] = []
  let mut offset = 0
  while offset < bytes.length() {
    if has_version_marker(bytes, offset) {
      offset += 4
      table.reset()
      continue
    }
    match decode_value(bytes, offset, table) {
      Some((value, consumed)) => {
        offset += consumed
        match accept_value(table, value) {
          Some(value) => values.push(value)
          None => ()
        }
      }
      None =>
        if is_padding_only(bytes, offset) {
          offset = bytes.length()
        } else {
          raise @ion.IonError::Syntax("truncated Ion binary value")
        }
    }
  }
  values
}

///|
/// Decode exactly one Ion binary value, rejecting anything after it.
pub fn read_binary_value(
  bytes : BytesView,
  catalog? : @ion.Catalog = @ion.Catalog::new(),
) -> @ion.IonValue raise @ion.IonError {
  let values = read_binary(bytes, catalog~)
  match values {
    [value] => value
    [] =>
      raise @ion.IonError::Syntax("expected one Ion binary value, found none")
    _ =>
      raise @ion.IonError::Syntax(
        "expected one Ion binary value, found several",
      )
  }
}
