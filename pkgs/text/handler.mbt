// A push-based (SAX-style) handler for an Ion event stream.
//
// The parser drives the process, calling the handler as it walks the value
// tree. Every method has a default no-op implementation.

///|
/// A handler for push-based Ion parsing.
///
/// Override only the events you care about. Drive it with
/// [`parse_with_handler`], [`dispatch_values`], or [`IonReader::feed`].
pub(open) trait IonHandler {
  fn on_document_start(Self) -> Unit = _
  fn on_document_end(Self) -> Unit = _
  fn on_annotation(Self, @ion.SymbolToken) -> Unit = _
  fn on_field_name(Self, @ion.SymbolToken) -> Unit = _
  fn on_list_start(Self) -> Unit = _
  fn on_list_end(Self) -> Unit = _
  fn on_sexp_start(Self) -> Unit = _
  fn on_sexp_end(Self) -> Unit = _
  fn on_struct_start(Self) -> Unit = _
  fn on_struct_end(Self) -> Unit = _
  fn on_scalar(Self, @ion.IonValue) -> Unit = _
}

///|
impl IonHandler with fn on_document_start(_self) {
  ()
}

///|
impl IonHandler with fn on_document_end(_self) {
  ()
}

///|
impl IonHandler with fn on_annotation(_self, _token) {
  ()
}

///|
impl IonHandler with fn on_field_name(_self, _token) {
  ()
}

///|
impl IonHandler with fn on_list_start(_self) {
  ()
}

///|
impl IonHandler with fn on_list_end(_self) {
  ()
}

///|
impl IonHandler with fn on_sexp_start(_self) {
  ()
}

///|
impl IonHandler with fn on_sexp_end(_self) {
  ()
}

///|
impl IonHandler with fn on_struct_start(_self) {
  ()
}

///|
impl IonHandler with fn on_struct_end(_self) {
  ()
}

///|
impl IonHandler with fn on_scalar(_self, _value) {
  ()
}

///|
/// Parse Ion text, pushing events to `handler`.
pub fn parse_with_handler(
  text : StringView,
  handler : &IonHandler,
) -> Unit raise @ion.IonError {
  dispatch_values(read_ion_datagram(text), handler)
}

///|
/// Push the events of a datagram to `handler`.
pub fn dispatch_values(
  values : Array[@ion.IonValue],
  handler : &IonHandler,
) -> Unit {
  handler.on_document_start()
  for value in values {
    dispatch_value(value, handler)
  }
  handler.on_document_end()
}

///|
/// Push the events of a single value to `handler`.
pub fn dispatch_value(value : @ion.IonValue, handler : &IonHandler) -> Unit {
  for annotation in value.annotations() {
    handler.on_annotation(annotation)
  }
  match value.kind() {
    @ion.IonValueKind::List(items) => {
      handler.on_list_start()
      for item in items {
        dispatch_value(item, handler)
      }
      handler.on_list_end()
    }
    @ion.IonValueKind::Sexp(items) => {
      handler.on_sexp_start()
      for item in items {
        dispatch_value(item, handler)
      }
      handler.on_sexp_end()
    }
    @ion.IonValueKind::Struct(fields) => {
      handler.on_struct_start()
      for field in fields {
        handler.on_field_name(field.name())
        dispatch_value(field.value(), handler)
      }
      handler.on_struct_end()
    }
    _ => handler.on_scalar(value.with_annotations([]))
  }
}

///|
/// Drive `handler` with every event from `reader`.
pub fn IonReader::feed(self : IonReader, handler : &IonHandler) -> Unit {
  while true {
    match self.next() {
      None => break
      Some(event) => dispatch_event(event, handler)
    }
  }
}

///|
/// Push one event to `handler`.
pub fn dispatch_event(event : IonEvent, handler : &IonHandler) -> Unit {
  match event {
    DocumentStart => handler.on_document_start()
    DocumentEnd => handler.on_document_end()
    Annotation(token) => handler.on_annotation(token)
    FieldName(token) => handler.on_field_name(token)
    ListStart => handler.on_list_start()
    ListEnd => handler.on_list_end()
    SexpStart => handler.on_sexp_start()
    SexpEnd => handler.on_sexp_end()
    StructStart => handler.on_struct_start()
    StructEnd => handler.on_struct_end()
    Scalar(value) => handler.on_scalar(value)
  }
}
