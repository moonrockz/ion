// Converting Ion values to JSON.
//
// JSON's data model is a strict subset of Ion's, so this direction is lossy.
// It follows the Ion cookbook's documented "Down-converting to JSON" process:
//
//   1. a null of any type becomes JSON `null`;
//   2. integers become JSON numbers with their precision preserved (the exact
//      decimal spelling is carried in the number's `repr`);
//   3. floats become JSON numbers, except `nan` and `+-inf`, which become JSON
//      `null`;
//   4. decimals become JSON numbers with their precision preserved;
//   5. timestamps become JSON strings (their Ion text);
//   6. symbols become JSON strings;
//   7. strings become JSON strings;
//   8. clobs become JSON strings: bytes `0x20`..`0x7e` are emitted as the
//      characters they name, and every other byte as the code point `U+00XX`
//      (for example `0x7f` becomes `U+007f`, written `\u007f` in JSON);
//   9. blobs become Base64 JSON strings;
//  10. structs become JSON objects, with every field name quoted;
//  11. lists and s-expressions become JSON arrays;
//  12. annotations are suppressed.
//
// Absence is never a sentinel: a symbol — or a struct field name — known only
// by its symbol ID has no text, so converting it raises
// `IonError::Unsupported` rather than inventing an empty string. A struct with
// repeated field names folds each repetition onto the last, since a JSON
// object cannot carry the duplicates.

///|
/// How many levels of containers `to_json` converts with
/// recursion before switching to an explicit stack. Recursion is the
/// fastest way to convert a value; below this depth the conversions switch to
/// a stack of open containers, so the call stack stays small at any depth.
let shallow_depth : Int32 = @work.SHALLOW_DEPTH

///|
/// Convert an Ion value to a core `Json` value following the cookbook's
/// down-conversion rules (see the module comment). Any nesting depth works.
///
/// Raises [`@core.IonError::Unsupported`] when a symbol or struct field name
/// is known only by symbol ID, so it has no text to emit: for the first such
/// symbol in document order. Repeated field names fold onto the last
/// occurrence, because a JSON object cannot hold duplicates.
pub fn to_json(value : @core.IonValue) -> Json raise @core.IonError {
  json_shallow(value, shallow_depth)
}

///|
/// Convert `value` with recursion while `levels` is above zero, then with
/// `json_deep`.
fn json_shallow(
  value : @core.IonValue,
  levels : Int32,
) -> Json raise @core.IonError {
  match value.kind() {
    @core.IonValueKind::List(items) | @core.IonValueKind::Sexp(items) if levels >
      0 => {
      let elements : Array[Json] = Array::new(capacity=items.length())
      for item in items {
        elements.push(json_shallow(item, levels - 1))
      }
      Json::array(elements)
    }
    @core.IonValueKind::Struct(fields) if levels > 0 => {
      let members : Map[String, Json] = Map::new(capacity=fields.length())
      for field in fields {
        let name = symbol_text(field.name())
        members.set(name, json_shallow(field.value(), levels - 1))
      }
      Json::object(members)
    }
    @core.IonValueKind::List(_)
    | @core.IonValueKind::Sexp(_)
    | @core.IonValueKind::Struct(_) => json_deep(value)
    kind => scalar_to_json(kind)
  }
}

///|
/// A container that `json_deep` is filling: its Ion children, and the JSON
/// array or object that receives their conversions.
priv enum JsonContainer {
  Elements(Array[@core.IonValue], Array[Json])
  Members(Array[@core.Field], Map[String, Json])
}

///|
/// Convert `value` top-down with a stack of open containers, not recursion.
/// Each container's JSON is added to its parent when the walk enters it, and
/// filled while the walk is inside it.
fn json_deep(value : @core.IonValue) -> Json raise @core.IonError {
  let open : Array[JsonContainer] = []
  // The index of the next child of each open container.
  let next : Array[Int32] = []
  let root = json_start(value, open, next)
  while open.last() is Some(container) {
    let top = next.length() - 1
    let index = next[top]
    match container {
      Elements(items, elements) if index < items.length() => {
        next[top] = index + 1
        elements.push(json_start(items[index], open, next))
      }
      Members(fields, members) if index < fields.length() => {
        next[top] = index + 1
        let field = fields[index]
        let name = symbol_text(field.name())
        members.set(name, json_start(field.value(), open, next))
      }
      _ => {
        ignore(open.pop())
        ignore(next.pop())
      }
    }
  }
  root
}

///|
/// The JSON of `value`. A container's JSON is empty here: it is pushed onto
/// `open`, and `json_deep` fills it in place.
fn json_start(
  value : @core.IonValue,
  open : Array[JsonContainer],
  next : Array[Int32],
) -> Json raise @core.IonError {
  match value.kind() {
    @core.IonValueKind::List(items) | @core.IonValueKind::Sexp(items) => {
      let elements : Array[Json] = Array::new(capacity=items.length())
      open.push(Elements(items, elements))
      next.push(0)
      Json::array(elements)
    }
    @core.IonValueKind::Struct(fields) => {
      let members : Map[String, Json] = Map::new(capacity=fields.length())
      open.push(Members(fields, members))
      next.push(0)
      Json::object(members)
    }
    kind => scalar_to_json(kind)
  }
}

