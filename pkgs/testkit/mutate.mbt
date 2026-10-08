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

///|
/// Structural near misses of `value`, none of them equal to it: the first
/// list or S-expression whose first two children differ, with those two
/// swapped; the first list or S-expression changed to the other kind; the
/// first annotated value without its first annotation; and the first struct
/// with its first field renamed. A mutation with no place to apply is left
/// out.
pub fn near_misses(value : @ion.IonValue) -> Array[@ion.IonValue] {
  let misses : Array[@ion.IonValue] = []
  for
    mutation in [
      swap_first_items, flip_sequence_kind, drop_annotation, rename_field,
    ] {
    if rewrite_first(value, mutation) is Some(miss) {
      misses.push(miss)
    }
  }
  misses
}

///|
/// `value` with `mutation` applied to the first value, in document order,
/// where it applies; `None` when it applies nowhere.
fn rewrite_first(
  value : @ion.IonValue,
  mutation : (@ion.IonValue) -> @ion.IonValue?,
) -> @ion.IonValue? {
  if mutation(value) is Some(changed) {
    return Some(changed)
  }
  let annotations = value.annotations()
  match value.kind() {
    List(items) | Sexp(items) =>
      for index, item in items {
        if rewrite_first(item, mutation) is Some(changed) {
          let copy = items.copy()
          copy[index] = changed
          let rebuilt = if value.kind() is List(_) {
            @ion.IonValue::list(copy)
          } else {
            @ion.IonValue::sexp(copy)
          }
          return Some(rebuilt.with_annotations(annotations))
        }
      }
    Struct(fields) =>
      for index, field in fields {
        if rewrite_first(field.value(), mutation) is Some(changed) {
          let copy = fields.copy()
          copy[index] = @ion.Field::from_token(field.name(), changed)
          return Some(
            @ion.IonValue::from_fields(copy).with_annotations(annotations),
          )
        }
      }
    _ => ()
  }
  None
}

///|
fn swap_first_items(value : @ion.IonValue) -> @ion.IonValue? {
  match value.kind() {
    List([first, second, .. rest]) if !reference_equals(first, second) =>
      Some(
        @ion.IonValue::list([second, first, ..rest]).with_annotations(
          value.annotations(),
        ),
      )
    Sexp([first, second, .. rest]) if !reference_equals(first, second) =>
      Some(
        @ion.IonValue::sexp([second, first, ..rest]).with_annotations(
          value.annotations(),
        ),
      )
    _ => None
  }
}

///|
fn flip_sequence_kind(value : @ion.IonValue) -> @ion.IonValue? {
  match value.kind() {
    List(items) =>
      Some(@ion.IonValue::sexp(items).with_annotations(value.annotations()))
    Sexp(items) =>
      Some(@ion.IonValue::list(items).with_annotations(value.annotations()))
    _ => None
  }
}

///|
fn drop_annotation(value : @ion.IonValue) -> @ion.IonValue? {
  match value.annotations() {
    [_, .. rest] => Some(value.with_annotations(rest.to_owned()))
    [] => None
  }
}

///|
fn rename_field(value : @ion.IonValue) -> @ion.IonValue? {
  match value.kind() {
    Struct([first, .. rest]) => {
      let name = first.name().text().unwrap_or("") + "_"
      Some(
        @ion.IonValue::from_fields(
          [@ion.Field::new(name, first.value()), ..rest],
        ).with_annotations(value.annotations()),
      )
    }
    _ => None
  }
}
