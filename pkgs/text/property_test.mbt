// Property-based tests for the Ion text reader and writer.
//
// A round trip is the specification of an encoder/decoder pair, so these laws
// are the natural properties to state: `read(write(v)) == v`, and canonical
// text is a fixed point. QuickCheck generates the inputs and shrinks any
// counterexample to a minimal one.

///|
test "integers survive a text round-trip" {
  @quickcheck.check((n : BigInt) => {
    let value = @ion.IonValue::big_int(n)
    @text.read_ion(@text.write_ion(value)).equals(value)
  })
}

///|
test "strings survive a text round-trip" {
  @quickcheck.check((s : String) => {
    let value = @ion.IonValue::string(s)
    @text.read_ion(@text.write_ion(value)).equals(value)
  })
}

///|
test "symbols survive a text round-trip" {
  @quickcheck.check((s : String) => {
    let value = @ion.IonValue::symbol(s)
    @text.read_ion(@text.write_ion(value)).equals(value)
  })
}

///|
test "blobs and clobs survive a text round-trip" {
  @quickcheck.check((bytes : Bytes) => {
    let blob = @ion.IonValue::blob(bytes)
    let clob = @ion.IonValue::clob(bytes)
    @text.read_ion(@text.write_ion(blob)).equals(blob) &&
    @text.read_ion(@text.write_ion(clob)).equals(clob)
  })
}

///|
test "canonical text is a fixed point of write and read" {
  @quickcheck.check((s : String) => {
    let once = @text.write_ion(@ion.IonValue::string(s))
    @text.write_ion(@text.read_ion(once)) == once
  })
}

///|
test "tokenizing a written value reproduces its source" {
  @quickcheck.check((s : String) => {
    let text = @text.write_ion(@ion.IonValue::string(s))
    let rebuilt = StringBuilder()
    for token in @text.tokenize(text) {
      rebuilt.write_view(token.slice(text))
    }
    rebuilt.to_string() == text
  })
}

///|
fn walker_samples() -> Array[@ion.IonValue] {
  @testkit.gen_value(max_depth=6, max_width=4).samples(count=300, size=8)
}

///|
test "generated values survive compact and pretty text" {
  for value in walker_samples() {
    let compact = @text.write_ion(value)
    if !@text.read_ion(compact).equals(value) {
      fail("compact: \{compact}")
    }
    let pretty = @text.write_ion_pretty(value)
    if !@text.read_ion(pretty).equals(value) {
      fail("pretty: \{pretty}")
    }
  }
}

///|
/// A container that `EventBuilder` is building.
priv struct Building {
  kind : @ion.IonType
  annotations : Array[@ion.SymbolToken]
  field : @ion.SymbolToken?
  items : Array[@ion.IonValue]
  fields : Array[@ion.Field]
}

///|
/// Rebuilds values from an event stream with a stack, at any depth.
priv struct EventBuilder {
  top : Array[@ion.IonValue]
  open : Array[Building]
  pending : Array[@ion.SymbolToken]
  mut field : @ion.SymbolToken?
}

///|
fn EventBuilder::take_annotations(
  self : EventBuilder,
) -> Array[@ion.SymbolToken] {
  let annotations = self.pending.copy()
  self.pending.clear()
  annotations
}

///|
fn EventBuilder::add(
  self : EventBuilder,
  value : @ion.IonValue,
  field : @ion.SymbolToken?,
) -> Unit {
  match (self.open.last(), field) {
    (None, _) => self.top.push(value)
    (Some(parent), Some(name)) =>
      parent.fields.push(@ion.Field::from_token(name, value))
    (Some(parent), None) => parent.items.push(value)
  }
}

///|
fn EventBuilder::feed(
  self : EventBuilder,
  event : @text.IonEvent,
) -> Unit raise Failure {
  match event {
    DocumentStart | DocumentEnd => ()
    Annotation(token) => self.pending.push(token)
    FieldName(token) => self.field = Some(token)
    ListStart | SexpStart | StructStart => {
      let kind : @ion.IonType = match event {
        ListStart => List
        SexpStart => Sexp
        _ => Struct
      }
      self.open.push({
        kind,
        annotations: self.take_annotations(),
        field: self.field,
        items: [],
        fields: [],
      })
      self.field = None
    }
    ListEnd | SexpEnd | StructEnd => {
      guard self.open.pop() is Some(building) else {
        fail("an end event with no open container")
      }
      let value = match building.kind {
        List => @ion.IonValue::list(building.items)
        Sexp => @ion.IonValue::sexp(building.items)
        _ => @ion.IonValue::from_fields(building.fields)
      }
      self.add(value.with_annotations(building.annotations), building.field)
    }
    Scalar(value) => {
      let field = self.field
      self.field = None
      self.add(value.with_annotations(self.take_annotations()), field)
    }
  }
}

