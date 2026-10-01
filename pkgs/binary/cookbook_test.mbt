///|
test "cookbook transcoding preserves annotations decimal scale and typed nulls" {
  let input =
    #|order::{id: 7, total: 19.990, placed: 2024-05-01T10:00Z, note: null.string}
    #|42
  let values = @text.read_ion_datagram(input)
  let bytes = @binary.write_binary(values)
  let decoded = @binary.read_binary(bytes)
  assert_eq(decoded.length(), 2)
  for index, value in values {
    assert_true(decoded[index].equals(value))
  }
  let rewritten = @text.write_all(decoded)
  let reread = @text.read_ion_datagram(rewritten)
  assert_true(reread[0].equals(values[0]))
  assert_true(reread[1].equals(values[1]))
}
