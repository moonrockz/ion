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
  let symbols = @binary.SymbolTable::for_values(values)
  writer.write(@binary.binary_version_marker())
  match @binary.local_symbol_table(symbols) {
    Some(table) => writer.write(table)
    None => ()
  }
  for value in values {
    writer.write(@binary.encode_value(value, symbols))
  }
}
