///|
test "Ion constructor converts JSON to the existing Ion data model" {
  let value : @core.IonValue = @json.Ion(Json({ "items": [1, 2] }))
  assert_eq(@text.write_ion(value), "{items: [1, 2]}")
}

///|
test "JSON and core expose the same Ion constructor" {
  let json = Json::number(1.5, repr="1.500")
  assert_true(@json.Ion(json).equals(@core.Ion(json)))
  assert_eq(@text.write_ion(@json.Ion(true)), "true")
}

///|
#warnings("-deprecated")
test "deprecated to_ion preserves the existing JSON conversion" {
  let json = Json({ "items": [1, 2] })
  assert_true(@json.to_ion(json).equals(@json.Ion(json)))
}
