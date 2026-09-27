// Black-box tests for the visitor and fold traversal APIs.

///|
struct Collector {
  mut values : Int
  field_names : Array[String]
}

///|
impl @ion.IonVisitor for Collector with fn visit_value(self, _value) {
  self.values += 1
}

///|
impl @ion.IonVisitor for Collector with fn visit_field_name(self, token) {
  match token.text() {
    Some(text) => self.field_names.push(text)
    None => ()
  }
}

///|
test "visitor traverses depth-first" {
  let value = @ion.IonValue::from_fields([
    @ion.Field::new("a", @ion.IonValue::int(1)),
    @ion.Field::new("b", @ion.IonValue::list([@ion.IonValue::int(2)])),
  ])
  let collector : Collector = { values: 0, field_names: [], }
  value.accept(collector)
  // struct, int 1, list, int 2
  assert_eq(collector.values, 4)
  assert_eq(collector.field_names, ["a", "b"])
}

///|
test "fold accumulates with continuing" {
  let value = @ion.IonValue::list([
    @ion.IonValue::int(1),
    @ion.IonValue::int(2),
    @ion.IonValue::list([@ion.IonValue::int(3)]),
  ])
  let total = value.fold(0, {
    ..@ion.IonFold::default(),
    visit_value: @ion.continuing(fn(sum, v) {
      match v.kind() {
        @ion.IonValueKind::Int(n) => sum + n.to_int()
        _ => sum
      }
    }),
  })
  assert_eq(total, 6)
}

///|
test "fold SkipChildren stops descending" {
  let value = @ion.IonValue::list([@ion.IonValue::int(1), @ion.IonValue::int(2)])
  let visited = value.fold(0, {
    ..@ion.IonFold::default(),
    visit_value: fn(acc, _v) { @ion.FoldAction::SkipChildren(acc + 1) },
  })
  assert_eq(visited, 1)
}

///|
test "fold Stop aborts the whole traversal" {
  let value = @ion.IonValue::list([
    @ion.IonValue::int(1),
    @ion.IonValue::int(2),
    @ion.IonValue::int(3),
  ])
  let seen = value.fold([], {
    ..@ion.IonFold::default(),
    visit_value: fn(acc, v) {
      match v.kind() {
        @ion.IonValueKind::Int(n) =>
          if n.to_int() == 2 {
            @ion.FoldAction::Stop([..acc, n.to_int()])
          } else {
            @ion.FoldAction::Continue([..acc, n.to_int()])
          }
        _ => @ion.FoldAction::Continue(acc)
      }
    },
  })
  assert_eq(seen, [1, 2])
}
