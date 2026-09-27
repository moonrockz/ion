// Converting JSON to Ion.
//
// JSON's data model is a strict subset of Ion's, so this direction is
// faithful: every `Json` value maps to an Ion value that converts back to the
// same JSON. The mapping follows the Ion cookbook's "Migrating JSON data to
// Ion" rules:
//
//   * `null`, booleans, and strings map to the matching Ion type;
//   * an array maps to an Ion `list`;
//   * an object maps to an Ion `struct`, with each key a symbol field name;
//   * a number maps to an Ion `int`, `decimal`, or `float`.
//
// Numbers are the only interesting case, and they follow the cookbook's three
// rules: an integer spelling is an Ion `int`, a spelling with a decimal point
// but no exponent is an Ion `decimal`, and a spelling with an exponent is an
// Ion `float`.
//
// The spelling that decides is the one core kept in `repr`, or, when core
// dropped it, the number's shortest round-trip spelling. Core keeps `repr`
// only for an integer-spelled literal above 2^53 - 1, or for a literal that
// overflows a `Double` to infinity; a fractional or exponent-spelled literal
// that fits a `Double` is rounded to the nearest `Double` and its spelling is
// lost. So `1.50` and `0.1` arrive as bare doubles and become the Ion decimals
// `1.5` and `0.1`, while `1e2` becomes the Ion int `100` and `1e-7`, whose
// shortest spelling really does carry an exponent, becomes an Ion float.

///|
/// Convert a core `Json` value to an Ion value.
///
/// See the module comment for the mapping, especially for numbers.
pub fn to_ion(json : Json) -> @core.IonValue {
  match json {
    Json::Null => @core.IonValue::untyped_null()
    Json::True => @core.IonValue::bool(true)
    Json::False => @core.IonValue::bool(false)
    Json::String(text) => @core.IonValue::string(text)
    Json::Array(elements) =>
      @core.IonValue::list(elements.map(element => to_ion(element)))
    Json::Object(entries) => object_to_ion(entries)
    Json::Number(value, repr~) =>
      number_text_to_ion(
        match repr {
          Some(text) => text
          None => shortest_spelling(value)
        },
        value,
      )
  }
}

///|
/// Convert a JSON object to an Ion struct, preserving field order.
fn object_to_ion(entries : Map[String, Json]) -> @core.IonValue {
  let fields : Array[@core.Field] = []
  for name, value in entries {
    fields.push(@core.Field::new(name, to_ion(value)))
  }
  @core.IonValue::from_fields(fields)
}

///|
/// Convert a JSON number from a decimal spelling.
fn number_text_to_ion(text : String, fallback : Double) -> @core.IonValue {
  if has_exponent(text) {
    let value = @string.parse_double(text) catch { _ => fallback }
    return @core.IonValue::float(value)
  }
  if text.contains(".") {
    let parsed = @core.Decimal::parse(text) catch {
      _ => return double_to_ion(fallback)
    }
    return @core.IonValue::decimal(parsed)
  }
  let parsed = @string.parse_bigint(text) catch {
    _ => return double_to_ion(fallback)
  }
  @core.IonValue::big_int(parsed)
}

///|
/// Whether a JSON number spelling carries a base-10 exponent.
fn has_exponent(text : String) -> Bool {
  text.contains("e") || text.contains("E")
}

///|

///|
/// The shortest decimal spelling that round-trips to `value`, used when core
/// did not keep the source text in `repr`.
fn shortest_spelling(value : Double) -> String {
  Json::number(value).stringify()
}

///|
/// Convert a JSON number to Ion from the `Double` alone, the fallback for a
/// spelling that does not parse.
fn double_to_ion(value : Double) -> @core.IonValue {
  if is_integral_64(value) {
    @core.IonValue::big_int(@bigint.BigInt::from_int64(value.to_int64()))
  } else {
    @core.IonValue::float(value)
  }
}

///|
/// Whether a double is a finite integer that fits in an `Int64`.
fn is_integral_64(value : Double) -> Bool {
  !value.is_nan() &&
  !value.is_inf() &&
  value == value.floor() &&
  value.abs() < 9.223372036854776e18
}
