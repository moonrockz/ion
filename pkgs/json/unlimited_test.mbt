///|
test "JSON text accepts deep nesting and optional scoped fuel" {
  let source = "[".repeat(10000) + "1" + "]".repeat(10000)
  let value = @json.read_json(source)
  assert_eq(
    value.fold_up(scalar=_ => 0, container=(_, children) => children[0].1 + 1),
    10000,
  )
  let exhausted = try
    @json.read_json(source, fuel=Limited(@core.Budget(2)))
  catch {
    @core.IonError::FuelExhausted(
      operation=JsonRead,
      location=TextOffset(2),
      ..
    ) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
  ignore(@json.read_json("[[1],[2],{}]", fuel=Limited(@core.Budget(2))))
}

///|
test "JSON container parsing agrees with core on generated documents" {
  for
    value in @testkit.gen_json(max_depth=6, max_width=4).samples(
      count=300,
      size=8,
    ) {
    let source = value.stringify()
    assert_true(
      @json.read_json(source).equals(@json.to_ion(@cjson.parse(source))),
    )
  }
  assert_eq(
    @text.write_ion(@json.read_json("{\"a\":1,\"b\":2,\"a\":3}")),
    "{a: 3, b: 2}",
  )
}

///|
test "JSON container parsing rejects malformed grammar and scalar tokens" {
  for
    source in [
      "", "[", "{", "[1,]", "{\"a\":1,}", "[1 2]", "{a:1}", "{\"a\" 1}", "[truefalse]",
      "[01]", "1 2", "[/*x*/1]", "[nan]", "[+1]", "[.1]", "[1e+]", "[\"\\uD800\"]",
      "[\"\\q\"]",
    ] {
    let syntax = try @json.read_json(source) catch {
      @core.IonError::Syntax(_) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(syntax, msg=source)
  }
}
