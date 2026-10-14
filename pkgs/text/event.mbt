// The Ion event stream: a flat, push- and pull-friendly view of a datagram.
//
// Events are derived from an `IonValue` tree (or a parsed datagram) and mirror
// its structure: a document start/end, container start/end, a field-name event
// before each struct field value, an annotation event before each annotation,
// and a scalar event for every non-container value.

///|
/// A single event in an Ion document.
pub(all) enum IonEvent {
  DocumentStart
  DocumentEnd
  /// Emitted before a value, once per annotation.
  Annotation(@ion.SymbolToken)
  /// Emitted before a struct field's value.
  FieldName(@ion.SymbolToken)
  ListStart
  ListEnd
  SexpStart
  SexpEnd
  StructStart
  StructEnd
  /// A non-container value. Its annotations were emitted as `Annotation`
  /// events, so the carried value has none.
  Scalar(@ion.IonValue)
} derive(Debug)

///|
/// A short human-readable name for the event.
pub fn IonEvent::to_text(self : IonEvent) -> String {
  match self {
    DocumentStart => "DocumentStart"
    DocumentEnd => "DocumentEnd"
    Annotation(token) =>
      "Annotation(" + token.text().unwrap_or("$<unknown>") + ")"
    FieldName(token) =>
      "FieldName(" + token.text().unwrap_or("$<unknown>") + ")"
    ListStart => "ListStart"
    ListEnd => "ListEnd"
    SexpStart => "SexpStart"
    SexpEnd => "SexpEnd"
    StructStart => "StructStart"
    StructEnd => "StructEnd"
    Scalar(value) => "Scalar(" + value.ion_type().to_text() + ")"
  }
}

///|
/// The start and end events of a list, S-expression or struct.
fn container_events(value : @ion.IonValue) -> (IonEvent, IonEvent) {
  match value.kind() {
    List(_) => (ListStart, ListEnd)
    Sexp(_) => (SexpStart, SexpEnd)
    _ => (StructStart, StructEnd)
  }
}

///|
/// Emit `value`'s events into `events`, at any depth.
fn emit_value(value : @ion.IonValue, events : Array[IonEvent]) -> Unit {
  emit_shallow(value, events, @ion.MAX_NESTING_DEPTH)
}

///|
/// Emit `value`'s events with recursion while `levels` is above zero. At zero
/// levels a container switches to `emit_deep`; a scalar stays here. Recursion
/// is the fastest walk; the limit keeps the call stack small at any depth.
fn emit_shallow(
  value : @ion.IonValue,
  events : Array[IonEvent],
  levels : Int32,
) -> Unit {
  if levels == 0 && value.kind() is (List(_) | Sexp(_) | Struct(_)) {
    return emit_deep(value, events)
  }
  for annotation in value.annotations() {
    events.push(Annotation(annotation))
  }
  match value.kind() {
    List(items) => {
      events.push(ListStart)
      for item in items {
        emit_shallow(item, events, levels - 1)
      }
      events.push(ListEnd)
    }
    Sexp(items) => {
      events.push(SexpStart)
      for item in items {
        emit_shallow(item, events, levels - 1)
      }
      events.push(SexpEnd)
    }
    Struct(fields) => {
      events.push(StructStart)
      for field in fields {
        events.push(FieldName(field.name()))
        emit_shallow(field.value(), events, levels - 1)
      }
      events.push(StructEnd)
    }
    _ => events.push(Scalar(without_annotations(value)))
  }
}

///|
/// Emit `value`'s events with no recursion.
fn emit_deep(value : @ion.IonValue, events : Array[IonEvent]) -> Unit {
  traverse(
    value,
    (current, field) => {
      emit_prefix(current, field, events)
      match current.kind() {
        List(_) | Sexp(_) | Struct(_) =>
          events.push(container_events(current).0)
        _ => events.push(IonEvent::Scalar(without_annotations(current)))
      }
    },
    current => events.push(container_events(current).1),
  )
}

///|
/// The field-name and annotation events before a value.
fn emit_prefix(
  value : @ion.IonValue,
  field : @ion.SymbolToken?,
  events : Array[IonEvent],
) -> Unit {
  if field is Some(name) {
    events.push(FieldName(name))
  }
  for annotation in value.annotations() {
    events.push(Annotation(annotation))
  }
}

///|
/// A pull-based iterator over an Ion event stream.
pub struct IonReader {
  events : Array[IonEvent]
  mut index : Int32
}

///|
/// An event reader over a parsed datagram.
pub fn IonReader::from_values(values : Array[@ion.IonValue]) -> IonReader {
  let events : Array[IonEvent] = [DocumentStart]
  for value in values {
    emit_value(value, events)
  }
  events.push(DocumentEnd)
  { events, index: 0, }
}

///|
/// An event reader over a single value.
pub fn IonReader::from_value(value : @ion.IonValue) -> IonReader {
  IonReader::from_values([value])
}

///|
/// An event reader over Ion text.
pub fn IonReader::from_text(text : StringView) -> IonReader raise @ion.IonError {
  IonReader::from_values(read_ion_datagram(text))
}

///|
/// The next event, or `None` when the stream is exhausted.
pub fn IonReader::next(self : IonReader) -> IonEvent? {
  if self.index >= self.events.length() {
    None
  } else {
    let event = self.events[self.index]
    self.index += 1
    Some(event)
  }
}

///|
/// All events in the stream, from the current position.
pub fn IonReader::remaining(self : IonReader) -> Array[IonEvent] {
  let result : Array[IonEvent] = []
  for index in self.index..<self.events.length() {
    result.push(self.events[index])
  }
  result
}

///|
pub extend IonEvent with @debug.Debug::{to_repr}

///|
/// `value` without its annotations, which the events carry separately. A
/// value with none is returned as it is, so most scalars cost no copy.
fn without_annotations(value : @ion.IonValue) -> @ion.IonValue {
  if value.has_annotations() {
    value.with_annotations([])
  } else {
    value
  }
}
