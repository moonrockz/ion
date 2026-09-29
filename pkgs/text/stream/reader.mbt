// A pull reader over an asynchronous Ion text stream.
//
// Octets are decoded as they arrive, in the encoding the first octets show
// (UTF-8, UTF-16, or UTF-32; see `@text.detect_encoding`), and each top-level
// value is
// returned once it is settled (see `@text.read_ion_prefix`), so memory stays
// proportional to the largest single value rather than to the stream.
//
// Text has no length prefix to frame a value by. A framer reads each code
// unit once and tells the reader when the text is back at the top level
// between values; only then does the reader try a parse, so a large value
// costs time linear in its length. A value that does not parse yet is taken to
// be cut short and the reader reads on, so a malformed value is reported only
// at the end of the stream.

///|
/// A reader that pulls Ion text values from an async byte source of UTF-8
/// text.
struct TextReader {
  source : &@io.Reader
  /// Decoded text not yet parsed, from `start` on, and then `arrived`.
  mut text : String
  mut start : Int
  /// Decoded text that came after `text` was last built. It joins `text`
  /// only when a parse is tried, so waiting on a large value copies nothing.
  arrived : StringBuilder
  framer : Framer
  /// The symbols in effect, as version markers and local symbol tables set
  /// them.
  symbols : @ion.SymbolTable
  /// The code units at the end that the framer has not read yet.
  mut unscanned : String
  /// The octets of a character that a read split, or, before the encoding
  /// is known, every octet so far.
  mut partial : Bytes
  /// The encoding of the source, once its first octets have arrived.
  mut encoding : @text.TextEncoding?
  mut eof : Bool
}

///|
/// A reader over `source`, holding no text until the first value is asked
/// for. `prefix` holds octets the caller already read from `source`, such as
/// the first few it looked at to choose a reader; they are read first.
/// `catalog` supplies the shared symbol tables that local symbol tables
/// import.
pub fn TextReader::new(
  source : &@io.Reader,
  prefix? : Bytes = b"",
  catalog? : @ion.Catalog = @ion.Catalog::new(),
) -> TextReader {
  {
    source,
    text: "",
    start: 0,
    arrived: StringBuilder(),
    framer: Framer::new(),
    symbols: @ion.SymbolTable::system(catalog~),
    unscanned: "",
    // Decoded with the first chunk, as octets a read left over would be.
    partial: prefix,
    encoding: None,
    eof: false,
  }
}

///|
/// The next value, or `None` at the end of the stream. Values come back as
/// `@text.read_ion_datagram` would return them for the whole text.
pub async fn TextReader::next(self : TextReader) -> @ion.IonValue? {
  while true {
    match self.take() {
      Some(value) => return Some(value)
      None => if self.eof { return None } else { self.fill() }
    }
  }
  None
}

///|
/// The next value in the text that has arrived, or `None` when it holds none
/// yet. A parse is tried only at the end of the stream, or when the framer
/// has seen the text at the top level since the last try. Version markers and
/// local symbol tables update the symbol table and are not returned.
fn TextReader::take(self : TextReader) -> @ion.IonValue? raise @ion.IonError {
  while self.eof || self.framer.at_top {
    self.framer.at_top = false
    match
      @text.read_ion_prefix(
        self.pending(),
        symbols=self.symbols,
        end_of_input=self.eof,
      ) {
      Some((value, consumed)) => {
        self.start += consumed
        // The rest of the text may already hold the next value.
        self.framer.at_top = true
        if value is Some(_) {
          return value
        }
      }
      None => return None
    }
  }
  None
}

///|
/// The decoded text not yet parsed, joining the text that has arrived.
fn TextReader::pending(self : TextReader) -> StringView {
  if !self.arrived.is_empty() {
    self.text = self.text.view(start_offset=self.start).to_owned() +
      self.arrived.to_string()
    self.start = 0
    self.arrived.reset()
  }
  self.text.view(start_offset=self.start)
}

///|
/// Take in decoded text and let the framer read it.
fn TextReader::append(self : TextReader, decoded : String) -> Unit {
  self.arrived.write_string(decoded)
  let text = self.unscanned + decoded
  let stop = self.framer.scan(text, 0)
  self.unscanned = text.view(start_offset=stop).to_owned()
}

///|
/// Read one more chunk from the source and append its text, keeping back the
/// octets of a character that the chunk splits.
async fn TextReader::fill(self : TextReader) -> Unit {
  let chunk = self.source.read_some(max_len=read_size) catch {
    _ => raise @ion.IonError::Syntax("the Ion text stream could not be read")
  }
  let mut octets = match chunk {
    Some(bytes) if bytes.length() > 0 => self.partial + bytes
    _ => {
      self.eof = true
      self.partial
    }
  }
  let encoding = match self.encoding {
    Some(encoding) => encoding
    None => {
      // Four octets tell the encodings apart; wait for them unless the
      // stream ends first.
      if octets.length() < 4 && !self.eof {
        self.partial = octets
        return
      }
      let (encoding, mark) = @text.detect_encoding(octets)
      octets = octets[mark:].to_owned()
      self.encoding = Some(encoding)
      encoding
    }
  }
  let whole = @text.complete_length(encoding, octets)
  // At the end of the stream, what is left must be whole characters.
  if self.eof && whole < octets.length() {
    raise @ion.IonError::Syntax("the Ion text stream ends inside a character")
  }
  let decoded = @text.decode_text(encoding, octets[:whole])
  self.partial = octets[whole:].to_owned()
  self.append(decoded)
}

///|
/// The most octets to ask the source for in one read. Without a limit, a read
/// returns about one kilobyte, and the cost of each read dominates.
let read_size : Int = 65536
