// The Ion text writer.
//
// Values are rendered with a minimal, unambiguous spelling: symbols, strings,
// and clobs are quoted only when they must be, and every float keeps an `e`
// exponent so it is not read back as a decimal.

///|
/// Write a single value as compact Ion text.
pub fn write_ion(value : @ion.IonValue) -> String raise @ion.IonError {
  write_all([value])
}

///|
/// Write a sequence of values (an Ion datagram) as compact Ion text, one value
/// per line.
///
/// A symbol known only by its ID keeps that ID: before the first value that
/// holds such an ID, a local symbol table reserves the IDs up to it with
/// unknown text, so the text reads back to the same symbols.
/// Unknown imported symbols retain their table name, version, and slot; their
/// local IDs may change. Each such value gets its own local symbol table.
pub fn write_all(values : Array[@ion.IonValue]) -> String raise @ion.IonError {
  write_values(values, pretty=false)
}

///|
/// Write a single value as indented Ion text.
pub fn write_ion_pretty(value : @ion.IonValue) -> String raise @ion.IonError {
  write_all_pretty([value])
}

///|
/// Write a sequence of values as indented Ion text, one value per line, as
/// `write_all` does.
pub fn write_all_pretty(
  values : Array[@ion.IonValue],
) -> String raise @ion.IonError {
  write_values(values, pretty=true)
}

///|
/// Write values one per line, each after the local symbol table it needs.
fn write_values(
  values : Array[@ion.IonValue],
  pretty~ : Bool,
) -> String raise @ion.IonError {
  let buffer = StringBuilder()
  let mut reserved = 9
  for index in 0..<values.length() {
    if index > 0 {
      buffer.write_string("\n")
    }
    let (text, now_reserved) = write_stream_value(
      values[index],
      reserved~,
      pretty~,
    )
    buffer.write_string(text)
    reserved = now_reserved
  }
  buffer.to_string()
}

///|
/// Write one value of a stream as `write_all` writes it there. `reserved` is
/// the highest symbol ID that the values before it reserved with unknown text,
/// 9 at the start of a stream. Returns the text, which starts with a local
/// symbol table on its own line when the value holds a symbol known only by an
/// ID above `reserved`, and the highest reserved ID after it.
/// Values containing unknown imported symbols get a complete import context
/// and reset the returned reservation to 9 for later local unknown symbols.
pub fn write_stream_value(
  value : @ion.IonValue,
  reserved~ : Int32,
  pretty~ : Bool = false,
) -> (String, Int32) raise @ion.IonError {
  let buffer = StringBuilder()
  if value.has_imported_symbols() {
    let table = @ion.SymbolTable::for_values([value])
    write_value(
      buffer,
      table.to_local_symbol_table().unwrap(),
      0,
      pretty,
      false,
    )
    buffer.write_string("\n")
    write_value(buffer, table.localize_for_text(value), 0, pretty, false)
    // Any later local unknown IDs need their own context after these imports.
    return (buffer.to_string(), 9)
  }
  let highest = @ion.highest_symbol_id([value])
  let reserved = if highest > reserved {
    let table = @ion.SymbolTable::system()
    table.reserve(highest - 9)
    match table.to_local_symbol_table() {
      Some(table) => {
        write_value(buffer, table, 0, pretty, false)
        buffer.write_string("\n")
      }
      None => ()
    }
    highest
  } else {
    reserved
  }
  write_value(buffer, value, 0, pretty, false)
  (buffer.to_string(), reserved)
}

///|
/// The two-space indentation unit used by the pretty writer.
let indent_unit : String = "  "

///|
/// Render a value inside an existing text context, without symbol-table
/// directives. Incremental writers supply the depth and sexp position.
pub fn write_fragment(
  value : @ion.IonValue,
  depth~ : Int32 = 0,
  pretty~ : Bool = false,
  in_sexp~ : Bool = false,
) -> String raise @ion.IonError {
  let buffer = StringBuilder()
  write_value(buffer, value, depth, pretty, in_sexp)
  buffer.to_string()
}

///|
/// Render a symbol token in an existing text context.
pub fn symbol_to_text(
  token : @ion.SymbolToken,
  in_sexp~ : Bool = false,
) -> String raise @ion.IonError {
  let buffer = StringBuilder()
  write_symbol(buffer, token, in_sexp)
  buffer.to_string()
}

