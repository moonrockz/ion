// The text writer, the event emitter and dispatch each have a recursive path
// for shallow values and a stack path for deep ones. Both paths must give the
// same output for every value, so these tests run both on generated values.

///|
fn generated_values() -> Array[@ion.IonValue] {
  @testkit.gen_value(max_depth=5, max_width=4).samples(count=200, size=8)
}

///|
test "the recursive and the stack text writer write the same text" {
  for value in generated_values() {
    for pretty in [false, true] {
      for in_sexp in [false, true] {
        for depth in [0, 3] {
          let shallow = StringBuilder()
          write_value(shallow, value, depth, pretty, in_sexp)
          let deep = StringBuilder()
          write_deep(deep, value, depth, pretty, in_sexp)
          assert_eq(shallow.to_string(), deep.to_string())
        }
      }
    }
  }
}

///|
/// Whether two event sequences are the same, scalars compared by value.
fn same_events(a : Array[IonEvent], b : Array[IonEvent]) -> Bool {
  a.length() == b.length() &&
  a
  .iter()
  .zip(b.iter())
  .all(pair => {
    match pair {
      (Scalar(x), Scalar(y)) => x.equals(y)
      (x, y) => x.to_text() == y.to_text()
    }
  })
}

///|
struct EventRecorder {
  events : Array[IonEvent]
}

///|
impl IonHandler for EventRecorder with fn on_annotation(self, token) {
  self.events.push(Annotation(token))
}

///|
impl IonHandler for EventRecorder with fn on_field_name(self, token) {
  self.events.push(FieldName(token))
}

///|
impl IonHandler for EventRecorder with fn on_list_start(self) {
  self.events.push(ListStart)
}

///|
impl IonHandler for EventRecorder with fn on_list_end(self) {
  self.events.push(ListEnd)
}

///|
impl IonHandler for EventRecorder with fn on_sexp_start(self) {
  self.events.push(SexpStart)
}

///|
impl IonHandler for EventRecorder with fn on_sexp_end(self) {
  self.events.push(SexpEnd)
}

///|
impl IonHandler for EventRecorder with fn on_struct_start(self) {
  self.events.push(StructStart)
}

///|
impl IonHandler for EventRecorder with fn on_struct_end(self) {
  self.events.push(StructEnd)
}

///|
impl IonHandler for EventRecorder with fn on_scalar(self, value) {
  self.events.push(Scalar(value))
}

///|
test "the recursive and the stack paths emit and dispatch the same events" {
  for value in generated_values() {
    let deep : Array[IonEvent] = []
    emit_deep(value, deep)
    let shallow : Array[IonEvent] = []
    emit_value(value, shallow)
    assert_true(same_events(shallow, deep))
    let dispatched : EventRecorder = { events: [], }
    dispatch_value(value, dispatched)
    let dispatched_deep : EventRecorder = { events: [], }
    dispatch_deep(value, dispatched_deep)
    assert_true(same_events(dispatched.events, deep))
    assert_true(same_events(dispatched_deep.events, deep))
  }
}
