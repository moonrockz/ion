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
/// Convert a core `Json` value to an Ion value. Object fields keep their
/// order, and any nesting depth works.
///
/// See the module comment for the mapping, especially for numbers.
pub impl ToIon for Json with fn to_ion(self : Json) -> IonValue {
  ion_shallow(self, @work.SHALLOW_DEPTH)
}

///|
/// Convert `json` with recursion while `levels` is above zero, then with
/// `ion_deep`. Recursion is the fastest way to convert a small value; the
/// limit keeps the call stack small at any depth.
fn ion_shallow(json : Json, levels : Int32) -> IonValue {
  match json {
    Json::Array(elements) if levels > 0 => {
      let items : Array[IonValue] = Array(capacity=elements.length())
      for element in elements {
        items.push(ion_shallow(element, levels - 1))
      }
      IonValue::list(items)
    }
    Json::Object(entries) if levels > 0 => {
      let fields : Array[Field] = Array(capacity=entries.length())
      for name, item in entries {
        fields.push(Field::Field(name, ion_shallow(item, levels - 1)))
      }
      IonValue::from_fields(fields)
    }
    Json::Array(_) | Json::Object(_) => ion_deep(json)
    scalar => scalar_to_ion(scalar)
  }
}

///|
/// A container that `ion_deep` is filling: its JSON children, and the Ion
/// elements or fields that receive their conversions. An object's members are
/// copied into an array so that they can be taken by index, in order.
priv enum IonContainer {
  Items(Array[Json], Array[IonValue])
  Fields(Array[(String, Json)], Array[Field])
}

///|
/// Convert `json` top-down with a stack of open containers, not recursion.
/// Each container's Ion value is added to its parent when the walk enters it,
/// and filled while the walk is inside it.
fn ion_deep(json : Json) -> IonValue {
  let open : Array[IonContainer] = []
  // The index of the next child of each open container.
  let next : Array[Int32] = []
  let root = ion_start(json, open, next)
  while open.last() is Some(container) {
    let top = next.length() - 1
    let index = next[top]
    match container {
      Items(elements, items) if index < elements.length() => {
        next[top] = index + 1
        items.push(ion_start(elements[index], open, next))
      }
      Fields(members, fields) if index < members.length() => {
        next[top] = index + 1
        let (name, item) = members[index]
        fields.push(Field::Field(name, ion_start(item, open, next)))
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
/// The Ion value of `json`. A container's value is empty here: it is pushed
/// onto `open`, and `ion_deep` fills it in place.
fn ion_start(
  json : Json,
  open : Array[IonContainer],
  next : Array[Int32],
) -> IonValue {
  match json {
    Json::Array(elements) => {
      let items : Array[IonValue] = Array(capacity=elements.length())
      open.push(Items(elements, items))
      next.push(0)
      IonValue::list(items)
    }
    Json::Object(entries) => {
      let members : Array[(String, Json)] = Array(capacity=entries.length())
      for name, item in entries {
        members.push((name, item))
      }
      let fields : Array[Field] = Array(capacity=entries.length())
      open.push(Fields(members, fields))
      next.push(0)
      IonValue::from_fields(fields)
    }
    scalar => scalar_to_ion(scalar)
  }
}

///|
/// The Ion value of a JSON value with no children.
fn scalar_to_ion(json : Json) -> IonValue {
  match json {
    Json::Null => IonValue::untyped_null()
    Json::True => IonValue::bool(true)
    Json::False => IonValue::bool(false)
    Json::String(text) => IonValue::string(text)
    Json::Number(value, repr~) =>
      number_text_to_ion(
        match repr {
          Some(text) => text
          None => shortest_spelling(value)
        },
        value,
      )
    Json::Array(_) | Json::Object(_) =>
      abort("ion_shallow and ion_start convert containers")
  }
}

///|
/// Convert a JSON number from a decimal spelling.
fn number_text_to_ion(text : String, fallback : Double) -> IonValue {
  if has_exponent(text) {
    let value = @string.parse_double(text) catch { _ => fallback }
    return IonValue::float(value)
  }
  if text.contains(".") {
    let parsed = Decimal::parse(text) catch {
      _ => return double_to_ion(fallback)
    }
    return IonValue::decimal(parsed)
  }
  let parsed = @string.parse_bigint(text) catch {
    _ => return double_to_ion(fallback)
  }
  IonValue::big_int(parsed)
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
fn double_to_ion(value : Double) -> IonValue {
  if is_integral_64(value) {
    IonValue::big_int(@bigint.BigInt::from_int64(value.to_int64()))
  } else {
    IonValue::float(value)
  }
}

///|
/// Whether a double is a finite integer that fits in an `Int64`.
fn is_integral_64(value : Double) -> Bool {
  !value.is_nan() &&
  !value.is_inf() &&
  value == value.floor() &&
  value >= -9.223372036854776e18 &&
  value < 9.223372036854776e18
}
