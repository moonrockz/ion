// Document-order traces make early termination and skipped subtrees observable.

///|
fn traversal_values() -> Array[@ion.IonValue] {
  [
    @ion.IonValue::from_fields([
      @ion.Field::new(
        "first",
        @ion.IonValue::list([
          @ion.IonValue::sexp([
            @ion.IonValue::int(1).with_annotation(
              @ion.SymbolToken::new("scalar_a"),
            ),
            @ion.IonValue::string("inner"),
          ]),
        ]).with_annotations([
          @ion.SymbolToken::new("list_a"),
          @ion.SymbolToken::new("list_b"),
        ]),
      ),
      @ion.Field::new("last", @ion.IonValue::bool(true)),
    ]).with_annotations([
      @ion.SymbolToken::new("root_a"),
      @ion.SymbolToken::new("root_b"),
    ]),
    @ion.IonValue::int(99),
  ]
}

///|
fn value_label(value : @ion.IonValue) -> String {
  "value:" +
  (match value.kind() {
    Int(n) => n.to_string()
    _ => value.ion_type().to_text()
  })
}

///|
let traversal_order : Array[String] = [
  "value:struct", "annotation:root_a", "annotation:root_b", "field:first", "value:list",
  "annotation:list_a", "annotation:list_b", "value:sexp", "value:1", "annotation:scalar_a",
  "value:string", "field:last", "value:bool", "value:99",
]

///|
test "fold Stop returns the exact prefix at every callback and depth" {
  for index, stop in traversal_order {
    let action = (acc : Array[String], label : String) => {
      let acc = acc + [label]
      if label == stop {
        @ion.FoldAction::Stop(acc)
      } else {
        Continue(acc)
      }
    }
    let actual = @ion.fold_values(traversal_values(), [], {
      visit_value: (acc, value) => action(acc, value_label(value)),
      visit_annotation: (acc, token) => {
        action(acc, "annotation:" + token.text().unwrap())
      },
      visit_field_name: (acc, token) => {
        action(acc, "field:" + token.text().unwrap())
      },
    })
    assert_eq(actual, traversal_order[:index + 1].to_owned(), msg=stop)
  }
}

///|
test "fold SkipChildren keeps annotations and continues with siblings" {
  for
    (skip, expected) in [
      (
        "value:struct",
        ["value:struct", "annotation:root_a", "annotation:root_b", "value:99"],
      ),
      (
        "value:list",
        [
          "value:struct", "annotation:root_a", "annotation:root_b", "field:first",
          "value:list", "annotation:list_a", "annotation:list_b", "field:last", "value:bool",
          "value:99",
        ],
      ),
      (
        "value:sexp",
        [
          "value:struct", "annotation:root_a", "annotation:root_b", "field:first",
          "value:list", "annotation:list_a", "annotation:list_b", "value:sexp", "field:last",
          "value:bool", "value:99",
        ],
      ),
      ("value:1", traversal_order),
    ] {
    let actual = @ion.fold_values(traversal_values(), [], {
      visit_value: (acc, value) => {
        let label = value_label(value)
        let acc = acc + [label]
        if label == skip {
          @ion.FoldAction::SkipChildren(acc)
        } else {
          Continue(acc)
        }
      },
      visit_annotation: (acc, token) => {
        Continue(acc + ["annotation:" + token.text().unwrap()])
      },
      visit_field_name: (acc, token) => {
        Continue(acc + ["field:" + token.text().unwrap()])
      },
    })
    assert_eq(actual, expected, msg=skip)
  }
}

///|
test "metadata SkipChildren continues through field values and later annotations" {
  let actual = @ion.fold_values(traversal_values(), [], {
    visit_value: (acc, value) => Continue(acc + [value_label(value)]),
    visit_annotation: (acc, token) => {
      SkipChildren(acc + ["annotation:" + token.text().unwrap()])
    },
    visit_field_name: (acc, token) => {
      SkipChildren(acc + ["field:" + token.text().unwrap()])
    },
  })
  assert_eq(actual, traversal_order)
  assert_eq(@ion.fold_values(traversal_values(), 7, @ion.IonFold::default()), 7)
  assert_eq(@ion.fold_values([], 7, @ion.IonFold::default()), 7)
  for action in [@ion.FoldAction::Continue(3), SkipChildren(3), Stop(3)] {
    assert_eq(action.value(), 3)
    assert_eq(action.is_stop(), action is Stop(_))
  }
}

///|
struct TraceVisitor {
  events : Array[String]
}

///|
impl @ion.IonVisitor for TraceVisitor with fn visit_value(self, value) {
  self.events.push(value_label(value))
}

///|
impl @ion.IonVisitor for TraceVisitor with fn visit_annotation(self, token) {
  self.events.push("annotation:" + token.text().unwrap())
}

///|
impl @ion.IonVisitor for TraceVisitor with fn visit_field_name(self, token) {
  self.events.push("field:" + token.text().unwrap())
}

///|
impl @ion.IonVisitor for TraceVisitor with fn visit_list(self, items) {
  self.events.push("list:" + items.length().to_string())
}

///|
impl @ion.IonVisitor for TraceVisitor with fn visit_sexp(self, items) {
  self.events.push("sexp:" + items.length().to_string())
}

///|
impl @ion.IonVisitor for TraceVisitor with fn visit_struct(self, fields) {
  self.events.push("struct:" + fields.length().to_string())
}

///|
test "visitor delivers annotations and container callbacks before their contents" {
  let visitor = TraceVisitor::{ events: [], }
  @ion.accept_values(traversal_values(), visitor)
  assert_eq(visitor.events, [
    "value:struct", "annotation:root_a", "annotation:root_b", "struct:2", "field:first",
    "value:list", "annotation:list_a", "annotation:list_b", "list:1", "value:sexp",
    "sexp:2", "value:1", "annotation:scalar_a", "value:string", "field:last", "value:bool",
    "value:99",
  ])
}

///|
struct FieldVisitor {
  fields : Array[String]
}

///|
impl @ion.IonVisitor for FieldVisitor with fn visit_field_name(self, token) {
  self.fields.push(token.text().unwrap())
}

///|
struct ValueVisitor {
  mut count : Int
}

///|
impl @ion.IonVisitor for ValueVisitor with fn visit_value(self, _value) {
  self.count += 1
}

///|
test "selective visitors traverse through default callbacks" {
  let fields = FieldVisitor::{ fields: [], }
  let values = ValueVisitor::{ count: 0, }
  @ion.accept_values(traversal_values(), fields)
  @ion.accept_values(traversal_values(), values)
  assert_eq(fields.fields, ["first", "last"])
  assert_eq(values.count, 7)
}