///|
fn values_from_events(
  events : Array[@text.IonEvent],
) -> Array[@ion.IonValue] raise Failure {
  let builder : EventBuilder = { top: [], open: [], pending: [], field: None, }
  for event in events {
    builder.feed(event)
  }
  if !builder.open.is_empty() ||
    !builder.pending.is_empty() ||
    builder.field is Some(_) {
    fail("the events end inside a value")
  }
  builder.top
}

///|
test "events rebuild the value they came from" {
  for value in walker_samples() {
    let rebuilt = values_from_events(
      @text.IonReader::from_value(value).remaining(),
    )
    if rebuilt.length() != 1 || !rebuilt[0].equals(value) {
      fail("events of \{@text.write_ion(value)}")
    }
  }
}

///|
/// Records the events a handler receives.
struct EventRecorder {
  events : Array[@text.IonEvent]
}

///|
impl @text.IonHandler for EventRecorder with fn on_document_start(self) {
  self.events.push(@text.IonEvent::DocumentStart)
}

///|
impl @text.IonHandler for EventRecorder with fn on_document_end(self) {
  self.events.push(@text.IonEvent::DocumentEnd)
}

///|
impl @text.IonHandler for EventRecorder with fn on_annotation(self, token) {
  self.events.push(@text.IonEvent::Annotation(token))
}

///|
impl @text.IonHandler for EventRecorder with fn on_field_name(self, token) {
  self.events.push(@text.IonEvent::FieldName(token))
}

///|
impl @text.IonHandler for EventRecorder with fn on_list_start(self) {
  self.events.push(@text.IonEvent::ListStart)
}

///|
impl @text.IonHandler for EventRecorder with fn on_list_end(self) {
  self.events.push(@text.IonEvent::ListEnd)
}

///|
impl @text.IonHandler for EventRecorder with fn on_sexp_start(self) {
  self.events.push(@text.IonEvent::SexpStart)
}

///|
impl @text.IonHandler for EventRecorder with fn on_sexp_end(self) {
  self.events.push(@text.IonEvent::SexpEnd)
}

///|
impl @text.IonHandler for EventRecorder with fn on_struct_start(self) {
  self.events.push(@text.IonEvent::StructStart)
}

///|
impl @text.IonHandler for EventRecorder with fn on_struct_end(self) {
  self.events.push(@text.IonEvent::StructEnd)
}

///|
impl @text.IonHandler for EventRecorder with fn on_scalar(self, value) {
  self.events.push(@text.IonEvent::Scalar(value))
}

///|
fn render_event(event : @text.IonEvent) -> String raise @ion.IonError {
  match event {
    Scalar(value) => "Scalar " + @text.write_ion(value)
    Annotation(token) => "Annotation " + @text.symbol_to_text(token)
    FieldName(token) => "FieldName " + @text.symbol_to_text(token)
    other => other.to_text()
  }
}

///|
test "dispatch pushes the same events that the reader pulls" {
  for value in walker_samples() {
    let recorder : EventRecorder = { events: [], }
    @text.dispatch_values([value], recorder)
    let pulled = @text.IonReader::from_value(value).remaining()
    let pushed : Array[String] = []
    for event in recorder.events {
      pushed.push(render_event(event))
    }
    let expected : Array[String] = []
    for event in pulled {
      expected.push(render_event(event))
    }
    assert_eq(pushed, expected)
  }
}

///|
test "values with symbols from a shared import survive text" {
  for
    value in @testkit.gen_value(max_depth=6, max_width=4, imported_symbols=true).samples(
      count=300,
      size=8,
    ) {
    let text = @text.write_ion(value)
    if !@text.read_ion(text).equals(value) {
      fail("imported symbols: \{text}")
    }
  }
}

///|
test "the event rebuilder rejects unbalanced or unfinished events" {
  let unbalanced : Array[@text.IonEvent] = [ListEnd]
  let unclosed : Array[@text.IonEvent] = [ListStart]
  let dangling : Array[@text.IonEvent] = [
    Annotation(@ion.SymbolToken::new("a")),
  ]
  for events in [unbalanced, unclosed, dangling] {
    let rejected = try values_from_events(events) catch {
      _ => true
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
}
