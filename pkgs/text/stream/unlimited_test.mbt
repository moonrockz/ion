///|
async test "text value and event streams honor caller fuel" {
  let source = @io.MemoryReader(async fn(writer) { writer.write(b"[[[1]]]") })
  defer source.close()
  let reader = @stream.TextReader::new(source, fuel=Limited(@ion.Budget(2)))
  let exhausted = try reader.next() catch {
    @ion.IonError::FuelExhausted(operation=TextRead, ..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
  let event_source = @io.MemoryReader(async fn(writer) {
    writer.write(b"[[[1]]]")
  })
  defer event_source.close()
  let events = @stream.TextEventReader::new(
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
