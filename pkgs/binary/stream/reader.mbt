// A pull reader over an asynchronous Ion binary stream.
//
// Each value is framed by its own descriptor and length and decoded on
// arrival, so memory stays proportional to the largest single value rather
// than to the stream. A local symbol table updates the reader's symbol table
// as it appears and is consumed rather than returned.
//
// Octets that arrive while a value is incomplete wait in a growable buffer and
// join the pending octets only once the whole value has arrived, so a large
// value costs time linear in its length. Decoded values are skipped by offset
// rather than copied away.

///|
/// A reader that pulls Ion binary values from an async byte source.
struct BinaryReader {
  source : &@io.Reader
  table : @ion.SymbolTable
  /// Octets not yet decoded, from `start` on, and then `arrived`.
  mut buffer : Bytes
  mut start : Int
  /// Octets read since `buffer` was last built.
  arrived : @buffer.Buffer
  /// The octets the next value needs before a decode is worth trying.
  mut needed : Int
  mut eof : Bool
}

///|
/// A reader over `source`, holding no octets until the first value is asked
/// for. `prefix` holds octets the caller already read from `source`, such as
/// the first few it looked at to choose a reader; they are read first.
/// `catalog` supplies the shared symbol tables that local symbol tables
/// import.
pub fn BinaryReader::new(
  source : &@io.Reader,
  prefix? : Bytes = b"",
  catalog? : @ion.Catalog = @ion.Catalog::new(),
) -> BinaryReader {
  let arrived = @buffer.Buffer()
  arrived.write_bytes(prefix)
  {
    source,
    table: @ion.SymbolTable::system(catalog~),
    buffer: Bytes::new(0),
    start: 0,
    arrived,
    needed: 1,
    eof: false,
  }
}

///|
/// The next value, or `None` at the end of the stream. A version marker and
/// local symbol tables update the reader's symbol table and are not returned.
pub async fn BinaryReader::next(self : BinaryReader) -> @ion.IonValue? {
  while true {
    if !self.eof && self.available() < self.needed {
      self.fill()
      continue
    }
    let bytes = self.pending()
    if bytes.length() == 0 {
      if self.eof {
        return None
      }
      self.needed = 1
      continue
    }
    if bytes[0].to_int() == 0xE0 && bytes.length() < 4 && !self.eof {
      // Possibly the start of a version marker.
      self.needed = 4
      continue
    }
    if @binary.has_version_marker(bytes, 0) {
      self.start += 4
      self.table.reset()
      continue
    }
    match @binary.decode_value(bytes, 0, self.table) {
      Some((value, consumed)) => {
        self.start += consumed
        self.needed = 0
        match @binary.accept_value(self.table, value) {
          Some(value) => return Some(value)
          None => ()
        }
      }
      None => {
        if self.eof {
          if @binary.is_padding_only(bytes, 0) {
            return None
          }
          raise @ion.IonError::Syntax("truncated Ion binary value")
        }
        // Wait for the whole value, or at least one more octet when its
        // length is not known yet or padding comes before it.
        let size = @binary.value_size(bytes, 0).unwrap_or(0)
        self.needed = if size > bytes.length() {
          size
        } else {
          bytes.length() + 1
        }
      }
    }
  }
  None
}

///|
/// The number of octets read and not yet decoded.
fn BinaryReader::available(self : BinaryReader) -> Int {
  self.buffer.length() - self.start + self.arrived.length()
}

///|
/// The octets not yet decoded, joining the octets that have arrived.
fn BinaryReader::pending(self : BinaryReader) -> BytesView {
  if !self.arrived.is_empty() {
    self.buffer = self.buffer[self.start:].to_owned() + self.arrived.to_bytes()
    self.start = 0
    self.arrived.reset()
  }
  self.buffer[self.start:]
}

///|
/// Read one more chunk from the source into the arrived octets.
async fn BinaryReader::fill(self : BinaryReader) -> Unit {
  let chunk = self.source.read_some(max_len=read_size) catch {
    _ => raise @ion.IonError::Syntax("the Ion binary stream could not be read")
  }
  match chunk {
    Some(bytes) if bytes.length() > 0 => self.arrived.write_bytes(bytes)
    _ => self.eof = true
  }
}

///|
/// The most octets to ask the source for in one read. Without a limit, a read
/// returns about one kilobyte, and the cost of each read dominates.
let read_size : Int = 65536
