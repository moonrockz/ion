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
pub fn write_all(values : Array[@ion.IonValue]) -> String raise @ion.IonError {
  let buffer = StringBuilder()
  for index in 0..<values.length() {
    if index > 0 {
      buffer.write_string("\n")
    }
    write_value(buffer, values[index], 0, false, false)
  }
  buffer.to_string()
}

///|
/// Write a single value as indented Ion text.
pub fn write_ion_pretty(value : @ion.IonValue) -> String raise @ion.IonError {
  let buffer = StringBuilder()
  write_value(buffer, value, 0, true, false)
  buffer.to_string()
}

///|
/// Write a sequence of values as indented Ion text, one value per line.
pub fn write_all_pretty(
  values : Array[@ion.IonValue],
) -> String raise @ion.IonError {
  let buffer = StringBuilder()
  for index in 0..<values.length() {
    if index > 0 {
      buffer.write_string("\n")
    }
    write_value(buffer, values[index], 0, true, false)
  }
  buffer.to_string()
}

///|
/// The two-space indentation unit used by the pretty writer.
let indent_unit : String = "  "

///|
/// Append `depth` indent units.
fn write_indent(buffer : StringBuilder, depth : Int) -> Unit {
  for _ in 0..<depth {
    buffer.write_string(indent_unit)
  }
}

///|
/// Render one value into `buffer`.
fn write_value(
  buffer : StringBuilder,
  value : @ion.IonValue,
  depth : Int,
  pretty : Bool,
  in_sexp : Bool,
) -> Unit raise @ion.IonError {
  for annotation in value.annotations() {
    buffer.write_string(quote_symbol(annotation.require_text()))
    buffer.write_string("::")
  }
  match value.kind() {
    @ion.IonValueKind::Null(@ion.IonType::Null) => buffer.write_string("null")
    @ion.IonValueKind::Null(t) => buffer.write_string("null." + t.to_text())
    @ion.IonValueKind::Bool(value) =>
      buffer.write_string(if value { "true" } else { "false" })
    @ion.IonValueKind::Int(value) => buffer.write_string(value.to_string())
    @ion.IonValueKind::Float(value) => buffer.write_string(float_to_ion(value))
    @ion.IonValueKind::Decimal(value) =>
      buffer.write_string(value.to_ion_string())
    @ion.IonValueKind::Timestamp(value) =>
      buffer.write_string(value.to_ion_string())
    @ion.IonValueKind::Symbol(token) => {
      let text = token.require_text()
      if in_sexp && is_operator_symbol(text) {
        buffer.write_string(text)
      } else {
        buffer.write_string(quote_symbol(text))
      }
    }
    @ion.IonValueKind::String(value) => {
      buffer.write_string("\"")
      buffer.write_string(escape_ion(value, '"'))
      buffer.write_string("\"")
    }
    @ion.IonValueKind::Clob(bytes) => {
      buffer.write_string("{{ ")
      buffer.write_string(escape_clob(bytes))
      buffer.write_string(" }}")
    }
    @ion.IonValueKind::Blob(bytes) => {
      buffer.write_string("{{ ")
      buffer.write_string(@base64.encode(bytes))
      buffer.write_string(" }}")
    }
    @ion.IonValueKind::List(items) => write_list(buffer, items, depth, pretty)
    @ion.IonValueKind::Sexp(items) => write_sexp(buffer, items, depth, pretty)
    @ion.IonValueKind::Struct(fields) =>
      write_struct(buffer, fields, depth, pretty)
  }
}

///|
/// Render a list as `[a, b]` (or one element per line in pretty mode).
fn write_list(
  buffer : StringBuilder,
  items : Array[@ion.IonValue],
  depth : Int,
  pretty : Bool,
) -> Unit raise @ion.IonError {
  if items.is_empty() {
    buffer.write_string("[]")
    return
  }
  buffer.write_string("[")
  for index in 0..<items.length() {
    if pretty {
      buffer.write_string("\n")
      write_indent(buffer, depth + 1)
    } else if index > 0 {
      buffer.write_string(", ")
    }
    write_value(buffer, items[index], depth + 1, pretty, false)
    if pretty && index + 1 < items.length() {
      buffer.write_string(",")
    }
  }
  if pretty {
    buffer.write_string("\n")
    write_indent(buffer, depth)
  }
  buffer.write_string("]")
}

///|
/// Render an S-expression as `(a b)` (or one element per line in pretty mode).
fn write_sexp(
  buffer : StringBuilder,
  items : Array[@ion.IonValue],
  depth : Int,
  pretty : Bool,
) -> Unit raise @ion.IonError {
  if items.is_empty() {
    buffer.write_string("()")
    return
  }
  buffer.write_string("(")
  for index in 0..<items.length() {
    if pretty {
      buffer.write_string("\n")
      write_indent(buffer, depth + 1)
    } else if index > 0 {
      buffer.write_string(" ")
    }
    write_value(buffer, items[index], depth + 1, pretty, true)
  }
  if pretty {
    buffer.write_string("\n")
    write_indent(buffer, depth)
  }
  buffer.write_string(")")
}

///|
/// Render a struct as `{a: 1, b: 2}` (or one field per line in pretty mode).
fn write_struct(
  buffer : StringBuilder,
  fields : Array[@ion.Field],
  depth : Int,
  pretty : Bool,
) -> Unit raise @ion.IonError {
  if fields.is_empty() {
    buffer.write_string("{}")
    return
  }
  buffer.write_string("{")
  for index in 0..<fields.length() {
    if pretty {
      buffer.write_string("\n")
      write_indent(buffer, depth + 1)
    } else if index > 0 {
      buffer.write_string(", ")
    }
    let field = fields[index]
    buffer.write_string(quote_symbol(field.name().require_text()))
    buffer.write_string(": ")
    write_value(buffer, field.value(), depth + 1, pretty, false)
    if pretty && index + 1 < fields.length() {
      buffer.write_string(",")
    }
  }
  if pretty {
    buffer.write_string("\n")
    write_indent(buffer, depth)
  }
  buffer.write_string("}")
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
/// symbol.
fn is_reserved_symbol(text : String) -> Bool {
  match text {
    "null" | "true" | "false" | "nan" => true
    _ =>
      if text.has_prefix("null.") {
        @ion.IonType::from_text(text[5:]) is Some(_)
      } else {
        false
      }
  }
}

///|
/// Whether `text` is a bare S-expression operator: one or more operator
/// characters, and not the start of a comment.
fn is_operator_symbol(text : String) -> Bool {
  if text.is_empty() || text.has_prefix("//") || text.has_prefix("/*") {
    return false
  }
  for c in text {
    match c {
      '!'
      | '#'
      | '%'
      | '&'
      | '*'
      | '+'
      | '-'
      | '.'
      | '/'
      | ';'
      | '<'
      | '='
      | '>'
      | '?'
      | '@'
      | '^'
      | '`'
      | '|'
      | '~' => ()
      _ => return false
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
fn hex_byte(value : Int) -> String {
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
