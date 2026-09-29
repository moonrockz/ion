// Runs the ISL 2.0 test data from https://github.com/amazon-ion/ion-schema-tests,
// checked out as the `tests/ion-schema-tests` submodule, as its README
// describes. Each file is a schema with `$test::{...}` structs among its types:
//
// - the file's schema (its values other than the `$test` structs) must load;
// - `type` with `should_accept_as_valid` and `should_reject_as_invalid`: each
//   value must match the type, or not;
// - `valid_schemas` and `invalid_schemas`: each schema document, given as an
//   S-expression, must load, or not;
// - `invalid_types`: each type definition must be rejected.
//
// A case has one of three outcomes. It passes; it fails, when the answer is
// wrong; or it is unsupported, when it needs a construct this implementation
// does not implement (the loader raised `IonError::Unsupported`, or a value is
// an Ion document, `document::(...)`). A schema that is rejected as
// unsupported does not count as correctly rejected.
//
// `schema_skipped` lists the files this implementation does not pass yet, each
// with the reason. A listed file may have unsupported cases, but not wrong
// answers, which fail the test wherever they are, unless listed by case in
// `schema_known_failures`. A listed file whose cases all pass fails the test,
// and so does a known failure that no longer fails, so the lists stay
// accurate. ISL 1.0 is not implemented, and not run.

///|
/// The ISL 2.0 test data, relative to the module root.
let schema_root : String = "tests/ion-schema-tests/ion_schema_2_0"

///|
/// Files this implementation does not pass yet, by path under `schema_root`,
/// with what they need that is not supported.
let schema_skipped : Map[String, String] = Map([
  ("imports/cross_version/isl_1_0_importing_isl_2_0.isl", "Ion Schema 1.0"),
  ("imports/cross_version/isl_1_0_schema.isl", "Ion Schema 1.0"),
  ("imports/cross_version/isl_2_0_importing_isl_1_0.isl", "Ion Schema 1.0"),
])

///|
/// Cases whose answer is wrong, with the reason. A key is a case ID, or the
/// ID of a `$test` struct (`<file> $test[<index>]`) for all of its cases.
/// Most are schemas that ISL 2.0 does not allow but the loader accepts.
let schema_known_failures : Map[String, String] = Map([])

///|
/// The `schema_known_failures` key that covers a case, if any.
fn known_failure(id : String) -> String? {
  if schema_known_failures.contains(id) {
    return Some(id)
  }
  schema_known_failures.keys().find_first(key => id.has_prefix(key + " "))
}

///|
/// How one case went.
priv enum SchemaOutcome {
  SchemaPassed
  SchemaFailed(String)
  SchemaUnsupported(String)
}

///|
/// Resolve a schema import: the test data names each schema by its path
/// under `schema_root`.
fn resolve_import(id : String) -> Array[@ion.IonValue] raise @ion.IonError {
  read_file("\{schema_root}/\{id}") catch {
    @ion.IonError::DataModel(_) as error => raise error
    error =>
      raise @ion.IonError::DataModel("cannot read '\{id}': \{describe(error)}")
  }
}

///|
/// The outcome of loading `values` as a schema that should load (`valid`) or
/// should not, and the schema when it loads.
fn load_outcome(
  values : Array[@ion.IonValue],
  valid~ : Bool,
) -> (SchemaOutcome, @schema.Schema?) {
  let schema = try @schema.Schema::load(values, resolver=resolve_import) catch {
    @ion.IonError::Unsupported(message) =>
      return (SchemaUnsupported(message), None)
    error =>
      return (
        if valid {
          SchemaFailed("does not load: \{describe(error)}")
        } else {
          SchemaPassed
        },
        None,
      )
  } noraise {
    schema => schema
  }
  if valid {
    (SchemaPassed, Some(schema))
  } else {
    (SchemaFailed("loads, but should not"), Some(schema))
  }
}

///|
/// Whether a value has the annotation `name`.
fn annotated(value : @ion.IonValue, name : String) -> Bool {
  value.annotations().iter().any(token => token.text() == Some(name))
}

///|
/// The field `name` of a struct.
fn field_of(value : @ion.IonValue, name : String) -> @ion.IonValue? {
  match value.kind() {
    Struct(fields) =>
      fields
      .iter()
      .find_first(field => field.name().text() == Some(name))
      .map(field => field.value())
    _ => None
  }
}

///|
/// The elements of a list or S-expression.
fn elements(value : @ion.IonValue) -> Array[@ion.IonValue] {
  match value.kind() {
    List(items) | Sexp(items) => items
    _ => []
  }
}

