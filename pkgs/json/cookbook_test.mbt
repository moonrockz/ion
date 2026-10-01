///|
test "cookbook JSON export drops annotations and changes symbols and nulls" {
  let value = @text.read_ion(
    "order::{id: 7, status: shipped, note: null.string}",
  )
  let output = @json.write_json(value)
  assert_eq(output, "{\"id\":7,\"status\":\"shipped\",\"note\":null}")
  let imported = @json.read_json(output)
  assert_true(!imported.equals(value))
  assert_eq(
    @text.write_ion(imported),
    "{id: 7, status: \"shipped\", note: null}",
  )
}
