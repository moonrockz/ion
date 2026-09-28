// The `ion` CLI: read and re-emit Ion, convert to and from JSON, hash values,
// and validate Ion values against an Ion Schema. Ion input may be text or
// binary; a leading version marker decides. Ion input is streamed: each value
// is read, handled, and dropped in turn, so memory stays proportional to the
// largest value rather than to the input.
//
//   ion print [file|-]
//   ion json [file|-]
//   ion fromjson [file|-]
//   ion hash [file|-]
//   ion validate <schema-file> <type-name> [file|-]

///|
fn version() -> String {
  "moonrockz/ion 0.1.0"
}

///|
fn usage() -> String {
  "usage: ion <command> [args]\n" +
  "  ion print [file|-]     Ion text or Ion binary in, Ion text out\n" +
  "  ion json [file|-]      Ion text or Ion binary in, JSON out\n" +
  "  ion fromjson [file|-]  JSON in, Ion text out\n" +
  "  ion hash [file|-]\n" +
  "  ion validate <schema-file> <type-name> [file|-]"
}

///|
/// Write a line to stderr, falling back to stdout when stderr is unavailable.
fn eprintln(message : String) -> Unit {
  @fs.write_string_to_file("/dev/stderr", message + "\n") catch {
    _ => println(message)
  }
}

///|
/// Read a file, or stdin when the path is `-`.
fn read_input(path : String) -> String raise {
  if path == "-" {
    @fs.read_file_to_string("/dev/stdin")
  } else {
    @fs.read_file_to_string(path)
  }
}

///|
/// An error the CLI reports in its own words, such as an input it cannot open.
suberror CliError {
  CliError(String)
}

///|
/// The message of an error: the text of an `IonError` or a `CliError`, or its
/// description.
fn describe(error : Error) -> String {
  match error {
    @core.IonError::Syntax(message)
    | @core.IonError::DataModel(message)
    | @core.IonError::Unsupported(message)
    | CliError(message) => message
    _ => error.to_string()
  }
}

///|
/// Why `path` could not be opened.
fn open_failure(path : String, error : Error) -> CliError {
  match error {
    @os_error.OSError(_, ..) as os_error if os_error.is_ENOENT() =>
      CliError("\{path}: no such file or directory")
    @os_error.OSError(_, ..) as os_error if os_error.is_EACCES() =>
      CliError("\{path}: permission denied")
    _ => CliError("\{path}: cannot be opened")
  }
}

///|
/// Call `visit` on every value of a file, or of stdin when the path is `-`,
/// as each value arrives: Ion binary when the input begins with the version
/// marker, and Ion text otherwise.
async fn each_value(
  path : String,
  visit : (@core.IonValue) -> Unit raise,
) -> Unit {
  if path == "-" {
    each_value_of("stdin", @stdio.stdin, visit)
  } else {
    let file = @async_fs.open(path, mode=ReadOnly) catch {
      error => raise open_failure(path, error)
    }
    defer file.close()
    each_value_of(path, file, visit)
  }
}

///|
/// Call `visit` on every value of `source`, which `name` names in errors. The
/// first octets decide the encoding, and then go to the reader ahead of the
/// rest of the source.
async fn each_value_of(
  name : String,
  source : &@io.Reader,
  visit : (@core.IonValue) -> Unit raise,
) -> Unit {
  let mut head = Bytes::new(0)
  while head.length() < 4 {
    let chunk = source.read_some() catch {
      _ => raise CliError("\{name}: cannot be read")
    }
    match chunk {
      Some(chunk) if chunk.length() > 0 => head = head + chunk
      _ => break
    }
  }
  let input = @io.MemoryReader(async fn(writer) {
    writer.write(head)
    // Large reads keep the number of hand-offs through the pipe small.
    while source.read_some(max_len=65536) is Some(chunk) {
      writer.write(chunk)
    }
  })
  defer input.close()
  if @binary.has_version_marker(head[:], 0) {
    let reader = @binary_stream.BinaryReader::new(input)
    while reader.next() is Some(value) {
      visit(value)
    }
  } else {
    let reader = @text_stream.TextReader::new(input)
    while reader.next() is Some(value) {
      visit(value)
    }
  }
}

///|
/// Read a document and print its canonical Ion text, one value per line.
async fn do_print(path : String) -> Result[Unit, String] {
  each_value(path, value => println(@text.write_ion(value))) catch {
    error => return Err(describe(error))
  }
  Ok(())
}

///|
/// Print the SHA-256 Ion Hash of every value in a document, one per line.
async fn do_hash(path : String) -> Result[Unit, String] {
  each_value(path, value => println(@hash.ion_hash_hex(value))) catch {
    error => return Err(describe(error))
  }
  Ok(())
}

///|
/// Validate every value in a document against a named schema type.
async fn do_validate(
  schema_path : String,
  type_name : String,
  input : String,
) -> Result[Unit, String] {
  let schema_text = read_input(schema_path) catch {
    @fs.IOError(message) => return Err(message)
    _ => return Err("failed to read " + schema_path)
  }
  let schema = @schema.Schema::load_from_text(schema_text) catch {
    error => return Err(error.message())
  }
  let mut index = 0
  let mut failed = 0
  each_value(input, fn(value) {
    let violations = schema.validate(type_name, value)
    for violation in violations {
      eprintln("value \{index}: \{violation.path()}: \{violation.message()}")
    }
    if !violations.is_empty() {
      failed += 1
    }
    index += 1
  }) catch {
    error => return Err(describe(error))
  }
  if failed == 0 {
    Ok(())
  } else {
    Err("\{failed} of \{index} value(s) failed validation")
  }
}

///|
/// Dispatch a parsed command line.
async fn run(args : Array[String]) -> Result[Unit, String] {
  match args {
    [_] => do_print("-")
    [_, "print", path, ..] => do_print(path)
    [_, "print"] => do_print("-")
    [_, "json", path, ..] => do_json(path)
    [_, "json"] => do_json("-")
    [_, "fromjson", path, ..] => do_from_json(path)
    [_, "fromjson"] => do_from_json("-")
    [_, "hash", path, ..] => do_hash(path)
    [_, "hash"] => do_hash("-")
    [_, "validate", schema_path, type_name, input, ..] =>
      do_validate(schema_path, type_name, input)
    [_, "validate", schema_path, type_name] =>
      do_validate(schema_path, type_name, "-")
    [_, "version", ..] => {
      println(version())
      Ok(())
    }
    _ => Err(usage())
  }
}

///|
async fn main {
  match run(@env.args()) {
    Ok(_) => ()
    Err(message) => {
      eprintln(message)
      @sys.exit(1)
    }
  }
}

///|
/// Read a document and print each value as JSON text, one per line, following
/// the cookbook's down-conversion rules.
async fn do_json(path : String) -> Result[Unit, String] {
  each_value(path, value => println(@json.write_json(value))) catch {
    error => return Err(describe(error))
  }
  Ok(())
}

///|
/// Read a JSON document and print its canonical Ion text.
fn do_from_json(path : String) -> Result[Unit, String] {
  let text = read_input(path) catch {
    @fs.IOError(message) => return Err(message)
    _ => return Err("failed to read " + path)
  }
  let value = @json.read_json(text) catch {
    error => return Err(error.message())
  }
  let printed = @text.write_ion(value) catch {
    error => return Err(error.message())
  }
  println(printed)
  Ok(())
}