///|
/// Append `depth` indent units.
fn write_indent(buffer : StringBuilder, depth : Int32) -> Unit {
  for _ in 0..<depth {
    buffer.write_string(indent_unit)
  }
}

///|
/// A container the text writer is inside, and the index of its next child.
priv struct TextFrame {
  value : @ion.IonValue
  kind : @ion.IonType
  mut next : Int32
}

///|
/// Render one value into `buffer`, at any depth. `depth` is the pretty indent
/// level of the value, and `in_sexp` says whether the value is inside an
/// S-expression, where an operator symbol is written bare.
fn write_value(
  buffer : StringBuilder,
  value : @ion.IonValue,
  depth : Int32,
  pretty : Bool,
  in_sexp : Bool,
) -> Unit raise @ion.IonError {
  write_shallow(buffer, value, depth, pretty, in_sexp, @ion.MAX_NESTING_DEPTH)
}

///|
/// Render `value` with recursion while `levels` is above zero. At zero levels
/// a container switches to `write_deep`; a scalar stays here. Recursion is the
/// fastest walk; the limit keeps the call stack small at any depth.
fn write_shallow(
  buffer : StringBuilder,
  value : @ion.IonValue,
  depth : Int32,
  pretty : Bool,
  in_sexp : Bool,
  levels : Int32,
) -> Unit raise @ion.IonError {
  if levels == 0 && value.kind() is (List(_) | Sexp(_) | Struct(_)) {
    return write_deep(buffer, value, depth, pretty, in_sexp)
  }
  write_annotations(buffer, value)
  match value.kind() {
    List(items) | Sexp(items) => {
      let kind = value.ion_type()
      let sexp = kind == @ion.IonType::Sexp
      buffer.write_string(open_text(kind))
      for index, item in items {
        write_separator(buffer, index, sexp, depth, pretty)
        write_shallow(buffer, item, depth + 1, pretty, sexp, levels - 1)
      }
      write_close(buffer, kind, items.is_empty(), depth, pretty)
    }
    Struct(fields) => {
      buffer.write_string("{")
      for index, field in fields {
        write_separator(buffer, index, false, depth, pretty)
        write_symbol(buffer, field.name(), false)
        buffer.write_string(": ")
        write_shallow(
          buffer,
          field.value(),
          depth + 1,
          pretty,
          false,
          levels - 1,
        )
      }
      write_close(
        buffer,
        @ion.IonType::Struct,
        fields.is_empty(),
        depth,
        pretty,
      )
    }
    other => write_scalar(buffer, other, in_sexp)
  }
}

///|
/// Write what comes before child `index` of a container whose own indent
/// level is `depth`: the separator after the previous child, and in pretty
/// text a new line and the child's indent.
fn write_separator(
  buffer : StringBuilder,
  index : Int32,
  sexp : Bool,
  depth : Int32,
  pretty : Bool,
) -> Unit {
  if pretty {
    if !sexp && index > 0 {
      buffer.write_string(",")
    }
    buffer.write_string("\n")
    write_indent(buffer, depth + 1)
  } else if index > 0 {
    buffer.write_string(if sexp { " " } else { ", " })
  }
}

///|
/// Close a container whose own indent level is `depth`. Pretty text puts the
/// close of a container with children on a new line.
fn write_close(
  buffer : StringBuilder,
  kind : @ion.IonType,
  empty : Bool,
  depth : Int32,
  pretty : Bool,
) -> Unit {
  if pretty && !empty {
    buffer.write_string("\n")
    write_indent(buffer, depth)
  }
  buffer.write_string(close_text(kind))
}

///|
/// Render `value` with no recursion: the containers that the writer is inside
/// are on a heap stack.
fn write_deep(
  buffer : StringBuilder,
  value : @ion.IonValue,
  depth : Int32,
  pretty : Bool,
  in_sexp : Bool,
) -> Unit raise @ion.IonError {
  let open : Array[TextFrame] = []
  write_start(buffer, open, value, in_sexp)
  while open.last() is Some(frame) {
    let index = frame.next
    let (child, field) = match frame.value.kind() {
      List(items) | Sexp(items) if index < items.length() =>
        (items[index], None)
      Struct(fields) if index < fields.length() =>
        (fields[index].value(), Some(fields[index].name()))
      _ => {
        ignore(open.pop())
        // A container on `open` has children; `write_start` closes an empty
        // one at once.
        write_close(buffer, frame.kind, false, depth + open.length(), pretty)
        continue
      }
    }
    frame.next = index + 1
    let sexp = frame.kind == @ion.IonType::Sexp
    // The container's own indent level is one less than its children's.
    write_separator(buffer, index, sexp, depth + open.length() - 1, pretty)
    if field is Some(name) {
      write_symbol(buffer, name, false)
      buffer.write_string(": ")
    }
    write_start(buffer, open, child, sexp)
  }
}

