// A pull reader over an asynchronous Ion binary stream.
//
// Each value is framed by its own descriptor and length and decoded on
// arrival, so memory stays proportional to the largest single value rather
// than to the stream. A local symbol table updates the reader's symbol table
// as it appears and is consumed rather than returned.

///|
/// A reader that pulls Ion binary values from an async byte source.
pub struct BinaryReader {
  source : &@io.Reader
  table : @ion.SymbolTable
  mut buffer : Bytes
  mut eof : Bool
}

///|
/// A reader over `source`, holding no octets until the first value is asked
/// for.
pub fn BinaryReader::new(source : &@io.Reader) -> BinaryReader {
  {
    source,
    table: @ion.SymbolTable::system(),
    buffer: Bytes::new(0),
    eof: false,
  }
}

///|
/// The next value, or `None` at the end of the stream. A version marker and
/// local symbol tables update the reader's symbol table and are not returned.
pub async fn BinaryReader::next(self : BinaryReader) -> @ion.IonValue? {
  let mut result : @ion.IonValue? = None
  while result is None {
    if self.buffer.length() == 0 {
      if self.eof {
        break
      }
      self.fill()
      continue
    }
    if self.buffer[0].to_int() == 0xE0 {
      while self.buffer.length() < 4 && !self.eof {
        self.fill()
      }
      if self.buffer.length() >= 4 &&
        @binary.has_version_marker(self.buffer[:], 0) {
        self.buffer = self.buffer[4:].to_owned()
        self.table.reset()
        continue
      }
    }
    match @binary.decode_value(self.buffer[:], 0, self.table) {
      Some((value, consumed)) => {
        self.buffer = self.buffer[consumed:].to_owned()
        match @binary.accept_value(self.table, value) {
          Some(value) => result = Some(value)
          None => ()
        }
      }
      None =>
        if self.eof {
          if @binary.is_padding_only(self.buffer[:], 0) {
            break
          }
          raise @ion.IonError::Syntax("truncated Ion binary value")
        } else {
          self.fill()
        }
    }
  }
  result
}

///|
/// Read one more chunk from the source into the buffer.
async fn BinaryReader::fill(self : BinaryReader) -> Unit {
  let chunk = self.source.read_some() catch {
    _ => raise @ion.IonError::Syntax("the Ion binary stream could not be read")
  }
  match chunk {
    Some(bytes) =>
      if bytes.length() == 0 {
        self.eof = true
      } else {
        self.buffer = self.buffer + bytes
      }
    None => self.eof = true
  }
}
