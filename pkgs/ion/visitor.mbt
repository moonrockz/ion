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
/// (struct field names precede their values).
pub fn IonValue::accept(self : IonValue, visitor : &IonVisitor) -> Unit {
  visitor.visit_value(self)
  for annotation in self.annotations() {
    visitor.visit_annotation(annotation)
  }
  match self.kind() {
    IonValueKind::List(items) => {
      visitor.visit_list(items)
      for item in items {
        item.accept(visitor)
      }
    }
    IonValueKind::Sexp(items) => {
      visitor.visit_sexp(items)
      for item in items {
        item.accept(visitor)
      }
    }
    IonValueKind::Struct(fields) => {
      visitor.visit_struct(fields)
      for field in fields {
        visitor.visit_field_name(field.name())
        field.value().accept(visitor)
      }
    }
    _ => ()
  }
}

///|
/// Accept `visitor` on every value of a datagram, in order.
pub fn accept_values(values : Array[IonValue], visitor : &IonVisitor) -> Unit {
  for value in values {
    value.accept(visitor)
  }
}
