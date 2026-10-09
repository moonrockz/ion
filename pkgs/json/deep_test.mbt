// The JSON conversions handle values nested far deeper than the readers
// accept.

///|
let deep : Int = 100_000

///|
/// How many one-child arrays or one-member objects lead to the innermost
/// JSON value, and that value. A loop, so it works at any depth.
fn json_innermost(json : Json) -> (Json, Int) {
  let mut current = json
  let mut depth = 0
  while true {
    match current {
      Array([child]) => current = child
      Object(members) if members.length() == 1 =>
        for _, child in members {
          current = child
        }
      _ => break
    }
    depth += 1
  }
  (current, depth)
}

///|
#skip("ion-dql.8: to_json recurses once per level")
test "to_json converts values 100,000 levels deep" {
  let shapes : Array[@testkit.DeepShape] = [
    List,
    Sexp,
    Struct,
    AnnotatedList,
    Mixed,
  ]
  for shape in shapes {
    let (inner, depth) = json_innermost(
      @json.to_json(@testkit.deep_value(shape, deep)),
    )
    assert_eq(depth, deep)
    assert_true(inner is Number(_, ..))
  }
}

///|
#skip("ion-dql.8: to_json recurses once per level")
test "write_json writes values 100,000 levels deep" {
  let list = @json.write_json(@testkit.deep_value(List, deep))
  assert_true(list == "[".repeat(deep) + "1" + "]".repeat(deep))
  let object = @json.write_json(@testkit.deep_value(Struct, deep))
  assert_true(object == "{\"name\":".repeat(deep) + "1" + "}".repeat(deep))
}

///|
#skip("ion-dql.8: to_ion recurses once per level")
test "to_ion converts JSON 100,000 levels deep" {
  let mut array = Json::number(1.0)
  let mut object = Json::number(1.0)
  for _ in 0..<deep {
    array = Json::array([array])
    object = Json::object(Map([("name", object)]))
  }
  for json in [array, object] {
    let (inner, depth) = @testkit.innermost(@json.to_ion(json))
    assert_eq(depth, deep)
    assert_true(inner.kind() is Int(_))
  }
}