///|
/// Write `value` up to its children: its annotations, then a whole scalar, or
/// an empty container, or the opening of a container, which goes on `open`.
/// `bare_operators` lets an operator symbol be written without quotes.
fn write_start(
  buffer : StringBuilder,
  open : Array[TextFrame],
  value : @ion.IonValue,
  bare_operators : Bool,
) -> Unit raise @ion.IonError {
  write_annotations(buffer, value)
  let kind = value.ion_type()
  let empty = match value.kind() {
    List(items) | Sexp(items) => items.is_empty()
    Struct(fields) => fields.is_empty()
    other => {
      write_scalar(buffer, other, bare_operators)
      return
    }
  }
  buffer.write_string(open_text(kind))
  if empty {
    buffer.write_string(close_text(kind))
  } else {
    open.push({ value, kind, next: 0, })
  }
}

///|
/// Write the annotations of `value`, each followed by `::`.
fn write_annotations(
  buffer : StringBuilder,
  value : @ion.IonValue,
) -> Unit raise @ion.IonError {
  for annotation in value.annotations() {
    write_symbol(buffer, annotation, false)
    buffer.write_string("::")
  }
}

///|
/// The text that opens a container of type `kind`.
fn open_text(kind : @ion.IonType) -> String {
  match kind {
    List => "["
    Sexp => "("
    _ => "{"
  }
}

///|
/// The text that closes a container of type `kind`.
fn close_text(kind : @ion.IonType) -> String {
  match kind {
    List => "]"
    Sexp => ")"
    _ => "}"
  }
}

///|
/// Render a value with no children. `bare_operators` lets an operator symbol
/// be written without quotes.
fn write_scalar(
  buffer : StringBuilder,
  kind : @ion.IonValueKind,
  bare_operators : Bool,
) -> Unit raise @ion.IonError {
  match kind {
    Null(@ion.IonType::Null) => buffer.write_string("null")
    Null(t) => buffer.write_string("null." + t.to_text())
    Bool(value) => buffer.write_string(if value { "true" } else { "false" })
    Int(value) => buffer.write_string(value.to_string())
    Float(value) => buffer.write_string(float_to_ion(value))
    Decimal(value) => buffer.write_string(value.to_ion_string())
    Timestamp(value) => buffer.write_string(value.to_ion_string())
    Symbol(token) => write_symbol(buffer, token, bare_operators)
    String(value) => {
      buffer.write_string("\"")
      buffer.write_string(escape_ion(value, '"'))
      buffer.write_string("\"")
    }
    Clob(bytes) => {
      buffer.write_string("{{ ")
      buffer.write_string(escape_clob(bytes))
      buffer.write_string(" }}")
    }
    Blob(bytes) => {
      buffer.write_string("{{ ")
      buffer.write_string(@base64.encode(bytes))
      buffer.write_string(" }}")
    }
    List(_) | Sexp(_) | Struct(_) => abort("write_start writes containers")
  }
}

///|
/// Render a float so that reading it back yields a float, not a decimal:
/// `nan`, `+inf`, `-inf`, or a value with an `e` exponent. Negative zero is
/// preserved as `-0e0`.
fn float_to_ion(value : Double) -> String {
  if value.is_nan() {
    "nan"
  } else if value.is_pos_inf() {
    "+inf"
  } else if value.is_neg_inf() {
    "-inf"
  } else if value == 0.0 && value.reinterpret_as_int64() < 0 {
    // Preserve negative zero, which `to_string` renders without its sign.
    "-0e0"
  } else {
    let text = value.to_string()
    if text.contains("e") || text.contains("E") {
      text
    } else {
      text + "e0"
    }
  }
}

