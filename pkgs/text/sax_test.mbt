// Black-box tests for the SAX-style event reader and push handler.

///|
fn event_names(text : String) -> Array[String] raise {
  let events = @text.IonReader::from_text(text).remaining()
  let names : Array[String] = []
  for event in events {
    names.push(event.to_text())
  }
  names
}

///|
test "events mirror a struct" {
  assert_eq(event_names("{a: 1, b: [x]}"), [
    "DocumentStart", "StructStart", "FieldName(a)", "Scalar(int)", "FieldName(b)",
    "ListStart", "Scalar(symbol)", "ListEnd", "StructEnd", "DocumentEnd",
  ])
}

///|
test "annotation events precede the value" {
  assert_eq(event_names("int32::12"), [
    "DocumentStart", "Annotation(int32)", "Scalar(int)", "DocumentEnd",
  ])
}

///|
test "pull reader advances one event at a time" {
  let reader = @text.IonReader::from_text("(a b)")
  assert_true(reader.next() is Some(@text.IonEvent::DocumentStart))
  assert_true(reader.next() is Some(@text.IonEvent::SexpStart))
  assert_eq(reader.remaining().length(), 4)
  assert_true(reader.next() is Some(@text.IonEvent::Scalar(_)))
}

///|
struct Recorder {
  events : Array[String]
}

///|
impl @text.IonHandler for Recorder with fn on_document_start(self) {
  self.events.push("start")
}

///|
impl @text.IonHandler for Recorder with fn on_document_end(self) {
  self.events.push("end")
}

///|
impl @text.IonHandler for Recorder with fn on_scalar(self, _value) {
  self.events.push("scalar")
}

///|
impl @text.IonHandler for Recorder with fn on_field_name(self, token) {
  self.events.push("field:" + token.text().unwrap_or("?"))
}

///|
test "push handler receives events" {
  let recorder : Recorder = { events: [], }
  @text.parse_with_handler("1 {a: 2}", recorder)
  assert_eq(recorder.events, ["start", "scalar", "field:a", "scalar", "end"])
}
