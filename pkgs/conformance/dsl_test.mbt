// Runs the test cases in ion-tests' `conformance/` directory, which are
// written in a small declarative language (see
// `tests/ion-tests/conformance/README.md`):
//
//   (ion_1_0 "name"
//     (then (text "$ion_symbol_table::{symbols:[\"a\"]}")
//           (toplevel '#$10')
//           (produces a)))
//
// A test starts from an empty document (`document`) or one with an Ion 1.0
// version marker (`ion_1_0`, and `ion_1_x`, which an Ion 1.0 implementation
// reads as `ion_1_0`). Fragments (`text`, `binary`, `ivm`, `toplevel`) extend
// the document; `then` and `each` branch it; an expectation (`produces`,
// `denotes`, `signals`, `and`, `not`) checks each finished document.
//
// Two kinds of case do not apply to this implementation and are only
// counted: `ion_1_1` tests, and documents that mix `text` and `binary`
// fragments, which the language forbids. `dsl_skipped` lists the cases this
// implementation does not pass yet, by case ID or by a whole test
// (`file#index`), with the reason; a skip whose cases all pass fails the
// test.

///|
/// The conformance test files, relative to the module root.
let conformance_root : String = "tests/ion-tests/conformance"

///|
/// Cases this implementation does not pass yet, by case ID, with the reason.
let dsl_skipped : Map[String, String] = Map([
  (
    "data_model/decimal.ion", "the file does not read: its test 'a negative number with low precision and low, positive exponent' leaves a `then` clause unclosed, so the S-expressions never balance (an upstream ion-tests bug, amazon-ion/ion-tests#168)",
  ),
  (
    "system_symbols.ion#0 Ion 1.0 system symbol / then#2 '$ion_1_0'", "expects `$2` at the top level to produce the symbol `$ion_1_0`, but iontestdata/good/equivs/nonIVMNoOps.ion, which this implementation follows, makes it a no-op",
  ),
])

///|
/// The skip-list key that covers a case ID: the ID itself, or the test
/// (`file#index`) or file it belongs to.
fn skip_key(id : String) -> String? {
  if dsl_skipped.contains(id) {
    return Some(id)
  }
  for key, _ in dsl_skipped {
    if id.has_prefix(key + " ") {
      return Some(key)
    }
  }
  None
}

///|
/// A piece of a test document.
priv enum Fragment {
  /// Text, as UTF-8 octets, since a test may give raw octets.
  Text(Bytes)
  Binary(Bytes)
  /// A version marker, `$ion_<major>_<minor>`.
  Ivm(Int, Int)
  /// Values given as data, to be encoded as the document requires.
  Toplevel(Array[@ion.IonValue])
}

///|
/// A document under construction, and the path of names that led to it.
priv struct Document {
  path : String
  fragments : Array[Fragment]
}

///|
/// How one case went.
priv enum Outcome {
  Passed
  Failed(String)
  /// The case does not apply to an Ion 1.0 implementation.
  NotApplicable(String)
}

///|
/// The results of a run.
priv struct Report {
  outcomes : Array[(String, Outcome)]
}

