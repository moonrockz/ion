///|
test "recursive schemas validate deep values and honor optional fuel" {
  let schema = @schema.Schema::load_from_text(
    "$ion_schema_2_0 type::{name:tree,any_of:[int,{type:list,element:tree}]}",
  )
  let mut value = @ion.IonValue::int(1)
  for _ in 0..<2000 {
    value = @ion.IonValue::list([value])
  }
  assert_true(schema.is_valid("tree", value))
  let exhausted = try
    schema.validate("tree", value, fuel=Limited(@ion.Budget(10)))
  catch {
    @ion.IonError::FuelExhausted(
      operation=SchemaValidate,
      location=ValuePath(_),
      ..
    ) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
  assert_true(schema.is_valid("tree", @text.read_ion("[1,[2],3]")))
}

///|
test "logical validation propagates fuel exhaustion instead of returning validity" {
  for
    body in [
      "not:{not:int}", "any_of:[int,string]", "one_of:[int,string]", "all_of:[int,int]",
    ] {
    let schema = @schema.Schema::load_from_text(
      "$ion_schema_2_0 type::{name:t,\{body}}",
    )
    let exhausted = try
      schema.is_valid("t", @ion.IonValue::int(1), fuel=Limited(@ion.Budget(1)))
    catch {
      @ion.IonError::FuelExhausted(operation=SchemaValidate, ..) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(exhausted)
    let document_exhausted = try
      schema.is_valid_document("t", [], fuel=Limited(@ion.Budget(1)))
    catch {
      @ion.IonError::FuelExhausted(operation=SchemaValidate, ..) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(document_exhausted)
  }
}

///|
test "regex compilation reports its own fuel operation" {
  let exhausted = try
    @schema.Regex::new("a", fuel=Limited(@ion.Budget(1)))
  catch {
    @ion.IonError::FuelExhausted(
      operation=RegexCompile,
      location=RegexInstruction(_),
      ..
    ) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
test "schema imports are stack safe and share caller fuel" {
  let documents : Map[String, Array[@ion.IonValue]] = Map([])
  for index in 0..<2000 {
    documents[index.to_string()] = @text.read_ion_datagram(
      "$ion_schema_2_0 schema_header::{imports:[{id:\"\{index + 1}\",type:t,as:next}]} type::{name:t,type:next} schema_footer::{}",
    )
  }
  documents["2000"] = @text.read_ion_datagram(
    "$ion_schema_2_0 type::{name:t,type:int}",
  )
  let resolver = (id : String) => {
    match documents.get(id) {
      Some(values) => values
      None => raise @ion.IonError::DataModel("missing schema " + id)
    }
  }
  let root = @text.read_ion_datagram(
    "$ion_schema_2_0 schema_header::{imports:[{id:\"0\",type:t}]} schema_footer::{}",
  )
  assert_true(
    @schema.Schema::load(root, resolver~).is_valid("0#t", @ion.IonValue::int(1)),
  )
  let exhausted = try
    @schema.Schema::load(root, resolver~, fuel=Limited(@ion.Budget(10)))
  catch {
    @ion.IonError::FuelExhausted(
      operation=SchemaImport,
      location=SchemaId(_),
      ..
    ) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
test "schema regex loading forwards finite fuel to nested groups" {
  let source = "$ion_schema_2_0 type::{name:t,regex:\"" +
    "(".repeat(20) +
    "a" +
    ")".repeat(20) +
    "\"}"
  let exhausted = try
    @schema.Schema::load_from_text(source, fuel=Limited(@ion.Budget(3)))
  catch {
    @ion.IonError::FuelExhausted(operation=RegexParse, ..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
test "regex groups use stack-safe parsing and optional fuel" {
  let source = "(".repeat(10000) + "a" + ")".repeat(10000)
  assert_true(@schema.Regex::new(source).matches("a"))
  let exhausted = try
    @schema.Regex::new(source, fuel=Limited(@ion.Budget(2)))
  catch {
    @ion.IonError::FuelExhausted(
      operation=RegexParse,
      location=CharacterOffset(_),
      ..
    ) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
test "schema loading accepts deeply nested inline types with optional fuel" {
  let source = "$ion_schema_2_0 type::{name:t,type:" +
    "{type:".repeat(2000) +
    "int" +
    "}".repeat(2000) +
    "}"
  let schema = @schema.Schema::load_from_text(source)
  assert_true(schema.is_valid("t", @ion.IonValue::int(1)))
  let values = @text.read_ion_datagram(source)
  let exhausted = try
    @schema.Schema::load(values, fuel=Limited(@ion.Budget(10)))
  catch {
    @ion.IonError::FuelExhausted(operation=SchemaLoad, ..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}