///|
/// The types of a schema document, each loaded on its own, so that one
/// unsupported type does not hide the others, and why the others did not load.
priv struct LoadedTypes {
  schema : @schema.Schema
  /// Why a type cannot be used, by name: it did not load, or it refers to a
  /// type that did not.
  unusable : Map[String, String]
}

///|
/// The names of the schema types a constraint refers to, at any depth.
fn references(constraint : @schema.Constraint, out : Array[String]) -> Unit {
  match constraint {
    TypeRef(name) => out.push(name)
    NullOr(inner)
    | Not(inner)
    | Element(inner)
    | FieldNames(inner)
    | Annotations(inner) => references(inner, out)
    AllOf(items) | AnyOf(items) | OneOf(items) =>
      for item in items {
        references(item, out)
      }
    OrderedElements(slots) =>
      for slot in slots {
        references(slot.0, out)
      }
    Fields(fields) =>
      for field in fields {
        references(field.ty, out)
      }
    _ => ()
  }
}

///|
/// Load each type definition among `definitions` on its own.
fn load_types(definitions : Array[@ion.IonValue]) -> LoadedTypes {
  let whole = try
    @schema.Schema::load(definitions, resolver=resolve_import)
  catch {
    _ => None
  } noraise {
    schema => Some(schema)
  }
  if whole is Some(schema) {
    return { schema, unusable: Map([]), }
  }
  // Load each type with the version markers and the header, which decide how
  // it loads, and an empty stand-in for each other type of the file, so its
  // references resolve. A type that refers to an unusable type is unusable.
  let prelude = definitions.filter(value => {
    annotated(value, "schema_header") ||
    (
      value.kind() is Symbol(token) &&
      token.text().unwrap_or("").has_prefix("$ion_schema_")
    )
  })
  let name_of = (definition : @ion.IonValue) => {
    match field_of(definition, "name").map(value => value.kind()) {
      Some(Symbol(token)) => token.text().unwrap_or("?")
      _ => "?"
    }
  }
  let names = definitions.filter(value => annotated(value, "type")).map(name_of)
  let loaded : Array[@schema.TypeDefinition] = []
  let unusable : Map[String, String] = Map([])
  for definition in definitions {
    if !annotated(definition, "type") {
      continue
    }
    let name = name_of(definition)
    let stand_ins = names
      .filter(other => other != name)
      .map(other => {
        @ion.IonValue::from_fields([
          @ion.Field::new("name", @ion.IonValue::symbol(other)),
        ]).with_annotations([@ion.SymbolToken::new("type")])
      })
    let types = try
      @schema.Schema::load(
        prelude + [definition] + stand_ins,
        resolver=resolve_import,
      ).types()
    catch {
      error => {
        unusable[name] = "type \{name} does not load: \{describe(error)}"
        continue
      }
    } noraise {
      types => types
    }
    // Keep the type and the imported types, but not the stand-ins.
    for loaded_type in types {
      if loaded_type.name() == name ||
        (
          loaded_type.name().contains("#") &&
          !loaded.iter().any(other => other.name() == loaded_type.name())
        ) {
        loaded.push(loaded_type)
      }
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for definition in loaded {
      if unusable.contains(definition.name()) {
        continue
      }
      let refs : Array[String] = []
      for constraint in definition.constraints() {
        references(constraint, refs)
      }
      for name in refs {
        if unusable.contains(name) {
          unusable[definition.name()] = "type \{definition.name()} refers to \{name}, which is not usable"
          changed = true
          break
        }
      }
    }
  }
  { schema: @schema.Schema::from_types(loaded), unusable, }
}

///|
/// Run one `$test` struct, adding an outcome for each of its cases.
fn run_schema_test(
  test_case : @ion.IonValue,
  types : LoadedTypes,
  id : String,
  outcomes : Array[(String, SchemaOutcome)],
) -> Unit {
  let description = field_of(test_case, "description")
    .map(value => {
      match value.kind() {
        String(text) => text
        _ => ""
      }
    })
    .unwrap_or("")
  match field_of(test_case, "type") {
    Some(type_value) => {
      let type_name = match type_value.kind() {
        Symbol(token) => token.text().unwrap_or("")
        _ => ""
      }
      for
        pair in [
          ("should_accept_as_valid", true),
          ("should_reject_as_invalid", false),
        ] {
        let (key, accept) = pair
        let values = field_of(test_case, key).map(elements).unwrap_or([])
        for index, value in values {
          let case_id = "\{id} \{type_name} \{key}[\{index}]"
          let outcome = match types.unusable.get(type_name) {
            Some(reason) => SchemaUnsupported(reason)
            None => {
              // `document::(...)` stands for a document of those values.
              let valid = if annotated(value, "document") {
                types.schema.is_valid_document(type_name, elements(value))
              } else {
                types.schema.is_valid(type_name, value)
              }
              if valid == accept {
                SchemaPassed
              } else {
                SchemaFailed(
                  if accept {
                    "rejects \{show([value])}"
                  } else {
                    "accepts \{show([value])}"
                  },
                )
              }
            }
          }
          outcomes.push((case_id, outcome))
        }
      }
    }
    None => ()
  }
  for pair in [("valid_schemas", true), ("invalid_schemas", false)] {
    let (key, valid) = pair
    for index, document in field_of(test_case, key).map(elements).unwrap_or([]) {
      let (outcome, _) = load_outcome(elements(document), valid~)
      outcomes.push(("\{id} \{description} \{key}[\{index}]", outcome))
    }
  }
  for
    index, definition in field_of(test_case, "invalid_types")
    .map(elements)
    .unwrap_or([]) {
    // Name the type, unless it names itself, and load it in a schema of its own.
    let fields = match definition.kind() {
      Struct(fields) => fields
      _ => []
    }
    let named = if fields
      .iter()
      .any(field => field.name().text() == Some("name")) {
      fields
    } else {
      [@ion.Field::new("name", @ion.IonValue::symbol("invalid_type"))] + fields
    }
    let type_definition = @ion.IonValue::from_fields(named).with_annotations([
      @ion.SymbolToken::new("type"),
    ])
    let (outcome, _) = load_outcome(
      [@ion.IonValue::symbol("$ion_schema_2_0"), type_definition],
      valid=false,
    )
    outcomes.push(("\{id} \{description} invalid_types[\{index}]", outcome))
  }
}

///|
test "ion-schema-tests (ISL 2.0)" {
  if !@fs.path_exists(schema_root) {
    fail(
      "\{schema_root} is missing; run `git submodule update --init` to fetch the Ion Schema test data",
    )
  }
  // Outcomes by file.
  let files : Array[(String, Array[(String, SchemaOutcome)])] = []
  for path in files_under(schema_root) {
    if !path.has_suffix(".isl") {
      continue
    }
    let relative = path.view(start_offset=schema_root.length() + 1).to_owned()
    let outcomes : Array[(String, SchemaOutcome)] = []
    let values = try read_file(path) catch {
      error => {
        outcomes.push(
          (relative, SchemaFailed("does not read: \{describe(error)}")),
        )
        files.push((relative, outcomes))
        continue
      }
    } noraise {
      values => values
    }
    let tests = values.filter(value => annotated(value, "$test"))
    let definitions = values.filter(value => !annotated(value, "$test"))
    let (outcome, _) = load_outcome(definitions, valid=true)
    outcomes.push(("\{relative} schema", outcome))
    let types = load_types(definitions)
    for index, test_case in tests {
      run_schema_test(test_case, types, "\{relative} $test[\{index}]", outcomes)
    }
    files.push((relative, outcomes))
  }
  let unexpected : Array[String] = []
  let stale : Array[String] = []
  let unsupported : Map[String, Int] = Map([])
  let used : Set[String] = Set([])
  let mut passed = 0
  let mut total = 0
  for file in files {
    let (relative, outcomes) = file
    let mut clean = true
    for pair in outcomes {
      let (id, outcome) = pair
      total += 1
      match outcome {
        SchemaPassed => passed += 1
        SchemaFailed(reason) => {
          clean = false
          match known_failure(id) {
            Some(key) => used.add(key)
            None => unexpected.push("\{id}: \{reason}")
          }
        }
        SchemaUnsupported(reason) => {
          clean = false
          unsupported[reason] = unsupported.get(reason).unwrap_or(0) + 1
          if !schema_skipped.contains(relative) {
            unexpected.push("\{id}: unsupported: \{reason}")
          }
        }
      }
    }
    if clean && schema_skipped.contains(relative) {
      stale.push(relative)
    }
  }
  for key, _ in schema_known_failures {
    if !used.contains(key) {
      stale.push(key)
    }
  }
  println(
    "ion-schema-tests (ISL 2.0): \{files.length()} files, \{total} cases, \{passed} passed, \{unexpected.length()} unexpected",
  )
  // The unsupported reasons help only when something is unexpected.
  if !unexpected.is_empty() {
    let reasons = unsupported.to_array()
    reasons.sort_by((a, b) => b.1.compare(a.1))
    for pair in reasons {
      println("  unsupported (\{pair.1}): \{pair.0}")
    }
  }
  for line in unexpected {
    println("  FAIL " + line)
  }
  for relative in stale {
    println("  PASSES BUT LISTED " + relative)
  }
  assert_true(unexpected.is_empty() && stale.is_empty())
}
