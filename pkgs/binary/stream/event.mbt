// A pull reader of Ion events over an asynchronous Ion binary stream.

///|
/// A reader that emits `@text.IonEvent`s, holding the events of one
/// top-level value at a time. A container is decoded in full before its
/// events are available, as with `TextEventReader`.
struct BinaryEventReader {
  values : BinaryReader
  mut events : @text.IonReader?
  mut started : Bool
  mut ended : Bool
}

///|
/// An event reader over `source`, reading no bytes until events after
/// `DocumentStart` are requested. `prefix` is consumed before the source.
/// `catalog` supplies the shared symbol tables that local tables import.
pub fn BinaryEventReader::new(
  source : &@io.Reader,
  prefix? : Bytes = b"",
  catalog? : @ion.Catalog = @ion.Catalog::new(),
) -> BinaryEventReader {
  {
    values: BinaryReader::new(source, prefix~, catalog~),
    events: None,
    started: false,
    ended: false,
  }
}

///|
/// The next event, or `None` after the stream's single `DocumentEnd`.
/// Truncated or invalid input raises `@ion.IonError` before `DocumentEnd`.
pub async fn BinaryEventReader::next(
  self : BinaryEventReader,
) -> @text.IonEvent? {
  if !self.started {
    self.started = true
    return Some(DocumentStart)
  }
  while !self.ended {
    if self.events is Some(reader) {
      match reader.next() {
        Some(DocumentStart | DocumentEnd) => continue
        Some(event) => return Some(event)
        None => self.events = None
      }
    }
    match self.values.next() {
      Some(value) => self.events = Some(@text.IonReader::from_value(value))
      None => {
        self.ended = true
        return Some(DocumentEnd)
      }
    }
  }
  None
}
