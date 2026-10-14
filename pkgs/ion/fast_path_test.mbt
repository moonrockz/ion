// The walkers recurse while values are shallow and switch to an explicit
// stack below the readers' nesting limit. These tests cross that boundary and
// check that both paths give the same, document-order results.

///|
/// A value `levels` levels deep. Each level is a struct whose field `a` holds
/// an annotated list of the level number and the next level, and whose field
/// `b` holds a string, so each level adds two containers.
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
fn trace_label(value : @ion.IonValue) -> String {
  match value.kind() {
    Int(n) => "int:" + n.to_string()
    String(text) => "string:" + text
    Symbol(token) => "symbol:" + token.text().unwrap_or("?")
    _ => value.ion_type().to_text()
  }
}

///|
/// The visitor trace that a document-order walk gives, built from
/// `IonValue::walk`.
fn walk_trace(value : @ion.IonValue) -> Array[String] {
  let trace = []
  for event in value.walk() {
    match event {
      Scalar(current, field~) | Enter(current, field~) => {
        if field is Some(name) {
          trace.push("field:" + name.text().unwrap_or("?"))
        }
        trace.push(trace_label(current))
        for annotation in current.annotations() {
          trace.push("annotation:" + annotation.text().unwrap_or("?"))
        }
      }
      Exit(_, ..) => ()
    }
  }
  trace
}

///|
struct TraceAll {
  trace : Array[String]
}

///|
impl @ion.IonVisitor for TraceAll with fn visit_value(self, value) {
  self.trace.push(trace_label(value))
}

///|
impl @ion.IonVisitor for TraceAll with fn visit_annotation(self, token) {
  self.trace.push("annotation:" + token.text().unwrap_or("?"))
}

///|
impl @ion.IonVisitor for TraceAll with fn visit_field_name(self, token) {
  self.trace.push("field:" + token.text().unwrap_or("?"))
}

///|
test "accept visits every value in document order past the nesting limit" {
  for levels in crossing_levels {
    let value = layered(levels)
    let visitor : TraceAll = { trace: [], }
    value.accept(visitor)
    assert_eq(visitor.trace, walk_trace(value))
  }
}

///|
/// A folder that records the same trace as `TraceAll`.
fn trace_folder() -> @ion.IonFold[Array[String]] {
  {
    visit_value: @ion.continuing(fn(trace, value) {
      trace.push(trace_label(value))
      trace
    }),
    visit_annotation: @ion.continuing(fn(trace, token) {
      trace.push("annotation:" + token.text().unwrap_or("?"))
      trace
    }),
    visit_field_name: @ion.continuing(fn(trace, token) {
      trace.push("field:" + token.text().unwrap_or("?"))
      trace
    }),
  }
}

///|
test "fold visits every value in document order past the nesting limit" {
  for levels in crossing_levels {
    let value = layered(levels)
    assert_eq(value.fold([], trace_folder()), walk_trace(value))
  }
}

///|
test "fold stops at once when a callback stops past the nesting limit" {
  let value = layered(100)
  let expected = walk_trace(value)
  // Stop at the integer of each level, on both sides of the boundary.
  for level in [10, 63, 64, 65, 99] {
    let stop_at = "int:" + level.to_string()
    let folder = {
      ..trace_folder(),
      visit_value: fn(trace : Array[String], current) {
        trace.push(trace_label(current))
        if trace_label(current) == stop_at {
          @ion.FoldAction::Stop(trace)
        } else {
          Continue(trace)
        }
      },
    }
    let trace = value.fold([], folder)
    guard expected.search(stop_at) is Some(index) else { fail("no \{stop_at}") }
    assert_eq(trace, expected[:index + 1].to_owned())
  }
}

///|
test "fold skips the children of a container past the nesting limit" {
  let value = layered(100)
  // Skip the list of level 70: its integer and everything deeper are left
  // out, and the walk goes on with that level's field `b`.
  let folder = {
    ..trace_folder(),
    visit_value: fn(trace : Array[String], current) {
      trace.push(trace_label(current))
      match current.kind() {
        List(items) if items[0].kind() is Int(n) && n.to_string() == "70" =>
          @ion.FoldAction::SkipChildren(trace)
        _ => Continue(trace)
      }
    },
  }
  let trace = value.fold([], folder)
  let expected = walk_trace(value)
  guard expected.search("int:70") is Some(skipped) else { fail("no int:70") }
  // Level 70's `b` field and string, then the `b` fields of the 70 outer
  // levels, close the trace.
  let tail : Array[String] = []
  for _ in 0..<71 {
    tail.push("field:b")
    tail.push("string:s")
  }
  assert_eq(trace, expected[:skipped].to_owned() + tail)
}