///|
/// Whether `text` can be written as a bare (unquoted) Ion symbol: a leading
/// ASCII letter, `_`, or `$`, then letters, digits, `_`, or `$`, and not a
/// reserved keyword such as `null` or `true`.
fn is_bare_symbol(text : String) -> Bool {
  let mut first = true
  for c in text {
    if first {
      if !(c.is_ascii_alphabetic() || c == '_' || c == '$') {
        return false
      }
      first = false
    } else if !(c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      c == '_' ||
      c == '$') {
      return false
    }
  }
  !first && !is_reserved_symbol(text)
}

///|
/// Whether `text` is a reserved token that must be quoted to be read back as a
/// symbol: a reserved keyword such as `null` or `true`, a symbol-ID literal
/// such as `$1`, or a version marker such as `$ion_1_0`.
fn is_reserved_symbol(text : String) -> Bool {
  match text {
    "null" | "true" | "false" | "nan" => true
    _ =>
      if text.has_prefix("null.") {
        @ion.IonType::from_text(text[5:]) is Some(_)
      } else {
        is_symbol_id_literal(text) || is_version_marker_literal(text)
      }
  }
}

///|
/// Whether `text` is a bare S-expression operator: one or more operator
/// characters, and no `//` or `/*` inside. A comment start ends an operator
/// when it is read back, so such a symbol must be quoted to keep its text.
fn is_operator_symbol(text : String) -> Bool {
  if text.is_empty() {
    return false
  }
  for index in 0..<text.length() {
    let c = text[index]
    if !is_operator_char(c) {
      return false
    }
    if c == '/' &&
      index + 1 < text.length() &&
      (text[index + 1] == '/' || text[index + 1] == '*') {
      return false
    }
  }
  true
}

///|
/// Render a symbol as Ion text, quoting it only when necessary.
fn quote_symbol(text : String) -> String {
  if is_bare_symbol(text) {
    text
  } else {
    "'" + escape_ion(text, '\'') + "'"
  }
}

///|
/// The lowercase hexadecimal digits.
let hex_digits : Array[String] = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
]

///|
/// Two lowercase hexadecimal digits for a byte value.
fn hex_byte(value : Int32) -> String {
  hex_digits[(value >> 4) & 0xF] + hex_digits[value & 0xF]
}

///|
/// Escape the body of a quoted Ion string or symbol (without the surrounding
/// quotes). `quote` is `'"'` for strings and `'\''` for symbols.
fn escape_ion(text : String, quote : Char) -> String {
  let sb = StringBuilder()
  for c in text {
    let code = c.to_int()
    match code {
      0 => sb.write_string("\\0")
      7 => sb.write_string("\\a")
      8 => sb.write_string("\\b")
      9 => sb.write_string("\\t")
      10 => sb.write_string("\\n")
      11 => sb.write_string("\\v")
      12 => sb.write_string("\\f")
      13 => sb.write_string("\\r")
      92 => sb.write_string("\\\\")
      _ =>
        if c == quote {
          sb.write_string("\\")
          sb.write_char(c)
        } else if code < 0x20 {
          sb.write_string("\\x" + hex_byte(code))
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.to_string()
}

///|
/// Render a clob as a quoted Ion clob body. Only printable ASCII is written
/// literally; every other byte becomes a `\xHH` escape.
fn escape_clob(bytes : Bytes) -> String {
  let sb = StringBuilder()
  sb.write_string("\"")
  for byte in bytes.iter() {
    let value = byte.to_int()
    if value == 0x22 {
      sb.write_string("\\\"")
    } else if value == 0x5C {
      sb.write_string("\\\\")
    } else if value >= 0x20 && value <= 0x7E {
      sb.write_char(char_from_code(value))
    } else {
      sb.write_string("\\x" + hex_byte(value))
    }
  }
  sb.write_string("\"")
  sb.to_string()
}

///|
/// Render a symbol token. Known text is quoted as needed, and left bare when it
/// is an operator inside an S-expression; a token known only by ID is written as
/// `$id`, which reads back to the same token.
fn write_symbol(
  buffer : StringBuilder,
  token : @ion.SymbolToken,
  bare_operators : Bool,
) -> Unit raise @ion.IonError {
  match token.text() {
    Some(text) =>
      if bare_operators && is_operator_symbol(text) {
        buffer.write_string(text)
      } else {
        buffer.write_string(quote_symbol(text))
      }
    None =>
      match token.sid() {
        Some(sid) => buffer.write_string("$" + sid.to_string())
        None => raise @ion.IonError::DataModel("symbol has neither text nor ID")
      }
  }
}
