// A pull reader of Ion events over an asynchronous Ion text stream.

///|
/// A reader that pulls the `@text.IonEvent` stream of an async byte source of
/// UTF-8 text. It parses one top-level value at a time and hands out its
/// events, so it holds the events of one value rather than of the stream.
struct TextEventReader {
  values : TextReader
  /// The events of the current value that are not yet handed out.
  events : Array[@text.IonEvent]
  mut index : Int
  mut started : Bool
  mut ended : Bool
}

///|
/// An event reader over `source`, holding no text until the first event is
/// asked for. `catalog` supplies the shared symbol tables that local symbol
/// tables import.
pub fn TextEventReader::new(
  source : &@io.Reader,
  catalog? : @ion.Catalog = @ion.Catalog::new(),
) -> TextEventReader {
  {
    values: TextReader::new(source, catalog~),
    events: [],
    index: 0,
    started: false,
    ended: false,
  }
}

///|
/// The next event, or `None` once the stream is exhausted. The events are the
/// ones `@text.IonReader::from_text` produces for the whole text:
/// `DocumentStart`, the events of each value in turn, and `DocumentEnd`.
pub async fn TextEventReader::next(self : TextEventReader) -> @text.IonEvent? {
  if !self.started {
    self.started = true
    return Some(DocumentStart)
  }
  while self.index >= self.events.length() {
    if self.ended {
      return None
    }
    match self.values.next() {
      Some(value) => {
        // A single-value reader frames the value's events with a document
        // start and end, which belong to the whole stream instead.
        let events = @text.IonReader::from_value(value).remaining()
        self.events.clear()
        for index in 1..<(events.length() - 1) {
          self.events.push(events[index])
        }
        self.index = 0
      }
      None => {
        self.ended = true
        return Some(DocumentEnd)
      }
    }
  }
  let event = self.events[self.index]
  self.index += 1
  Some(event)
}
