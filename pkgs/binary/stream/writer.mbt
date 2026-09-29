// Writing Ion binary to an asynchronous byte sink.

///|
/// Write `values` to `writer` as an Ion binary datagram: the version marker, a
/// local symbol table when one is needed, and then the values. Only the symbol
/// table is held in memory; the values are encoded and written in turn.
///
/// A buffered writer is flushed by its owner, not here.
pub async fn write_all(
  writer : &@io.Writer,
  values : Array[@ion.IonValue],
) -> Unit {
  let symbols = @binary.symbols_for_values(values)
  writer.write(@binary.binary_version_marker())
  match @binary.local_symbol_table(symbols) {
    Some(table) => writer.write(table)
    None => ()
  }
  for value in values {
    writer.write(@binary.encode_value(value, symbols))
  }
}

///|
/// A writer that encodes Ion values as an Ion binary datagram to an async byte
/// sink, one value at a time, without knowing the values ahead.
///
/// It writes the version marker first. A value that uses symbol texts the
/// stream has not declared is preceded by a local symbol table that appends
/// them (`imports: $ion_symbol_table`), so each text is declared once. A
/// value holding a symbol known only by an ID above the IDs reserved so far
/// starts a new context: a version marker and a table that reserves the IDs
/// up to it with unknown text.
struct BinaryWriter {
  sink : &@io.Writer
  mut symbols : @ion.SymbolTable
  /// The highest symbol ID reserved with unknown text in this context.
  mut reserved : Int
  mut started : Bool
}

///|
/// A writer to `sink`.
pub fn BinaryWriter::new(sink : &@io.Writer) -> BinaryWriter {
  { sink, symbols: @ion.SymbolTable::system(), reserved: 9, started: false, }
}

///|
/// Write `value`, with whatever marker and symbol table it needs first. A
/// buffered sink is flushed by its owner, not here.
pub async fn BinaryWriter::write(
  self : BinaryWriter,
  value : @ion.IonValue,
) -> Unit {
  let out : Array[Byte] = []
  let highest = @ion.highest_symbol_id([value])
  if !self.started || highest > self.reserved {
    // A new context: the marker resets the reader's symbol table.
    out.append(@binary.binary_version_marker().to_array())
    self.symbols = @ion.SymbolTable::system()
    self.reserved = 9
    if highest > 9 {
      self.symbols.reserve(highest - 9)
      self.reserved = highest
      match @binary.local_symbol_table(self.symbols) {
        Some(table) => out.append(table.to_array())
        None => ()
      }
    }
    self.started = true
  }
  let added : Array[String] = []
  for text in @binary.symbols_for_values([value]).locals() {
    match text {
      Some(text) if self.symbols.find(text) is None => {
        ignore(self.symbols.intern(text))
        added.push(text)
      }
      _ => ()
    }
  }
  if !added.is_empty() {
    let table = @ion.IonValue::from_fields([
      @ion.Field::new("imports", @ion.IonValue::symbol("$ion_symbol_table")),
      @ion.Field::new(
        "symbols",
        @ion.IonValue::list(added.map(@ion.IonValue::string)),
      ),
    ]).with_annotations([@ion.SymbolToken::new("$ion_symbol_table")])
    out.append(@binary.encode_value(table, self.symbols).to_array())
  }
  out.append(@binary.encode_value(value, self.symbols).to_array())
  self.sink.write(Bytes::from_array(out))
}
