///|
async test "binary value and event streams honor caller fuel" {
  let bytes = @binary.write_binary_value(@text.read_ion("[[[1]]]"))
  let source = @io.MemoryReader(async fn(writer) { writer.write(bytes) })
  defer source.close()
  let reader = @stream.BinaryReader::new(source, fuel=Limited(@ion.Budget(2)))
  let exhausted = try reader.next() catch {
    @ion.IonError::FuelExhausted(operation=BinaryRead, ..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
  let event_source = @io.MemoryReader(async fn(writer) { writer.write(bytes) })
  defer event_source.close()
  let events = @stream.BinaryEventReader::new(
    event_source,
    fuel=Limited(@ion.Budget(2)),
  )
  ignore(events.next())
  let event_exhausted = try events.next() catch {
    @ion.IonError::FuelExhausted(..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(event_exhausted)
}
