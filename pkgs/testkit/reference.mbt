// Recursive reference oracles. They recurse once per nesting level, so use
// them only on generated values (depth 6 or less), never on deep values.

///|
/// `IonValue::equals` as it was before the stack-safe port, kept as the
/// oracle for property tests: annotations match in order by symbol
/// equivalence, all NaNs are equal, positive and negative zero are not,
/// decimals compare coefficient, exponent and negative zero, timestamps
/// compare their text, and struct fields compare as a multiset.
pub fn reference_equals(a : @ion.IonValue, b : @ion.IonValue) -> Bool {
  let left = a.annotations()
  let right = b.annotations()
  if left.length() != right.length() {
    return false
  }
  for index in 0..<left.length() {
    if !left[index].equivalent(right[index]) {
      return false
    }
  }
  match (a.kind(), b.kind()) {
    (Null(x), Null(y)) => x == y
    (Bool(x), Bool(y)) => x == y
    (Int(x), Int(y)) => x.equal(y)
    (Float(x), Float(y)) =>
      (x.is_nan() && y.is_nan()) ||
      x.reinterpret_as_uint64() == y.reinterpret_as_uint64()
    (Decimal(x), Decimal(y)) =>
      x.coefficient().equal(y.coefficient()) &&
      x.exponent() == y.exponent() &&
      x.is_negative_zero() == y.is_negative_zero()
    (Timestamp(x), Timestamp(y)) => x.to_ion_string() == y.to_ion_string()
    (Symbol(x), Symbol(y)) => x.equivalent(y)
    (String(x), String(y)) => x == y
    (Clob(x), Clob(y)) => x == y
    (Blob(x), Blob(y)) => x == y
    (List(x), List(y)) | (Sexp(x), Sexp(y)) => items_equal(x, y)
    (Struct(x), Struct(y)) => fields_equal(x, y)
    _ => false
  }
}

///|
fn items_equal(a : Array[@ion.IonValue], b : Array[@ion.IonValue]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for index in 0..<a.length() {
    if !reference_equals(a[index], b[index]) {
      return false
    }
  }
  true
}

///|
fn fields_equal(a : Array[@ion.Field], b : Array[@ion.Field]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let consumed = Array::make(b.length(), false)
  for field in a {
    let mut matched = false
    for index in 0..<b.length() {
      if !consumed[index] &&
        field.name().equivalent(b[index].name()) &&
        reference_equals(field.value(), b[index].value()) {
        consumed[index] = true
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}

///|
/// The number of values in `value`, itself and every nested value included.
pub fn count_values(value : @ion.IonValue) -> Int {
  match value.kind() {
    List(items) | Sexp(items) =>
      items.fold(init=1, (count, item) => count + count_values(item))
    Struct(fields) =>
      fields.fold(init=1, (count, field) => count + count_values(field.value()))
    _ => 1
  }
}
