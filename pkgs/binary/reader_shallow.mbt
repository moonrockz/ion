// Direct recursive decoding for shallow values. Keep the container grammar
// in step with reader.mbt; scalar decoders and cursor checks are shared.

///|
/// Decode one value at the cursor: a scalar, a container, or an annotation
/// wrapper. NOP padding is rejected, because a caller that allows it skips it
/// before decoding. `depth` is the nesting depth of the value; a container
/// that exhausts optional caller fuel raises.
fn decode_element_shallow(
  cursor : Cursor,
  table : @ion.SymbolTable,
  depth : @ion.FuelState,
  levels : Int32,
) -> @ion.IonValue raise @ion.IonError {
  if levels == 0 {
    let runner = @work.Runner()
    return runner.run(() => decode_element(runner, cursor, table, depth))
  }
  let descriptor = cursor.octet()
  let type_code = descriptor >> 4
  let nibble = descriptor & 0x0F
  if type_code == 0 && nibble != 0x0F {
    raise @ion.IonError::Syntax("NOP padding is not allowed here")
  }
  if type_code == 14 {
    decode_annotated_shallow(cursor, nibble, table, depth, levels)
  } else {
    decode_typed_shallow(cursor, type_code, nibble, table, depth, levels)
  }
}

///|
/// Decode a value whose type descriptor has already been read.
fn decode_typed_shallow(
  cursor : Cursor,
  type_code : Int32,
  nibble : Int32,
  table : @ion.SymbolTable,
  depth : @ion.FuelState,
  levels : Int32,
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
    11 | 12 =>
      decode_sequence_shallow(
        cursor,
        end,
        table,
        type_code == 11,
        depth.enter(BinaryRead, BinaryOffset(cursor.pos)),
        levels - 1,
      )
    13 =>
      decode_struct_shallow(
        cursor,
        end,
        table,
        depth.enter(BinaryRead, BinaryOffset(cursor.pos)),
        levels - 1,
      )
    _ => raise @ion.IonError::Syntax("reserved Ion binary type code")
  }
  if cursor.pos != end {
    raise @ion.IonError::Syntax("a value used more octets than its length")
  }
  value
}

///|
/// Decode a list or S-expression: its elements, in order. `depth` is the
/// nesting depth inside it.
fn decode_sequence_shallow(
  cursor : Cursor,
  end : Int32,
  table : @ion.SymbolTable,
  is_list : Bool,
  depth : @ion.FuelState,
  levels : Int32,
) -> @ion.IonValue raise @ion.IonError {
  let inner = cursor.scoped(end)
  let items : Array[@ion.IonValue] = []
  while !inner.at_end() {
    if inner.skip_padding() {
      continue
    }
    items.push(decode_element_shallow(inner, table, depth, levels))
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
/// each field. NOP padding is not allowed inside a struct. `depth` is the
/// nesting depth inside it.
fn decode_struct_shallow(
  cursor : Cursor,
  end : Int32,
  table : @ion.SymbolTable,
  depth : @ion.FuelState,
  levels : Int32,
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
    let value = decode_element_shallow(inner, table, depth, levels)
    fields.push(@ion.Field::from_token(name, value))
  }
  cursor.seek(end)
  @ion.IonValue::from_fields(fields)
}

///|
/// Decode an annotation wrapper: a length-prefixed list of annotation symbol
/// IDs followed by the annotated value. Annotations do not add `depth`.
fn decode_annotated_shallow(
  cursor : Cursor,
  nibble : Int32,
  table : @ion.SymbolTable,
  depth : @ion.FuelState,
  levels : Int32,
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
  let value = decode_element_shallow(cursor, table, depth, levels)
  if cursor.pos != end {
    raise @ion.IonError::Syntax("an annotated value has trailing octets")
  }
  if annotations.is_empty() {
    raise @ion.IonError::Syntax("an annotation wrapper needs an annotation")
  }
  value.with_annotations(annotations)
}
