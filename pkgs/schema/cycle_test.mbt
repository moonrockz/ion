///|
test "direct cyclic aliases terminate value and document validation" {
  let schema = @schema.Schema::load_from_text(
    "$ion_schema_1_0 type::{name:a,type:b} type::{name:b,type:a}",
  )
  let violations = schema.validate("a", @ion.IonValue::int(1))
  assert_eq(violations.length(), 1)
  assert_eq(violations[0].path(), "$")
  assert_true(violations[0].message().contains("cyclic schema type reference"))
  assert_false(schema.is_valid_document("a", []))
}

///|
fn assert_cycle(
  violations : Array[@schema.Violation],
  path : String,
) -> Unit raise {
  assert_false(violations.is_empty())
  for violation in violations {
    assert_eq(violation.path(), path)
    assert_true(violation.message().contains("cyclic schema type reference"))
  }
}

///|
test "self references and logical cycles cannot be inverted into success" {
  for version in ["$ion_schema_1_0", "$ion_schema_2_0"] {
    for
      body in [
        "type:a", "all_of:[a]", "any_of:[int,a]", "one_of:[int,a]", "not:a", "type:{any_of:[{not:a},int]}",
      ] {
      let schema = @schema.Schema::load_from_text(
        "\{version} type::{name:a,\{body}}",
      )
      assert_cycle(schema.validate("a", @ion.IonValue::bool(true)), "$")
      assert_cycle(schema.validate_document("a", []), "$")
    }
  }
}

///|
test "nullable references terminate cycles but retain their null branch" {
  for
    (version, nullable) in [
      ("$ion_schema_1_0", "nullable"),
      ("$ion_schema_2_0", "$null_or"),
    ] {
    let schema = @schema.Schema::load_from_text(
      "\{version} type::{name:a,type:\{nullable}::a}",
    )
    assert_cycle(schema.validate("a", @ion.IonValue::int(1)), "$")
    assert_cycle(schema.validate_document("a", []), "$")
    assert_true(schema.is_valid("a", @ion.IonValue::untyped_null()))
  }
}

///|
test "cycles report the nested value path through every container constraint" {
  for
    (constraint, value, path) in [
      ("element:a", "[1]", "$[0]"),
      ("fields:{child:a}", "{child:1}", "$.child"),
      ("ordered_elements:[a]", "[1]", "$[0]"),
      ("field_names:a", "{child:1}", "$.(field name)"),
      ("annotations:a", "tag::1", "$::"),
    ] {
    let schema = @schema.Schema::load_from_text(
      "$ion_schema_2_0 type::{name:a,type:a} type::{name:outer,\{constraint}}",
    )
    assert_cycle(schema.validate("outer", @text.read_ion(value)), path)
  }
  let document = @schema.Schema::load_from_text(
    "$ion_schema_2_0 type::{name:a,type:a} type::{name:doc,type:document,ordered_elements:[a]}",
  )
  assert_cycle(
    document.validate_document("doc", [@ion.IonValue::int(1)]),
    "$[0]",
  )
}

///|
test "annotation transformations cannot manufacture endless fresh cycle values" {
  let schema = @schema.Schema::load_from_text(
    "$ion_schema_2_0 type::{name:a,annotations:a}",
  )
  let violations = schema.validate("a", @text.read_ion("tag::1"))
  assert_eq(violations.length(), 1)
  assert_true(
    violations[0].message().contains("cyclic schema type reference: a"),
  )
}

///|
test "productive recursive types consume children and release sibling frames" {
  let schema = @schema.Schema::load_from_text(
    "$ion_schema_2_0 type::{name:tree,any_of:[int,{type:list,element:tree}]} type::{name:node,type:struct,fields:{child:{type:node,occurs:range::[0,max]}}} type::{name:sexpression_tree,ordered_elements:[symbol,{type:sexpression_tree,occurs:range::[0,max]}]} type::{name:ints,type:int} type::{name:twice,all_of:[ints,ints]} type::{name:roots,type:document,element:tree}",
  )
  for value in ["1", "[]", "[1,[2,[3]],1,[2,[3]]]"] {
    assert_true(schema.is_valid("tree", @text.read_ion(value)))
  }
  assert_false(schema.is_valid("tree", @text.read_ion("[1,[\"bad\"]]")))
  assert_true(
    schema.is_valid("node", @text.read_ion("{child:{child:{}},child:{}}")),
  )
  assert_false(schema.is_valid("node", @text.read_ion("{child:{child:1}}")))
  assert_true(
    schema.is_valid("sexpression_tree", @text.read_ion("(a (b (c)) (b (c)))")),
  )
  assert_false(schema.is_valid("sexpression_tree", @text.read_ion("(a (b c))")))
  assert_true(schema.is_valid("twice", @ion.IonValue::int(1)))
  assert_true(
    schema.is_valid_document(
      "roots",
      @text.read_ion_datagram("[1,[2]] [1,[2]]"),
    ),
  )
}

///|
test "cycles through imported aliases use resolved type identities" {
  let resolver = (id : String) => {
    @text.read_ion_datagram(
      match id {
        "a" =>
          "$ion_schema_2_0 schema_header::{imports:[{id:\"b\",type:b}]} type::{name:a,type:b} schema_footer::{}"
        "b" =>
          "$ion_schema_2_0 schema_header::{imports:[{id:\"a\",type:a}]} type::{name:b,type:a} schema_footer::{}"
        _ => ""
      },
    )
  }
  let schema = @schema.Schema::load_from_text(
    "$ion_schema_2_0 schema_header::{imports:[{id:\"a\",type:a,as:alias}]} type::{name:t,type:alias} schema_footer::{}",
    resolver~,
  )
  assert_cycle(schema.validate("t", @ion.IonValue::int(1)), "$")
  assert_cycle(schema.validate_document("t", []), "$")
}

///|
test "finite any_of branches prove validity independently of cyclic alternatives" {
  let schema = @schema.Schema::load_from_text(
    "$ion_schema_2_0 type::{name:cycle,type:cycle} type::{name:first,any_of:[cycle,int]} type::{name:last,any_of:[int,cycle]} type::{name:negated,not:cycle} type::{name:exact,one_of:[cycle,int]} type::{name:combined,all_of:[cycle,{any_of:[cycle,int]}]} type::{name:doc,any_of:[cycle,document]} type::{name:not_doc,not:cycle} type::{name:one_doc,one_of:[cycle,document]}",
  )
  for name in ["first", "last"] {
    assert_true(schema.is_valid(name, @ion.IonValue::int(1)))
    assert_cycle(schema.validate(name, @ion.IonValue::bool(true)), "$")
  }
  for name in ["negated", "exact", "combined"] {
    assert_cycle(schema.validate(name, @ion.IonValue::int(1)), "$")
  }
  assert_true(schema.is_valid_document("doc", []))
  for name in ["not_doc", "one_doc"] {
    assert_cycle(schema.validate_document(name, []), "$")
  }
  // A validation call owns its frames and diagnostics, even after failure.
  assert_false(schema.is_valid("first", @ion.IonValue::bool(true)))
  assert_true(schema.is_valid("first", @ion.IonValue::int(1)))
}
