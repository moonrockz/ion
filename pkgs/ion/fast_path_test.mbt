// The walkers recurse while values are shallow and switch to an explicit
// stack below the shallow recursion threshold. These tests cross that boundary and
// check that both paths give the same, document-order results.

///|
/// A value `levels` levels deep. Each level is a struct whose field `a` holds
/// an annotated list of the level number and the next level, and whose field
/// `b` holds a string, so each level adds two containers.
fn layered(levels : Int32) -> @ion.IonValue {
  let mut value = @ion.IonValue::symbol("leaf")
  for level = levels - 1; level >= 0; level = level - 1 {
    value = @ion.IonValue::from_fields([
      @ion.Field::Field(
        "a",
        @ion.IonValue::list([@ion.IonValue::int(level), value]).with_annotation(
          @ion.SymbolToken::SymbolToken("tag"),
        ),
      ),
      @ion.Field::Field("b", @ion.IonValue::string("s")),
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
test "accept visits every value in document order past the shallow recursion threshold" {
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
test "fold visits every value in document order past the shallow recursion threshold" {
  for levels in crossing_levels {
    let value = layered(levels)
    assert_eq(value.fold([], trace_folder()), walk_trace(value))
  }
}

///|
test "fold stops at once when a callback stops past the shallow recursion threshold" {
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
test "fold skips the children of a container past the shallow recursion threshold" {
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

///|
test "equals compares every level past the shallow recursion threshold" {
  for levels in crossing_levels {
    let value = layered(levels)
    assert_true(value.equals(layered(levels)))
    assert_true(value.equals(@testkit.reverse_fields(value)))
    assert_true(!value.equals(layered(levels + 1)))
    // A changed scalar is found at every depth: index 0 is the outermost
    // level number, and the last index is the innermost symbol.
    let scalars = levels * 2 + 1
    for index in [0, scalars / 2, scalars - 2, scalars - 1] {
      assert_true(!value.equals(@testkit.change_one_leaf(value, index)))
    }
  }
}

///|
test "equals pairs repeated field names past the shallow recursion threshold" {
  // `{a: 1, a: 2}` against `{a: 2, a: 1}`: the first pairing by position
  // fails, and only another pairing shows that the structs are equal.
  let left = @ion.IonValue::from_fields([
    @ion.Field::Field("a", @ion.IonValue::int(1)),
    @ion.Field::Field("a", @ion.IonValue::int(2)),
  ])
  let right = @ion.IonValue::from_fields([
    @ion.Field::Field("a", @ion.IonValue::int(2)),
    @ion.Field::Field("a", @ion.IonValue::int(1)),
  ])
  let other = @ion.IonValue::from_fields([
    @ion.Field::Field("a", @ion.IonValue::int(2)),
    @ion.Field::Field("a", @ion.IonValue::int(3)),
  ])
  for depth in [0, 127, 128, 129, 300] {
    let wrap = (value : @ion.IonValue) => {
      @testkit.deep_value(List, depth, leaf=value)
    }
    assert_true(wrap(left).equals(wrap(right)))
    assert_true(!wrap(left).equals(wrap(other)))
  }
}

///|
/// `leaf` inside `depth` lists.
fn in_lists(depth : Int32, leaf : @ion.IonValue) -> @ion.IonValue {
  @testkit.deep_value(List, depth, leaf~)
}

///|
/// The value inside `depth` lists, found with a loop.
fn under_lists(value : @ion.IonValue, depth : Int32) -> @ion.IonValue {
  let mut current = value
  for _ in 0..<depth {
    guard current.kind() is List([item]) else { abort("expected a list") }
    current = item
  }
  current
}

///|
test "symbol walks find and resolve IDs past the shallow recursion threshold" {
  let sid = @ion.SymbolToken::from_sid
  // `imports::{name: version}` with every token known only by its ID.
  let leaf = @ion.IonValue::from_fields([
    @ion.Field::from_token(sid(4), @ion.IonValue::symbol_token(sid(5))),
  ]).with_annotation(sid(6))
  for depth in [0, 127, 128, 129, 300] {
    let value = in_lists(depth, leaf)
    assert_eq(@ion.highest_symbol_id([value]), 6)
    let resolved = under_lists(@ion.SymbolTable::system().resolve(value), depth)
    inspect(@text.write_ion(resolved), content="imports::{name: version}")
  }
}

///|
test "resolve names the first failing ID in document order across the shallow recursion threshold" {
  let sid = @ion.SymbolToken::from_sid
  let symbol = (id : Int32) => @ion.IonValue::symbol_token(sid(id))
  // The first failing ID is deep, and a later one is shallow.
  inspect(
    resolve_error(@ion.IonValue::list([in_lists(300, symbol(20)), symbol(30)])),
    content="symbol ID $20 is beyond the symbol table, whose largest ID is 9",
  )
  // The first failing ID is shallow, and a later one is deep.
  inspect(
    resolve_error(@ion.IonValue::list([symbol(30), in_lists(300, symbol(20))])),
    content="symbol ID $30 is beyond the symbol table, whose largest ID is 9",
  )
  // Below the limit, a field name comes before its value's annotations.
  let field_first = @ion.IonValue::from_fields([
    @ion.Field::from_token(sid(20), symbol(30).with_annotation(sid(40))),
  ])
  inspect(
    resolve_error(in_lists(300, field_first)),
    content="symbol ID $20 is beyond the symbol table, whose largest ID is 9",
  )
}

///|
test "for_values interns symbols in document order past the shallow recursion threshold" {
  // Level i is `{f<i>: t<i>::[s<i>, <level i + 1>]}`: two containers a level.
  let levels = 100
  let mut value = @ion.IonValue::symbol("leaf")
  for level = levels - 1; level >= 0; level = level - 1 {
    let list = @ion.IonValue::list([@ion.IonValue::symbol("s\{level}"), value]).with_annotation(
      @ion.SymbolToken::SymbolToken("t\{level}"),
    )
    value = @ion.IonValue::from_fields([@ion.Field::Field("f\{level}", list)])
  }
  let table = @ion.SymbolTable::for_values([value])
  for level in 0..<levels {
    assert_eq(table.find("f\{level}"), Some(10 + level * 3))
    assert_eq(table.find("t\{level}"), Some(11 + level * 3))
    assert_eq(table.find("s\{level}"), Some(12 + level * 3))
  }
  assert_eq(table.find("leaf"), Some(10 + levels * 3))
}

///|
test "localize_for_text rewrites imported symbols past the shallow recursion threshold" {
  let shared = @ion.SymbolToken::from_import(10, "shared", 1, 1)
  let leaf = @ion.IonValue::from_fields([
    @ion.Field::from_token(shared, @ion.IonValue::symbol_token(shared)),
  ])
  for depth in [0, 127, 128, 129, 300] {
    let value = in_lists(depth, leaf)
    let table = @ion.SymbolTable::for_values([value])
    let localized = under_lists(table.localize_for_text(value), depth)
    guard localized.kind() is Struct([field]) else { fail("expected a struct") }
    assert_eq(field.name().sid(), Some(10))
    assert_true(
      field.value().kind() is Symbol(token) && token.sid() == Some(10),
    )
  }
}

///|
test "resolve rewrites a field name even when its value has no IDs" {
  let sid = @ion.SymbolToken::from_sid
  let value = @ion.IonValue::from_fields([
    @ion.Field::from_token(sid(4), @ion.IonValue::int(1)),
  ])
  inspect(
    @text.write_ion(@ion.SymbolTable::system().resolve(value)),
    content="{name: 1}",
  )
}

///|
test "resolve keeps the annotations of a container whose children change" {
  let sid = @ion.SymbolToken::from_sid
  let value = @ion.IonValue::list([@ion.IonValue::symbol_token(sid(5))]).with_annotation(
    @ion.SymbolToken::SymbolToken("a"),
  )
  inspect(
    @text.write_ion(@ion.SymbolTable::system().resolve(value)),
    content="a::[version]",
  )
}
