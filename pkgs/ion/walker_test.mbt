// The traversal engine: a depth-first walk with an explicit stack, as
// Enter, Scalar and Exit events in document order.

///|
/// A short label for an event: its kind, the value's type, its field name and
/// its annotation count.
fn label(event : @ion.WalkEvent) -> String {
  let (kind, value, field) = match event {
    Scalar(value, field~) => ("scalar", value, field)
    Enter(value, field~) => ("enter", value, field)
    Exit(value, field~) => ("exit", value, field)
  }
  let name = match field {
    Some(token) => " " + token.text().unwrap_or("$")
    None => ""
  }
  let annotations = if value.has_annotations() {
    " @\{value.annotations().length()}"
  } else {
    ""
  }
  kind + " " + value.ion_type().to_text() + name + annotations
}

///|
test "walk reports each container's Enter and Exit around its children" {
  let value = @text.read_ion("{a: [1, null.list], b: x::2}")
  debug_inspect(
    value.walk().map(label).collect(),
    content=(
      #|[
      #|  "enter struct",
      #|  "enter list a",
      #|  "scalar int",
      #|  "scalar list",
      #|  "exit list a",
      #|  "scalar int b @1",
      #|  "exit struct",
      #|]
    ),
  )
}

///|
test "a scalar walks as one Scalar event" {
  debug_inspect(
    @ion.IonValue::int(7).walk().map(label).collect(),
    content=(
      #|["scalar int"]
    ),
  )
}

///|
test "a typed null container is a Scalar, not an Enter and Exit" {
  debug_inspect(
    @text.read_ion("null.struct").walk().map(label).collect(),
    content=(
      #|["scalar struct"]
    ),
  )
}

///|
test "skip_children after an Enter goes to that container's Exit" {
  let walker = @text.read_ion("[1, [2, 3], 4]").walker()
  let labels : Array[String] = []
  while walker.next() is Some(event) {
    labels.push(label(event))
    if event is Enter(value, ..) && value.kind() is List([_, _]) {
      walker.skip_children()
    }
  }
  debug_inspect(
    labels,
    content=(
      #|[
      #|  "enter list",
      #|  "scalar int",
      #|  "enter list",
      #|  "exit list",
      #|  "scalar int",
      #|  "exit list",
      #|]
    ),
  )
}

///|
test "skip_children after a Scalar or an Exit does nothing" {
  let walker = @text.read_ion("[[1], 2]").walker()
  let labels : Array[String] = []
  while walker.next() is Some(event) {
    labels.push(label(event))
    if !(event is Enter(_, ..)) {
      walker.skip_children()
    }
  }
  assert_eq(labels.length(), 6)
}

///|
test "depth counts the containers the walk is inside" {
  let walker = @text.read_ion("[[1]]").walker()
  let depths : Array[Int] = []
  while walker.next() is Some(_) {
    depths.push(walker.depth())
  }
  debug_inspect(
    depths,
    content=(
      #|[1, 2, 2, 1, 0]
    ),
  )
}

///|
test "walk visits 100,000 levels" {
  let mut events = 0
  for _ in @testkit.deep_value(Mixed, 100_000).walk() {
    events += 1
  }
  assert_eq(events, 2 * 100_000 + 1)
}

///|
/// The events of a recursive walk, as labels: the oracle for `walk`.
fn reference_labels(
  value : @ion.IonValue,
  field : @ion.SymbolToken?,
  out : Array[String],
) -> Unit {
  match value.kind() {
    List(items) | Sexp(items) => {
      out.push(label(Enter(value, field~)))
      for item in items {
        reference_labels(item, None, out)
      }
      out.push(label(Exit(value, field~)))
    }
    Struct(fields) => {
      out.push(label(Enter(value, field~)))
      for item in fields {
        reference_labels(item.value(), Some(item.name()), out)
      }
      out.push(label(Exit(value, field~)))
    }
    _ => out.push(label(Scalar(value, field~)))
  }
}

///|
test "walk matches a recursive walk on generated values" {
  for
    value in @testkit.gen_value(max_depth=6, max_width=4).samples(
      count=300,
      size=8,
    ) {
    let expected : Array[String] = []
    reference_labels(value, None, expected)
    assert_eq(value.walk().map(label).collect(), expected)
  }
}