///|
/// The keyword that starts a clause: the text of its first element, a
/// symbol or a string.
fn keyword(clause : @ion.IonValue) -> String? {
  match clause.kind() {
    Sexp(items) | List(items) if !items.is_empty() =>
      match items[0].kind() {
        Symbol(token) => token.text()
        String(text) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
/// The arguments of a clause: its elements after the keyword.
fn arguments(clause : @ion.IonValue) -> Array[@ion.IonValue] {
  match clause.kind() {
    Sexp(items) | List(items) => items[1:].to_owned()
    _ => []
  }
}

///|
/// The text of a string value.
fn string_of(value : @ion.IonValue) -> String? {
  match value.kind() {
    String(text) => Some(text)
    _ => None
  }
}

///|
/// The text of a symbol or a string. The grammar's quoted terminals, such as
/// `"negative_0"`, may be written as either.
fn atom_text(value : @ion.IonValue) -> String? {
  match value.kind() {
    Symbol(token) => token.text()
    String(text) => Some(text)
    _ => None
  }
}

///|
/// The name a test or a branch may start with: a string, or `null.string`
/// for no name.
fn name_of(value : @ion.IonValue) -> String? {
  match value.kind() {
    String(text) => Some(text)
    Null(String) => Some("")
    _ => None
  }
}

///|
/// An integer argument.
fn int_of(value : @ion.IonValue) -> Int raise {
  match value.kind() {
    Int(n) => n.to_int()
    _ => fail("expected an integer: \{show([value])}")
  }
}

///|
/// Octets given as integers or as strings of hexadecimal digit pairs.
fn octets_of(values : Array[@ion.IonValue]) -> Bytes raise {
  let octets : Array[Byte] = []
  for value in values {
    match value.kind() {
      Int(n) => octets.push(n.to_int().to_byte())
      String(text) => {
        let digits = text.iter().filter(c => c != ' ' && c != '\n').collect()
        if digits.length() % 2 != 0 {
          fail("odd number of hexadecimal digits: \{text}")
        }
        for index in 0..<(digits.length() / 2) {
          let pair = String::from_array([
            digits[index * 2],
            digits[index * 2 + 1],
          ])
          octets.push(@string.parse_int(pair, base=16).to_byte())
        }
      }
      _ => fail("expected octets: \{show([value])}")
    }
  }
  Bytes::from_array(octets)
}

///|
/// A fragment clause, or `None` when the clause is not one.
fn fragment_of(clause : @ion.IonValue) -> Fragment? raise {
  let args = arguments(clause)
  match keyword(clause) {
    Some("text") => {
      let octets : Array[Byte] = []
      for arg in args {
        match arg.kind() {
          String(text) => octets.append(@utf8.encode(text).to_array())
          Int(n) => octets.push(n.to_int().to_byte())
          _ => fail("expected text input: \{show([arg])}")
        }
      }
      Some(Text(Bytes::from_array(octets)))
    }
    Some("binary") => Some(Binary(octets_of(args)))
    Some("ivm") => Some(Ivm(int_of(args[0]), int_of(args[1])))
    Some("toplevel") => Some(Toplevel(args))
    _ => None
  }
}

///|
/// Walk the clauses of a test or an extension, extending `documents` with
/// each fragment and running each expectation against every document.
fn walk(
  clauses : Array[@ion.IonValue],
  documents : Array[Document],
  report : Report,
) -> Unit raise {
  let mut documents = documents
  let mut named = false
  let mut thens = 0
  for clause in clauses {
    if !named && name_of(clause) is Some(name) {
      // An optional name before the clauses.
      documents = documents.map(document => {
        ..document,
        path: document.path + " " + name,
      })
      named = true
      continue
    }
    named = true
    match fragment_of(clause) {
      Some(fragment) => {
        documents = documents.map(document => {
          ..document,
          fragments: document.fragments + [fragment],
        })
        continue
      }
      None => ()
    }
    match keyword(clause) {
      Some("then") => {
        thens += 1
        let branch = documents.map(document => {
          ..document,
          path: document.path + " / then#\{thens}",
        })
        walk(arguments(clause), branch, report)
      }
      Some("each") => walk_each(arguments(clause), documents, report)
      Some(_) =>
        for document in documents {
          report.outcomes.push((document.path, check(clause, document)))
        }
      None => fail("unexpected clause: \{show([clause])}")
    }
  }
}

///|
/// Walk an `each` clause: every named or unnamed fragment branches the
/// documents, and the clauses after the fragments continue every branch.
fn walk_each(
  args : Array[@ion.IonValue],
  documents : Array[Document],
  report : Report,
) -> Unit raise {
  let branches : Array[Document] = []
  let mut name : String? = None
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    if name_of(arg) is Some(text) {
      name = Some(text)
      index += 1
      continue
    }
    match fragment_of(arg) {
      Some(fragment) => {
        let label = name.unwrap_or("#\{branches.length() / documents.length()}")
        for document in documents {
          branches.push({
            path: document.path + " / each " + label,
            fragments: document.fragments + [fragment],
          })
        }
        name = None
        index += 1
      }
      None => break
    }
  }
  walk(args[index:].to_owned(), branches, report)
}

///|
/// The document's input: Ion text, Ion binary, or the reason it cannot be
/// built.
priv enum Input {
  TextInput(Bytes)
  BinaryInput(Bytes)
  Unbuildable(String)
}

///|
/// Build a document from its fragments. Text fragments are joined with
/// whitespace; `toplevel` data is written in the document's encoding.
fn build(document : Document) -> Input raise {
  let has_text = document.fragments.iter().any(fragment => fragment is Text(_))
  let has_binary = document.fragments
    .iter()
    .any(fragment => fragment is Binary(_))
  if has_text && has_binary {
    return Unbuildable("the document mixes text and binary fragments")
  }
  let octets : Array[Byte] = []
  for fragment in document.fragments {
    if has_binary {
      match fragment {
        Binary(bytes) => octets.append(bytes.to_array())
        Ivm(major, minor) =>
          octets.append([0xE0, major.to_byte(), minor.to_byte(), 0xEA])
        Toplevel(values) =>
          match encode_toplevel(values) {
            Some(bytes) => octets.append(bytes.to_array())
            None =>
              return Unbuildable(
                "toplevel symbols with text cannot be encoded into a binary document",
              )
          }
        Text(_) => ()
      }
    } else {
      if !octets.is_empty() {
        octets.push(b'\n')
      }
      match fragment {
        Text(bytes) => octets.append(bytes.to_array())
        Ivm(major, minor) =>
          octets.append(@utf8.encode("$ion_\{major}_\{minor}").to_array())
        Toplevel(values) =>
          match write_toplevel(values) {
            Some(text) => octets.append(@utf8.encode(text).to_array())
            None => return Unbuildable("an Ion 1.1 form in toplevel data")
          }
        Binary(_) => ()
      }
    }
  }
  let bytes = Bytes::from_array(octets)
  if has_binary {
    BinaryInput(bytes)
  } else {
    TextInput(bytes)
  }
}

///|
/// The symbol ID a `'#$<digits>'` symbol stands for in toplevel data.
fn reserved_sid(text : String) -> Int? {
  if !text.has_prefix("#$") || text.length() == 2 {
    return None
  }
  let digits = text.view(start_offset=2)
  if !digits.iter().all(c => c >= '0' && c <= '9') {
    return None
  }
  Some(@string.parse_int(digits)) catch {
    _ => None
  }
}

///|
/// Rewrite toplevel data's symbol tokens with `rewrite`, at any depth.
fn map_tokens(
  value : @ion.IonValue,
  rewrite : (@ion.SymbolToken) -> @ion.SymbolToken raise?,
) -> @ion.IonValue raise? {
  let annotations = value.annotations().map(rewrite)
  let kind = match value.kind() {
    Symbol(token) => @ion.IonValue::symbol_token(rewrite(token))
    List(items) =>
      @ion.IonValue::list(items.map(item => map_tokens(item, rewrite)))
    Sexp(items) =>
      @ion.IonValue::sexp(items.map(item => map_tokens(item, rewrite)))
    Struct(fields) =>
      @ion.IonValue::from_fields(
        fields.map(field => {
          @ion.Field::from_token(
            rewrite(field.name()),
            map_tokens(field.value(), rewrite),
          )
        }),
      )
    _ => value
  }
  kind.with_annotations(annotations)
}

///|
/// Write toplevel data as Ion text: `'#$ion_1_0'` as a version marker and
/// `'#$<digits>'` as a symbol-ID literal. `None` means the data holds an Ion
/// 1.1 form, such as an E-expression.
fn write_toplevel(values : Array[@ion.IonValue]) -> String? raise {
  let lines : Array[String] = []
  for value in values {
    if value.annotations().is_empty() &&
      value.kind() is Symbol(token) &&
      token.text() is Some(text) &&
      text.has_prefix("#$ion_") {
      lines.push(text.view(start_offset=1).to_owned())
      continue
    }
    let mut unsupported = false
    // A placeholder the writer leaves unquoted, swapped for the literal.
    let placeholder = fn(token : @ion.SymbolToken) -> @ion.SymbolToken {
      match token.text() {
        Some(text) if text.has_prefix("#$") =>
          match reserved_sid(text) {
            Some(sid) => @ion.SymbolToken::new("$__sid\{sid}__")
            None => {
              unsupported = true
              token
            }
          }
        _ => token
      }
    }
    let text = @text.write_ion(map_tokens(value, placeholder))
    if unsupported {
      return None
    }
    lines.push(replace_placeholders(text))
  }
  Some(lines.join("\n"))
}

///|
/// Swap each `$__sid<digits>__` placeholder for the literal `$<digits>`.
fn replace_placeholders(text : String) -> String {
  let result = StringBuilder()
  let mut rest = text.view()
  while rest.find("$__sid") is Some(start) {
    result.write_view(rest.view(end_offset=start))
    let after = rest.view(start_offset=start + 6)
    match after.find("__") {
      Some(end) => {
        result.write_string("$")
        result.write_view(after.view(end_offset=end))
        rest = after.view(start_offset=end + 2)
      }
      None => {
        result.write_view(rest.view(start_offset=start))
        rest = ""
      }
    }
  }
  result.write_view(rest)
  result.to_string()
}

///|
/// Encode toplevel data into a binary document with `'#$<digits>'` as raw
/// symbol IDs and `'#$ion_1_0'` as the version marker. `None` means a symbol
/// has text outside the system table, which a binary document could only
/// declare in a symbol table of its own.
fn encode_toplevel(values : Array[@ion.IonValue]) -> Bytes? raise {
  let table = @ion.SymbolTable::system()
  let octets : Array[Byte] = []
  for value in values {
    if value.annotations().is_empty() &&
      value.kind() is Symbol(token) &&
      token.text() is Some(text) &&
      text.has_prefix("#$ion_") {
      octets.append(@binary.binary_version_marker().to_array())
      continue
    }
    let raw = fn(token : @ion.SymbolToken) -> @ion.SymbolToken {
      match token.text() {
        Some(text) =>
          match reserved_sid(text) {
            Some(sid) => @ion.SymbolToken::from_sid(sid)
            None => token
          }
        None => token
      }
    }
    octets.append(
      @binary.encode_value(map_tokens(value, raw), table).to_array(),
    )
  }
  if table.is_empty() {
    Some(Bytes::from_array(octets))
  } else {
    None
  }
}

///|
/// Read a document's values.
fn read_input(input : Input) -> Array[@ion.IonValue] raise {
  match input {
    TextInput(bytes) => {
      let text = @utf8.decode(bytes) catch {
        _ => raise @ion.IonError::Syntax("the text is not UTF-8")
      }
      @text.read_ion_datagram(text, catalog=catalog())
    }
    BinaryInput(bytes) => @binary.read_binary(bytes, catalog=catalog())
    Unbuildable(reason) => fail(reason)
  }
}

///|
/// The shared symbol tables of ion-tests' catalog, which the import tests use.
fn catalog() -> @ion.Catalog raise {
  @ion.Catalog::load(
    @text.read_ion_datagram(
      @fs.read_file_to_string("tests/ion-tests/catalog/catalog.ion"),
    ),
  )
}

///|
/// Run an expectation against a document.
fn check(expectation : @ion.IonValue, document : Document) -> Outcome {
  let input = build(document) catch {
    error => return Failed("the test case is malformed: \{describe(error)}")
  }
  if input is Unbuildable(reason) {
    return NotApplicable(reason)
  }
  let result = try read_input(input) catch {
    error => Err(error)
  } noraise {
    values => Ok(values)
  }
  expect(expectation, result)
}

///|
/// Whether `result` meets an expectation clause.
fn expect(
  expectation : @ion.IonValue,
  result : Result[Array[@ion.IonValue], Error],
) -> Outcome {
  let args = arguments(expectation)
  match keyword(expectation) {
    Some("signals") =>
      match result {
        Err(_) => Passed
        Ok(values) => Failed("expected an error, read \{show(values)}")
      }
    Some("produces") | Some("denotes") => {
      let values = match result {
        Ok(values) => values
        Err(error) => return Failed(describe(error))
      }
      let expected = try {
        if keyword(expectation) == Some("produces") {
          args.map(produced_value)
        } else {
          args.map(model_value)
        }
      } catch {
        error => return Failed(describe(error))
      }
      if same_values(values, expected) {
        Passed
      } else {
        Failed("read \{show(values)}, expected \{show(expected)}")
      }
    }
    Some("and") => {
      for arg in args {
        let outcome = expect(arg, result)
        if !(outcome is Passed) {
          return outcome
        }
      }
      Passed
    }
    Some("not") =>
      match expect(args[0], result) {
        Passed => Failed("the negated expectation holds")
        Failed(_) => Passed
        other => other
      }
    other => Failed("unknown expectation: \{other.unwrap_or("?")}")
  }
}

///|
/// A `produces` datum, with `'#$0'` as a symbol with unknown text. A symbol
/// `'#$name#ddd'` is a symbol with unknown text at a place in a shared table;
/// the data model does not keep that place, so the check is only that the
/// text is unknown.
fn produced_value(value : @ion.IonValue) -> @ion.IonValue {
  map_tokens(value, token => {
    match token.text() {
      Some(text) if text.has_prefix("#$") => @ion.SymbolToken::from_sid(0)
      _ => token
    }
  })
}

///|
/// A symbol token in the model language: text, a symbol ID, or
/// `(text codepoint...)`.
fn model_token(value : @ion.IonValue) -> @ion.SymbolToken raise {
  match value.kind() {
    String(text) => @ion.SymbolToken::new(text)
    // A symbol ID: its text when it is a system symbol, unknown otherwise.
    Int(sid) => @ion.SymbolTable::system().token(sid.to_int())
    _ =>
      match keyword(value) {
        Some("text") => @ion.SymbolToken::new(codepoints(arguments(value)))
        // A symbol with unknown text at a place in a shared table, as
        // `(absent name offset)` or `(name offset)`. The data model does not
        // keep that place, so the check is only that the text is unknown.
        Some(_) => @ion.SymbolToken::from_sid(0)
        None => fail("invalid symbol model: \{show([value])}")
      }
  }
}

///|
/// A string from a list of code points.
fn codepoints(values : Array[@ion.IonValue]) -> String raise {
  let builder = StringBuilder()
  for value in values {
    builder.write_char(int_of(value).unsafe_to_char())
  }
  builder.to_string()
}

///|
/// The Ion value a `denotes` model value stands for.
fn model_value(value : @ion.IonValue) -> @ion.IonValue raise {
  match value.kind() {
    Bool(_) | Int(_) | String(_) => return value
    _ => ()
  }
  let args = arguments(value)
  match keyword(value) {
    Some("Null") =>
      if args.is_empty() {
        @ion.IonValue::untyped_null()
      } else {
        let name = match args[0].kind() {
          Symbol(token) => token.text().unwrap_or("")
          String(text) => text
          _ => ""
        }
        match @ion.IonType::from_text(name) {
          Some(ion_type) => @ion.IonValue::typed_null(ion_type)
          None => fail("unknown Ion type: \{show(args)}")
        }
      }
    Some("Bool") => args[0]
    Some("Int") => args[0]
    Some("Float") => {
      let text = string_of(args[0]).unwrap_or("")
      @ion.IonValue::float(
        match text {
          "nan" => @double.not_a_number
          "+inf" => @double.infinity
          "-inf" => @double.neg_infinity
          _ => @string.parse_double(text)
        },
      )
    }
    Some("Decimal") =>
      match args[0].kind() {
        Symbol(_) | String(_) if atom_text(args[0]) == Some("negative_0") =>
          @ion.IonValue::decimal(
            @ion.Decimal::negative_zero_at(int_of(args[1])),
          )
        Int(coefficient) =>
          @ion.IonValue::decimal(
            @ion.Decimal::new(coefficient, int_of(args[1])),
          )
        _ => fail("invalid decimal model: \{show(args)}")
      }
    Some("String") => @ion.IonValue::string(codepoints(args))
    Some("Symbol") => @ion.IonValue::symbol_token(model_token(args[0]))
    Some("List") => @ion.IonValue::list(args.map(model_value))
    Some("Sexp") => @ion.IonValue::sexp(args.map(model_value))
    Some("Struct") =>
      @ion.IonValue::from_fields(
        args.map(field => {
          let parts = match field.kind() {
            Sexp(parts) | List(parts) if parts.length() == 2 => parts
            _ => fail("invalid field model: \{show([field])}")
          }
          @ion.Field::from_token(model_token(parts[0]), model_value(parts[1]))
        }),
      )
    Some("Blob") => @ion.IonValue::blob(octets_of(args))
    Some("Clob") => @ion.IonValue::clob(octets_of(args))
    Some("annot") =>
      model_value(args[0]).with_annotations(
        args[1:].to_owned().map(model_token),
      )
    other => fail("unsupported model value: \{other.unwrap_or("?")}")
  }
}

///|
test "ion-tests conformance DSL" {
  if !@fs.path_exists(conformance_root) {
    fail(
      "\{conformance_root} is missing; run `git submodule update --init` to fetch the Ion test data",
    )
  }
  let report : Report = { outcomes: [], }
  let mut ion_1_1 = 0
  for path in files_under(conformance_root) {
    if !path.has_suffix(".ion") {
      continue
    }
    let file = path.view(start_offset=conformance_root.length() + 1).to_owned()
    let tests = @text.read_ion_datagram(@fs.read_file_to_string(path)) catch {
      error => {
        report.outcomes.push(
          (file, Failed("does not read: \{describe(error)}")),
        )
        continue
      }
    }
    for index in 0..<tests.length() {
      let form = tests[index]
      let start = match keyword(form) {
        Some("document") => []
        Some("ion_1_0") | Some("ion_1_x") => [Ivm(1, 0)]
        Some("ion_1_1") => {
          ion_1_1 += 1
          continue
        }
        other => fail("\{file}: unknown test form \{other.unwrap_or("?")}")
      }
      let document : Document = { path: "\{file}#\{index}", fragments: start, }
      walk(arguments(form), [document], report)
    }
  }
  let unexpected : Array[String] = []
  let not_applicable : Map[String, Int] = Map([])
  let mut passed = 0
  let mut skipped = 0
  // Whether each skip-list key covered a failing case.
  let skip_failed : Map[String, Bool] = Map([])
  for pair in report.outcomes {
    let (id, outcome) = pair
    let key = skip_key(id)
    match outcome {
      Passed => {
        passed += 1
        if key is Some(key) && !skip_failed.contains(key) {
          skip_failed[key] = false
        }
      }
      Failed(reason) =>
        match key {
          Some(key) => {
            skipped += 1
            skip_failed[key] = true
          }
          None => unexpected.push("\{id}: \{reason}")
        }
      NotApplicable(reason) =>
        not_applicable[reason] = not_applicable.get(reason).unwrap_or(0) + 1
    }
  }
  // A skip is stale when it covers no case, or no failing one.
  let stale : Array[String] = []
  for key, _ in dsl_skipped {
    if skip_failed.get(key) != Some(true) {
      stale.push(key)
    }
  }
  println(
    "ion-tests conformance DSL: \{report.outcomes.length()} cases, \{passed} passed, \{skipped} skipped under \{dsl_skipped.length()} skip entries, \{unexpected.length()} unexpected failures, \{ion_1_1} Ion 1.1 tests not run",
  )
  for reason, count in not_applicable {
    println("  not applicable (\{count}): \{reason}")
  }
  for line in unexpected {
    println("  FAIL " + line)
  }
  for id in stale {
    println("  PASSES BUT SKIPPED " + id)
  }
  assert_true(unexpected.is_empty() && stale.is_empty())
}

///|
test "the decimal model accepts negative_0 as a symbol or a string" {
  // The grammar's quoted terminals, such as "negative_0", may be written as
  // either; data_model/decimal.ion uses the string form.
  let expected = @ion.IonValue::decimal(@ion.Decimal::negative_zero_at(-3))
  for model in ["(Decimal negative_0 -3)", "(Decimal \"negative_0\" -3)"] {
    assert_true(model_value(@text.read_ion(model)).equals(expected))
  }
  assert_true(
    model_value(@text.read_ion("(Decimal -15 -1)")).equals(
      @ion.IonValue::decimal(@ion.Decimal::parse("-1.5")),
    ),
  )
}
