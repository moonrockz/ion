// The test kit is test code for the other packages, so its own tests check
// that each helper builds what its name says.

///|
test "deep_value nests the requested number of containers" {
  let shapes : Array[@testkit.DeepShape] = [
    List,
    Sexp,
    Struct,
    AnnotatedList,
    Mixed,
  ]
  for shape in shapes {
    let (leaf, depth) = @testkit.innermost(@testkit.deep_value(shape, 5))
    assert_eq(depth, 5)
    assert_true(leaf.kind() is Int(_))
  }
}

///|
test "deep_value spells each shape as its name says" {
  inspect(@text.write_ion(@testkit.deep_value(List, 2)), content="[[1]]")
  inspect(@text.write_ion(@testkit.deep_value(Sexp, 2)), content="((1))")
  inspect(
    @text.write_ion(@testkit.deep_value(Struct, 2)),
    content="{name: {name: 1}}",
  )
  inspect(
    @text.write_ion(@testkit.deep_value(AnnotatedList, 2)),
    content="name::[name::[1]]",
  )
  inspect(
    @text.write_ion(@testkit.deep_value(Mixed, 4)),
    content="[{name: ([1])}]",
  )
}

///|
test "deep_value builds and frees 100,000 levels on every target" {
  let shapes : Array[@testkit.DeepShape] = [List, Struct, Mixed]
  for shape in shapes {
    let (_, depth) = @testkit.innermost(@testkit.deep_value(shape, 100_000))
    assert_eq(depth, 100_000)
  }
}

///|
test "reference_equals follows the Ion data model" {
  fn read(text : String) -> @ion.IonValue raise {
    @text.read_ion(text)
  }
  assert_true(
    @testkit.reference_equals(read("{a: 1, b: 2}"), read("{b: 2, a: 1}")),
  )
  assert_true(@testkit.reference_equals(read("nan"), read("nan")))
  assert_true(!@testkit.reference_equals(read("0e0"), read("-0e0")))
  assert_true(!@testkit.reference_equals(read("1.0"), read("1.00")))
  assert_true(
    !@testkit.reference_equals(read("{a: 1, a: 1}"), read("{a: 1, a: 2}")),
  )
  assert_true(!@testkit.reference_equals(read("x::1"), read("1")))
  assert_true(!@testkit.reference_equals(read("[]"), read("()")))
}

///|
test "count_values counts every value, containers included" {
  assert_eq(
    @testkit.count_values(@text.read_ion("[1, {a: (2 3)}, x::null.list]")),
    7,
  )
}

///|
/// Record in `found` every Ion type that occurs in `value`, every typed null,
/// "annotated" when a value has annotations, "duplicate field" when a struct
/// repeats a name, and "symbol ID" when a symbol value has no text.
fn features(value : @ion.IonValue, found : Map[String, Bool]) -> Unit {
  found.set(value.ion_type().to_text(), true)
  if value.is_null() {
    found.set("null." + value.ion_type().to_text(), true)
  }
  if value.has_annotations() {
    found.set("annotated", true)
  }
  match value.kind() {
    List(items) | Sexp(items) =>
      for item in items {
        features(item, found)
      }
    Struct(fields) => {
      let names : Map[String, Bool] = Map([])
      for field in fields {
        let name = field.name().text().unwrap_or("$")
        if names.contains(name) {
          found.set("duplicate field", true)
        }
        names.set(name, true)
        features(field.value(), found)
      }
    }
    Symbol(token) => if token.text() is None { found.set("symbol ID", true) }
    _ => ()
  }
}

///|
test "gen_value covers every Ion type, typed nulls, annotations and duplicate fields" {
  let found : Map[String, Bool] = Map([])
  for
    value in @testkit.gen_value(max_depth=4, max_width=4).samples(
      count=500,
      size=8,
    ) {
    features(value, found)
  }
  for type_ in @ion.IonType::all() {
    assert_true(
      found.contains(type_.to_text()),
      msg="missing \{type_.to_text()}",
    )
  }
  for
    name in [
      "null.struct", "null.int", "annotated", "duplicate field", "symbol ID",
    ] {
    assert_true(found.contains(name), msg="missing \{name}")
  }
}

///|
test "gen_value without unknown symbols writes only symbols with text" {
  let found : Map[String, Bool] = Map([])
  for
    value in @testkit.gen_value(max_depth=4, max_width=4, unknown_symbols=false).samples(
      count=300,
      size=8,
    ) {
    features(value, found)
  }
  assert_true(!found.contains("symbol ID"))
}

///|
test "change_one_leaf always makes an unequal value" {
  let values = @testkit.gen_value(max_depth=4, max_width=3).samples(
    count=200,
    size=8,
  )
  for index, value in values {
    let changed = @testkit.change_one_leaf(value, index)
    assert_true(
      !@testkit.reference_equals(value, changed),
      msg=@text.write_ion(value),
    )
  }
}

///|
test "reverse_fields keeps an equal value" {
  for
    value in @testkit.gen_value(max_depth=4, max_width=3).samples(
      count=200,
      size=8,
    ) {
    assert_true(
      @testkit.reference_equals(value, @testkit.reverse_fields(value)),
      msg=@text.write_ion(value),
    )
  }
}

///|
test "gen_json produces arrays, objects and every scalar" {
  let kinds : Map[String, Bool] = Map([])
  for
    json in @testkit.gen_json(max_depth=3, max_width=3).samples(
      count=300,
      size=8,
    ) {
    let name = match json {
      Null => "null"
      True | False => "bool"
      Number(_, ..) => "number"
      String(_) => "string"
      Array(_) => "array"
      Object(_) => "object"
    }
    kinds.set(name, true)
  }
  assert_eq(kinds.length(), 6)
}

///|
test "near_misses change structure, not only leaves" {
  let value = @text.read_ion("a::[1, 2, {f: x::3, g: (4 5)}]")
  let misses = @testkit.near_misses(value)
  let texts = misses.map(miss => @text.write_ion(miss))
  assert_true(texts.contains("a::[2, 1, {f: x::3, g: (4 5)}]"), msg="swap")
  assert_true(texts.contains("a::(1 2 {f: x::3, g: (4 5)})"), msg="kind")
  assert_true(texts.contains("[1, 2, {f: x::3, g: (4 5)}]"), msg="annotation")
  assert_true(texts.contains("a::[1, 2, {f_: x::3, g: (4 5)}]"), msg="field")
  for miss in misses {
    assert_true(
      !@testkit.reference_equals(value, miss),
      msg=@text.write_ion(miss),
    )
  }
}

///|
test "gen_value with imported symbols makes symbols from a shared table" {
  let mut imported = 0
  for
    value in @testkit.gen_value(max_depth=3, max_width=3, imported_symbols=true).samples(
      count=300,
      size=8,
    ) {
    if value.has_imported_symbols() {
      imported += 1
    }
  }
  assert_true(imported > 0)
}
