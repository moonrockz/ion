// A depth-first walk over a value with no recursion, for the event emitters.

///|
/// A container that `traverse` is inside, and the index of its next child.
priv struct TraverseFrame {
  value : @ion.IonValue
  mut next : Int32
}

///|
/// Visit `value` and every value inside it in document order, with no
/// recursion: the containers are on a heap stack. `visit` gets each value
/// with its struct field name; `leave` gets each list, S-expression and struct
/// after its children. This costs less than `@ion.ValueWalker`, which
/// allocates an event for each value.
fn traverse(
  value : @ion.IonValue,
  visit : (@ion.IonValue, @ion.SymbolToken?) -> Unit,
  leave : (@ion.IonValue) -> Unit,
) -> Unit {
  let open : Array[TraverseFrame] = []
  visit(value, None)
  if value.kind() is (List(_) | Sexp(_) | Struct(_)) {
    open.push({ value, next: 0, })
  }
  while open.last() is Some(frame) {
    let index = frame.next
    let (child, field) = match frame.value.kind() {
      List(items) | Sexp(items) if index < items.length() =>
        (items[index], None)
      Struct(fields) if index < fields.length() =>
        (fields[index].value(), Some(fields[index].name()))
      _ => {
        ignore(open.pop())
        leave(frame.value)
        continue
      }
    }
    frame.next = index + 1
    visit(child, field)
    if child.kind() is (List(_) | Sexp(_) | Struct(_)) {
      open.push({ value: child, next: 0, })
    }
  }
}
