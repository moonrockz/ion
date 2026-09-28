// A pull reader over an asynchronous Ion text stream.
//
// Octets are decoded as UTF-8 as they arrive, and each top-level value is
// returned once it is settled (see `@text.read_ion_prefix`), so memory stays
// proportional to the largest single value rather than to the stream.
//
// Text has no length prefix to frame a value by, so a value that does not
// parse yet is taken to be cut short and the reader reads on. A malformed
// value is therefore reported only at the end of the stream.

///|
/// A reader that pulls Ion text values from an async byte source of UTF-8
/// text.
pub struct TextReader {
  source : &@io.Reader
  /// Decoded text not yet parsed, from `start` on.
  mut text : String
  mut start : Int
  /// The octets of a UTF-8 character that a read split in two.
  mut partial : Bytes
  mut eof : Bool
}

///|
/// A reader over `source`, holding no text until the first value is asked
/// for.
pub fn TextReader::new(source : &@io.Reader) -> TextReader {
  { source, text: "", start: 0, partial: Bytes::new(0), eof: false, }
}

///|
/// The next value, or `None` at the end of the stream. Values come back as
/// `@text.read_ion_datagram` would return them for the whole text.
pub async fn TextReader::next(self : TextReader) -> @ion.IonValue? {
  while true {
    let pending = self.text.view(start_offset=self.start)
    match @text.read_ion_prefix(pending, end_of_input=self.eof) {
      Some((value, consumed)) => {
        self.start += consumed
        return Some(value)
      }
      None => if self.eof { return None } else { self.fill() }
    }
  }
  None
}

///|
/// Read one more chunk from the source and append its text, keeping back the
/// octets of a character that the chunk splits.
async fn TextReader::fill(self : TextReader) -> Unit {
  let chunk = self.source.read_some() catch {
    _ => raise @ion.IonError::Syntax("the Ion text stream could not be read")
  }
  let octets = match chunk {
    Some(bytes) if bytes.length() > 0 => self.partial + bytes
    _ => {
      self.eof = true
      if self.partial.length() > 0 {
        raise @ion.IonError::Syntax(
          "the Ion text stream ends inside a UTF-8 character",
        )
      }
      return
    }
  }
  let whole = whole_characters(octets)
  let decoded = @utf8.decode(octets[:whole]) catch {
    _ => raise @ion.IonError::Syntax("the Ion text stream is not UTF-8")
  }
  self.partial = octets[whole:].to_owned()
  self.text = self.text.view(start_offset=self.start).to_owned() + decoded
  self.start = 0
}

///|
/// The length of the longest prefix of `octets` that does not end inside a
/// UTF-8 character. Only the last three octets can belong to a character
/// that is cut short; any other malformation is left for the decoder.
fn whole_characters(octets : Bytes) -> Int {
  let n = octets.length()
  for back in 1..<=3 {
    if back > n {
      break
    }
    let octet = octets[n - back].to_int()
    if octet < 0x80 {
      return n
    }
    if octet >= 0xC0 {
      let width = if octet >= 0xF0 { 4 } else if octet >= 0xE0 { 3 } else { 2 }
      return if width > back { n - back } else { n }
    }
  }
  n
}
