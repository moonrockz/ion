// The same IonEvent stream as the text reader, decoded from Ion binary.

///|
/// A pull reader of a binary datagram's `@text.IonEvent`s. Like the sync
/// text event reader, construction decodes the whole datagram. Version
/// markers and local symbol tables update symbol resolution and emit no
/// events. For one top-level value at a time, use the async event reader.
pub struct BinaryEventReader {
  events : @text.IonReader
}

///|
/// Decode `bytes` into events, resolving shared-table imports with `catalog`.
pub fn BinaryEventReader::new(
  bytes : BytesView,
  catalog? : @ion.Catalog = @ion.Catalog::new(),
) -> BinaryEventReader raise @ion.IonError {
  { events: @text.IonReader::from_values(read_binary(bytes, catalog~)), }
}

///|
/// The next event, or `None` after `DocumentEnd`.
pub fn BinaryEventReader::next(self : BinaryEventReader) -> @text.IonEvent? {
  self.events.next()
}

///|
/// All events from the current position, without advancing the reader.
pub fn BinaryEventReader::remaining(
  self : BinaryEventReader,
) -> Array[@text.IonEvent] {
  self.events.remaining()
}
