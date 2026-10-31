// The JSON package re-exports the bridges of the core package, for callers
// that already work with JSON. Derived types are shown in the core package's
// tests, where `@json` names core JSON.

///|
test "the JSON package re-exports the bridges" {
  let original : Map[String, Array[Int32]] = { "a": [1, 2], "b": [] }
  let value : @json.Ion = @json.to_ion_via_json(original)
  inspect(@text.write_ion(value), content="{a: [1, 2], b: []}")
  let back : Map[String, Array[Int32]] = @json.from_ion_via_json(value)
  assert_eq(back, original)
}

///|
test "the JSON package re-exports FromIon and FromIonError" {
  let value = @text.read_ion("[1, x]")
  let error = try (@json.FromIon::from_ion(value) : Array[Int32]) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  let error : @json.FromIonError = error
  assert_eq(error.message(), "$[1]: expected int, found symbol")
}