///|
/// The JSON of a value with no children.
fn scalar_to_json(kind : @core.IonValueKind) -> Json raise @core.IonError {
  match kind {
    @core.IonValueKind::Null(_) => Json::null()
    @core.IonValueKind::Bool(flag) => Json::boolean(flag)
    @core.IonValueKind::Int(number) => int_to_json(number)
    @core.IonValueKind::Float(number) => float_to_json(number)
    @core.IonValueKind::Decimal(decimal) =>
      number_from_text(decimal_to_number_text(decimal))
    @core.IonValueKind::Timestamp(timestamp) =>
      Json::string(timestamp.to_ion_string())
    @core.IonValueKind::Symbol(token) => Json::string(symbol_text(token))
    @core.IonValueKind::String(text) => Json::string(text)
    @core.IonValueKind::Clob(bytes) => Json::string(clob_to_string(bytes))
    @core.IonValueKind::Blob(bytes) => Json::string(@base64.encode(bytes[:]))
    @core.IonValueKind::List(_)
    | @core.IonValueKind::Sexp(_)
    | @core.IonValueKind::Struct(_) =>
      abort("json_shallow and json_start convert containers")
  }
}

///|
/// The text of a symbol token, resolving the Ion 1.0 system symbols by ID.
///
/// Raises [`@core.IonError::Unsupported`] when the text is unknown.
fn symbol_text(token : @core.SymbolToken) -> String raise @core.IonError {
  match token.text() {
    Some(text) => text
    None if token.import_location is Some(_) =>
      raise @core.IonError::Unsupported(
        "an imported symbol with unknown text cannot be converted to JSON",
      )
    None =>
      match token.sid() {
        Some(sid) =>
          match @core.system_symbol_text(sid) {
            Some(text) => text
            None =>
              raise @core.IonError::Unsupported(
                "a symbol known only by symbol ID \{sid} has no text to convert to JSON",
              )
          }
        None =>
          raise @core.IonError::Unsupported(
            "a symbol with neither text nor symbol ID cannot be converted to JSON",
          )
      }
  }
}

///|
/// Convert an Ion `int` to a JSON number, keeping every digit.
fn int_to_json(value : @bigint.BigInt) -> Json {
  number_from_text(value.to_string())
}

///|
/// Convert an Ion `float` to a JSON number, mapping the non-finite values to
/// JSON `null` as the cookbook requires.
fn float_to_json(value : Double) -> Json {
  if value.is_nan() || value.is_inf() {
    Json::null()
  } else {
    Json::number(value)
  }
}

///|
/// Build a JSON number from its exact decimal spelling.
///
/// The `Double` is the best approximation of `text`; when it does not render
/// back to `text`, the spelling is kept in `repr` so the number prints
/// verbatim.
fn number_from_text(text : String) -> Json {
  let value = @string.parse_double(text) catch { _ => 0.0 }
  let plain = Json::number(value)
  if plain.stringify() == text {
    plain
  } else {
    Json::number(value, repr=text)
  }
}

///|
/// Render a clob's bytes as the JSON string the cookbook describes: ASCII for
/// `0x20`..`0x7e` and `U+00XX` for every other byte, which is a Latin-1
/// decoding of the bytes.
fn clob_to_string(bytes : Bytes) -> String {
  let builder = StringBuilder()
  for index in 0..<bytes.length() {
    // A byte is always a valid Unicode scalar value, so `to_char` is total
    // here and the failing branch is unreachable.
    if bytes[index].to_int().to_char() is Some(character) {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
/// Render a decimal as a JSON number literal, preserving its exact scale.
///
/// A decimal is `coefficient * 10^exponent`; JSON has no `d` exponent marker,
/// so the point is placed explicitly. `0.` stays `0`, `-0.` stays `-0`,
/// `1.50` stays `1.50`, and `0d5` keeps its scale as `0e5`.
fn decimal_to_number_text(value : @core.Decimal) -> String {
  let coefficient = value.coefficient()
  let magnitude = if coefficient.compare_int(0) < 0 {
    coefficient.neg()
  } else {
    coefficient
  }
  let digits = magnitude.to_string()
  let exponent = value.exponent()
  let builder = StringBuilder()
  if value.is_negative() {
    builder.write_string("-")
  }
  if exponent >= 0 {
    if magnitude.is_zero() {
      // A zero coefficient has no digits to extend, so `0dN` keeps its scale
      // as a JSON exponent, which is still a valid JSON number.
      builder.write_string("0")
      if exponent > 0 {
        builder.write_string("e")
        builder.write_string(exponent.to_string())
      }
    } else {
      builder.write_string(digits)
      for _ in 0..<exponent {
        builder.write_string("0")
      }
    }
  } else {
    let point = digits.length() + exponent
    if point > 0 {
      builder.write_view(digits[:point])
      builder.write_string(".")
      builder.write_view(digits[point:])
    } else {
      builder.write_string("0.")
      for _ in 0..<-point {
        builder.write_string("0")
      }
      builder.write_string(digits)
    }
  }
  builder.to_string()
}
