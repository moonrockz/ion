// Writing Ion text to an asynchronous byte sink.

///|
/// A writer that encodes Ion values as UTF-8 text to an async byte sink, one
/// value per line, as each value is written.
struct TextWriter {
  sink : &@io.Writer
  pretty : Bool
  mut first : Bool
  /// The highest symbol ID reserved with unknown text so far.
  mut reserved : Int
}

///|
/// A writer to `sink`, writing compact text, or indented text when `pretty`.
pub fn TextWriter::new(
  sink : &@io.Writer,
  pretty? : Bool = false,
) -> TextWriter {
  { sink, pretty, first: true, reserved: 9, }
}

///|
/// Write `value`, after a newline unless it is the first value. The octets
/// written for a sequence of values are the UTF-8 encoding of
/// `@text.write_all` for it, or of `@text.write_all_pretty` when `pretty`.
///
/// No text follows the last value, so a reader on the other end settles a
/// value that does not close with `]`, `)`, `}`, or `"` only when more text
/// or the end of the stream arrives. A buffered sink is flushed by its owner,
/// not here.
pub async fn TextWriter::write(
  self : TextWriter,
  value : @ion.IonValue,
) -> Unit {
  let (text, reserved) = @text.write_stream_value(
    value,
    reserved=self.reserved,
    pretty=self.pretty,
  )
  self.reserved = reserved
  let separator = if self.first { "" } else { "\n" }
  self.first = false
  self.sink.write(@utf8.encode(separator + text))
}

///|
/// Write `values` to `writer` as Ion text, one value per line: the same octets
/// as the UTF-8 encoding of `@text.write_all`, or of `@text.write_all_pretty`
/// when `pretty`. Each value is encoded and written in turn.
///
/// A buffered writer is flushed by its owner, not here.
pub async fn write_all(
  writer : &@io.Writer,
  values : Array[@ion.IonValue],
  pretty? : Bool = false,
) -> Unit {
  let text_writer = TextWriter::new(writer, pretty~)
  for value in values {
    text_writer.write(value)
  }
}
