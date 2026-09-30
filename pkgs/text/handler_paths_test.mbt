///|
struct HandlerTrace {
  events : Array[String]
  scalars : Array[@ion.IonValue]
}

///|
impl @text.IonHandler for HandlerTrace with fn on_document_start(self) {
  self.events.push("start")
}

///|
impl @text.IonHandler for HandlerTrace with fn on_document_end(self) {
  self.events.push("end")
}

///|
impl @text.IonHandler for HandlerTrace with fn on_annotation(self, token) {
  self.events.push("annotation:" + token.text().unwrap_or("?"))
}

///|
impl @text.IonHandler for HandlerTrace with fn on_field_name(self, token) {
  self.events.push("field:" + token.text().unwrap_or("?"))
}

///|
impl @text.IonHandler for HandlerTrace with fn on_list_start(self) {
  self.events.push("list+")
}

///|
impl @text.IonHandler for HandlerTrace with fn on_list_end(self) {
  self.events.push("list-")
}

///|
impl @text.IonHandler for HandlerTrace with fn on_sexp_start(self) {
  self.events.push("sexp+")
}

///|
impl @text.IonHandler for HandlerTrace with fn on_sexp_end(self) {
  self.events.push("sexp-")
}

///|
impl @text.IonHandler for HandlerTrace with fn on_struct_start(self) {
  self.events.push("struct+")
}

///|
impl @text.IonHandler for HandlerTrace with fn on_struct_end(self) {
  self.events.push("struct-")
}

///|
impl @text.IonHandler for HandlerTrace with fn on_scalar(self, value) {
  self.events.push("scalar:" + value.ion_type().to_text())
  self.scalars.push(value)
}

///|
test "tree dispatch and reader feed deliver every callback in the same order" {
  let input = "outer:: {a: [(inner::1 2)], a: null.list} tail::true"
  let expected = [
    "start", "annotation:outer", "struct+", "field:a", "list+", "sexp+", "annotation:inner",
    "scalar:int", "scalar:int", "sexp-", "list-", "field:a", "scalar:list", "struct-",
    "annotation:tail", "scalar:bool", "end",
  ]
  let tree = HandlerTrace::{ events: [], scalars: [], }
  @text.parse_with_handler(input, tree)
  let pull = HandlerTrace::{ events: [], scalars: [], }
  let reader = @text.IonReader::from_text(input)
  reader.feed(pull)
  assert_eq(tree.events, expected)
  assert_eq(pull.events, expected)
  assert_eq(tree.scalars.length(), 4)
  for index, scalar in tree.scalars {
    assert_false(scalar.has_annotations())
    assert_true(scalar.equals(pull.scalars[index]))
  }
  reader.feed(pull)
  assert_eq(pull.events, expected)
}

///|
struct ScalarCounter {
  mut count : Int
}

///|
impl @text.IonHandler for ScalarCounter with fn on_scalar(self, _value) {
  self.count += 1
}

///|
struct DocumentCounter {
  mut count : Int
}

///|
impl @text.IonHandler for DocumentCounter with fn on_document_end(self) {
  self.count += 1
}

///|
test "default handler callbacks preserve traversal and empty documents" {
  let scalars = ScalarCounter::{ count: 0, }
  let documents = DocumentCounter::{ count: 0, }
  let values = @text.read_ion_datagram("a::{field: [(1 b::2)]} null.struct")
  @text.dispatch_values(values, scalars)
  @text.dispatch_values(values, documents)
  @text.IonReader::from_values(values).feed(scalars)
  @text.IonReader::from_values(values).feed(documents)
  @text.parse_with_handler("", documents)
  assert_eq(scalars.count, 6)
  assert_eq(documents.count, 3)
  let empty = HandlerTrace::{ events: [], scalars: [], }
  @text.IonReader::from_text("").feed(empty)
  assert_eq(empty.events, ["start", "end"])
}
