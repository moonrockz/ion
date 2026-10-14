// A depth-first visitor over an Ion value tree.
//
// Ion has a single node type, `IonValue`, so `visit_value` is called for every
// value and callers match on `value.kind()`. The container callbacks and the
// annotation/field-name callbacks exist for the common cases. Every method has
// a default no-op implementation, so a visitor overrides only what it needs.

///|
/// A visitor for traversing an Ion value. Use [`IonValue::accept`] to begin
/// traversal.
pub(open) trait IonVisitor {
  /// Called for every value, before its annotations and children.
  fn visit_value(Self, IonValue) -> Unit = _
  /// Called for each annotation on a value, in order.
  fn visit_annotation(Self, SymbolToken) -> Unit = _
  /// Called for each struct field name, before its value.
  fn visit_field_name(Self, SymbolToken) -> Unit = _
  /// Called for a list value, before its elements.
  fn visit_list(Self, Array[IonValue]) -> Unit = _
  /// Called for an S-expression value, before its elements.
  fn visit_sexp(Self, Array[IonValue]) -> Unit = _
  /// Called for a struct value, before its fields.
  fn visit_struct(Self, Array[Field]) -> Unit = _
}

///|
impl IonVisitor with fn visit_value(_self, _value) {
  ()
}

///|
impl IonVisitor with fn visit_annotation(_self, _token) {
  ()
}

///|
impl IonVisitor with fn visit_field_name(_self, _token) {
  ()
}

///|
impl IonVisitor with fn visit_list(_self, _items) {
  ()
}

///|
impl IonVisitor with fn visit_sexp(_self, _items) {
  ()
}

///|
impl IonVisitor with fn visit_struct(_self, _fields) {
  ()
}

///|
/// Accept `visitor` on this value, traversing depth-first in document order:
/// the value, then its annotations, then — for containers — the child values
/// (struct field names precede their values). It works at any nesting depth.
pub fn IonValue::accept(self : IonValue, visitor : &IonVisitor) -> Unit {
  accept_shallow(self, visitor, MAX_NESTING_DEPTH)
}

///|
/// Accept `visitor` with recursion while `levels` is above zero. At zero
/// levels a container switches to `accept_deep`; a scalar stays here. Recursion is the fastest walk; the limit keeps the call
/// stack small at any depth.
fn accept_shallow(
  value : IonValue,
  visitor : &IonVisitor,
  levels : Int32,
) -> Unit {
  if levels == 0 && value.kind is (List(_) | Sexp(_) | Struct(_)) {
    return accept_deep(value, visitor)
  }
  visitor.visit_value(value)
  for annotation in value.annotations {
    visitor.visit_annotation(annotation)
  }
  match value.kind {
    List(items) => {
      visitor.visit_list(items)
      for item in items {
        accept_shallow(item, visitor, levels - 1)
      }
    }
    Sexp(items) => {
      visitor.visit_sexp(items)
      for item in items {
        accept_shallow(item, visitor, levels - 1)
      }
    }
    Struct(fields) => {
      visitor.visit_struct(fields)
      for field in fields {
        visitor.visit_field_name(field.name)
        accept_shallow(field.value, visitor, levels - 1)
      }
    }
    _ => ()
  }
}

///|
/// Accept `visitor` with no recursion, on a `ValueWalker`.
fn accept_deep(value : IonValue, visitor : &IonVisitor) -> Unit {
  let walker = value.walker()
  while true {
    match walker.step() {
      AtScalar | AtEnter => ()
      AtExit => continue
      Done => break
    }
    let value = walker.current
    let field = walker.current_field
    if field is Some(name) {
      visitor.visit_field_name(name)
    }
    visitor.visit_value(value)
    for annotation in value.annotations() {
      visitor.visit_annotation(annotation)
    }
    match value.kind() {
      List(items) => visitor.visit_list(items)
      Sexp(items) => visitor.visit_sexp(items)
      Struct(fields) => visitor.visit_struct(fields)
      _ => ()
    }
  }
}

///|
/// Accept `visitor` on every value of a datagram, in order.
pub fn accept_values(values : Array[IonValue], visitor : &IonVisitor) -> Unit {
  for value in values {
    value.accept(visitor)
  }
}
