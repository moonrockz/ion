// Property-based tests for the JSON <-> Ion conversions.
//
// JSON -> Ion is total, and the trip JSON -> Ion -> JSON must return the same
// JSON value. Numbers are compared by their double (Ion carries an exact
// spelling in `repr` separately), and objects are compared as unordered maps.

///|
/// Structural equality for `Json`, ignoring the non-semantic `repr` spelling
/// of a number and the order of an object's keys.
fn json_equal(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Json::Null, Json::Null) => true
    (Json::True, Json::True) => true
    (Json::False, Json::False) => true
    (Json::Number(a, ..), Json::Number(b, ..)) => a == b
    (Json::String(a), Json::String(b)) => a == b
    (Json::Array(a), Json::Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      let mut same = true
      for index in 0..<a.length() {
        if !json_equal(a[index], b[index]) {
          same = false
        }
      }
      same
    }
    (Json::Object(a), Json::Object(b)) => {
      if a.length() != b.length() {
        return false
      }
      let mut same = true
      for key, value in a {
        match b.get(key) {
          Some(other) => if !json_equal(value, other) { same = false }
          None => same = false
        }
      }
      same
    }
    _ => false
  }
}

///|
/// A JSON value assembled from a small seed, covering every JSON kind.
fn sample_json(seed : (Int, Int, String, Bool)) -> Json {
  Json::array([
    Json::number(seed.0.to_double()),
    Json::number(seed.1.to_double() / 4.0),
    Json::string(seed.2),
    Json::boolean(seed.3),
    Json::null(),
    Json::object({ "nested": Json::array([Json::number(seed.0.to_double())]) }),
  ])
}

///|
test "every Ion integer converts to its exact JSON spelling" {
  @quickcheck.check((n : BigInt) => {
    let json = @json.to_json(@core.IonValue::big_int(n)) catch {
      _ => return false
    }
    json.stringify() == n.to_string()
  })
}

///|
test "JSON survives a trip through Ion" {
  @quickcheck.check((seed : (Int, Int, String, Bool)) => {
    let original = sample_json(seed)
    let back = @json.to_json(@json.to_ion(original)) catch { _ => return false }
    json_equal(back, original)
  })
}

///|
test "a symbol becomes its text as a JSON string" {
  @quickcheck.check((s : String) => {
    let json = @json.to_json(@core.IonValue::symbol(s)) catch {
      _ => return false
    }
    json_equal(json, Json::string(s))
  })
}

///|
test "a clob's bytes become the matching Latin-1 code points" {
  @quickcheck.check((bytes : Bytes) => {
    let json = @json.to_json(@core.IonValue::clob(bytes)) catch {
      _ => return false
    }
    guard json is Json::String(text) else { return false }
    if text.char_length() != bytes.length() {
      return false
    }
    let mut same = true
    for index in 0..<bytes.length() {
      match text.get_char(index) {
        Some(character) =>
          if character.to_int() != bytes[index].to_int() {
            same = false
          }
        None => same = false
      }
    }
    same
  })
}

///|
test "a decimal renders as a valid JSON number" {
  @quickcheck.check((pair : (BigInt, Int)) => {
    let decimal = @core.Decimal::new(pair.0, pair.1 % 50)
    let json = @json.to_json(@core.IonValue::decimal(decimal)) catch {
      _ => return false
    }
    guard json is Json::Number(_, ..) else { return false }
    let text = json.stringify()
    // Ion's `d` exponent marker never survives, and the text parses as JSON.
    if text.contains("d") || text.contains("D") {
      return false
    }
    ignore(@cjson.parse(text) catch { _ => return false })
    true
  })
}
