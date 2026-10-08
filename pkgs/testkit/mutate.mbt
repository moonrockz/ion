// Mutations of generated values for near-miss property tests. They recurse
// once per level, so use them only on generated values.

///|
/// A copy of `value` with one scalar replaced by a different scalar: the
/// scalar at position `index` in document order, wrapping around. A value
/// with no scalar (such as `[]`) gets an extra annotation instead. The result
/// never equals `value`.
pub fn change_one_leaf(value : @ion.IonValue, index : Int) -> @ion.IonValue {
  let count = count_scalars(value)
  if count == 0 {
    return value.with_annotation(@ion.SymbolToken::new("changed"))
  }
  let seen = Ref(0)
  rebuild(value, (index % count + count) % count, seen)
}

///|
fn count_scalars(value : @ion.IonValue) -> Int {
  match value.kind() {
    List(items) | Sexp(items) =>
      items.fold(init=0, (count, item) => count + count_scalars(item))
    Struct(fields) =>
      fields.fold(init=0, (count, field) => count + count_scalars(field.value()))
    _ => 1
  }
}

///|
fn rebuild(
  value : @ion.IonValue,
  target : Int,
  seen : Ref[Int],
) -> @ion.IonValue {
  let rebuilt = match value.kind() {
    List(items) =>
      @ion.IonValue::list(items.map(item => rebuild(item, target, seen)))
    Sexp(items) =>
      @ion.IonValue::sexp(items.map(item => rebuild(item, target, seen)))
    Struct(fields) =>
      @ion.IonValue::from_fields(
        fields.map(field => {
          @ion.Field::from_token(
            field.name(),
            rebuild(field.value(), target, seen),
          )
        }),
      )
    _ => {
      let position = seen.val
      seen.val += 1
      return if position == target { different(value) } else { value }
    }
  }
  rebuilt.with_annotations(value.annotations())
}

///|
/// A scalar that differs from `value` and keeps its annotations.
fn different(value : @ion.IonValue) -> @ion.IonValue {
  let replacement = match value.kind() {
    Int(n) => @ion.IonValue::big_int(n + BigInt::from_int(1))
    _ => @ion.IonValue::int(0)
  }
  replacement.with_annotations(value.annotations())
}

///|
/// A copy of `value` with the fields of every struct in reverse order. Struct
/// fields are unordered, so the result equals `value`.
pub fn reverse_fields(value : @ion.IonValue) -> @ion.IonValue {
  let rebuilt = match value.kind() {
    List(items) => @ion.IonValue::list(items.map(reverse_fields))
    Sexp(items) => @ion.IonValue::sexp(items.map(reverse_fields))
    Struct(fields) =>
      @ion.IonValue::from_fields(
        fields
        .map(field => {
          @ion.Field::from_token(field.name(), reverse_fields(field.value()))
        })
        .rev(),
      )
    _ => return value
  }
  rebuilt.with_annotations(value.annotations())
}
