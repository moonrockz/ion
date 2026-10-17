// The text writer, the event emitter and dispatch recurse while values are
// shallow and switch to an explicit stack below the shallow recursion threshold.
// These tests cross that boundary and check that both paths give the same
// output.

///|
/// A value `levels` levels deep. Level i is `{a: tag::[i, <level i + 1>],
/// b: "s"}`, so each level adds two containers. The innermost value is the
/// symbol `leaf`.
fn layered(levels : Int32) -> @ion.IonValue {
  let mut value = @ion.IonValue::symbol("leaf")
  for level = levels - 1; level >= 0; level = level - 1 {
    value = @ion.IonValue::from_fields([
      @ion.Field::new(
        "a",
        @ion.IonValue::list([@ion.IonValue::int(level), value]).with_annotation(
          @ion.SymbolToken::new("tag"),
        ),
      ),
      @ion.Field::new("b", @ion.IonValue::string("s")),
    ])
  }
  value
}

///|
/// The levels that put the boundary between the two paths just before, at
/// and just after each kind of container, and far past it.
let crossing_levels : Array[Int32] = [1, 63, 64, 65, 100]

///|
fn indent(depth : Int32) -> String {
  "  ".repeat(depth)
}

///|
test "write_ion writes every level past the shallow recursion threshold" {
  for levels in crossing_levels {
    let expected = StringBuilder()
    for level in 0..<levels {
      expected.write_string("{a: tag::[\{level}, ")
    }
    expected.write_string("leaf")
    for _ in 0..<levels {
      expected.write_string("], b: \"s\"}")
    }
    assert_eq(@text.write_ion(layered(levels)), expected.to_string())
  }
}

///|
test "write_ion_pretty indents every level past the shallow recursion threshold" {
  for levels in crossing_levels {
    let expected = StringBuilder()
    for level in 0..<levels {
      let depth = level * 2
      expected.write_string("{\n" + indent(depth + 1) + "a: tag::[\n")
      expected.write_string(
        indent(depth + 2) + "\{level},\n" + indent(depth + 2),
      )
    }
    expected.write_string("leaf")
    for level = levels - 1; level >= 0; level = level - 1 {
      let depth = level * 2
      expected.write_string("\n" + indent(depth + 1) + "],\n")
      expected.write_string(
        indent(depth + 1) + "b: \"s\"\n" + indent(depth) + "}",
      )
    }
    assert_eq(@text.write_ion_pretty(layered(levels)), expected.to_string())
  }
}

///|
test "write_ion writes an operator bare inside S-expressions past the shallow recursion threshold" {
  let plus = @ion.IonValue::symbol("+")
  for depth in [0, 127, 128, 129, 300] {
    let value = @testkit.deep_value(Sexp, depth, leaf=plus)
    let expected = if depth == 0 {
      "'+'"
    } else {
      "(".repeat(depth) + "+" + ")".repeat(depth)
    }
    assert_eq(@text.write_ion(value), expected)
  }
}

///|
/// The events of a layered value, built level by level.
fn layered_events(levels : Int32) -> Array[String] {
  let events = []
  for _ in 0..<levels {
    events.push_iter(
      [
        "StructStart", "FieldName(a)", "Annotation(tag)", "ListStart", "Scalar(int)",
      ].iter(),
    )
  }
  events.push("Scalar(symbol)")
  for _ in 0..<levels {
    events.push_iter(
      ["ListEnd", "FieldName(b)", "Scalar(string)", "StructEnd"].iter(),
    )
  }
  events
}

///|
test "events come in document order past the shallow recursion threshold" {
  for levels in crossing_levels {
    let events = @text.IonReader::from_value(layered(levels))
      .remaining()
      .map(event => event.to_text())
    assert_eq(
      events,
      ["DocumentStart", ..layered_events(levels), "DocumentEnd"],
    )
  }
}

///|
struct EventTrace {
  events : Array[String]
}

///|
impl @text.IonHandler for EventTrace with fn on_annotation(self, token) {
  self.events.push(@text.IonEvent::Annotation(token).to_text())
}

///|
impl @text.IonHandler for EventTrace with fn on_field_name(self, token) {
  self.events.push(@text.IonEvent::FieldName(token).to_text())
}

///|
impl @text.IonHandler for EventTrace with fn on_list_start(self) {
  self.events.push("ListStart")
}

///|
impl @text.IonHandler for EventTrace with fn on_list_end(self) {
  self.events.push("ListEnd")
}

///|
impl @text.IonHandler for EventTrace with fn on_sexp_start(self) {
  self.events.push("SexpStart")
}

///|
impl @text.IonHandler for EventTrace with fn on_sexp_end(self) {
  self.events.push("SexpEnd")
}

///|
impl @text.IonHandler for EventTrace with fn on_struct_start(self) {
  self.events.push("StructStart")
}

///|
impl @text.IonHandler for EventTrace with fn on_struct_end(self) {
  self.events.push("StructEnd")
}

///|
impl @text.IonHandler for EventTrace with fn on_scalar(self, value) {
  self.events.push(@text.IonEvent::Scalar(value).to_text())
}

///|
test "dispatch_value calls the handler in document order past the shallow recursion threshold" {
  for levels in crossing_levels {
    let trace : EventTrace = { events: [], }
    @text.dispatch_value(layered(levels), trace)
    assert_eq(trace.events, layered_events(levels))
  }
}

///|
struct ScalarAnnotations {
  counts : Array[Int32]
}

///|
impl @text.IonHandler for ScalarAnnotations with fn on_scalar(self, value) {
  self.counts.push(value.annotations().length())
}

///|
test "a scalar event carries no annotations, on both sides of the shallow recursion threshold" {
  for depth in [0, 127, 128, 129, 300] {
    let leaf = @ion.IonValue::int(1).with_annotation(@ion.SymbolToken::new("a"))
    let value = @testkit.deep_value(List, depth, leaf~)
    let handler : ScalarAnnotations = { counts: [], }
    @text.dispatch_value(value, handler)
    assert_eq(handler.counts, [0])
    let scalars = @text.IonReader::from_value(value)
      .remaining()
      .filter_map(event => {
        match event {
          Scalar(scalar) => Some(scalar.annotations().length())
          _ => None
        }
      })
    assert_eq(scalars, [0])
  }
}
