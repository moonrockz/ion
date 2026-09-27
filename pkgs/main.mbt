// The `ion` CLI: read and re-emit Ion, hash values, and validate Ion values
// against an Ion Schema. Input may be Ion text or Ion binary; a leading
// version marker decides.
//
//   ion print [file|-]
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
/// Read a file (or stdin) as bytes.
fn read_input_bytes(path : String) -> Bytes raise {
  if path == "-" {
    @fs.read_file_to_bytes("/dev/stdin")
  } else {
    @fs.read_file_to_bytes(path)
  }
}

///|
/// Read a document as a datagram: Ion binary when it begins with the version
/// marker, and Ion text otherwise.
fn read_datagram(path : String) -> Array[@core.IonValue] raise @core.IonError {
  let bytes = read_input_bytes(path) catch {
    @fs.IOError(message) => raise @core.IonError::Syntax(message)
    _ => raise @core.IonError::Syntax("failed to read " + path)
  }
  if @binary.has_version_marker(bytes[:], 0) {
    @binary.read_binary(bytes[:])
  } else {
    let text = @utf8.decode(bytes) catch {
      _ =>
        raise @core.IonError::Syntax(
          "the input is neither Ion binary nor UTF-8 Ion text",
        )
    }
    @text.read_ion_datagram(text)
  }
}

///|
/// Read a document and print its canonical Ion text.
fn do_print(path : String) -> Result[Unit, String] {
  let values = read_datagram(path) catch {
    error => return Err(error.message())
  }
  let outcome = @text.write_all(values) catch {
    error => return Err(error.message())
  }
  println(outcome)
  Ok(())
}

///|
/// Print the SHA-256 Ion Hash of every value in a document, one per line.
fn do_hash(path : String) -> Result[Unit, String] {
  let values = read_datagram(path) catch {
    error => return Err(error.message())
  }
  let hashes : Array[String] = []
  for value in values {
    let digest = @hash.ion_hash_hex(value) catch {
      error => return Err(error.message())
    }
    hashes.push(digest)
  }
  if !hashes.is_empty() {
    println(hashes.join("\n"))
  }
  Ok(())
}

///|
/// Validate every value in a document against a named schema type.
fn do_validate(
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
  let input_text = read_input(input) catch {
    @fs.IOError(message) => return Err(message)
    _ => return Err("failed to read " + input)
  }
  let values = @text.read_ion_datagram(input_text) catch {
    error => return Err(error.message())
  }
  let mut failed = 0
  for index in 0..<values.length() {
    let violations = schema.validate(type_name, values[index])
    for violation in violations {
      eprintln("value \{index}: \{violation.path()}: \{violation.message()}")
    }
    if !violations.is_empty() {
      failed += 1
    }
  }
  if failed == 0 {
    Ok(())
  } else {
    Err("\{failed} of \{values.length()} value(s) failed validation")
  }
}

///|
/// Dispatch a parsed command line.
fn run(args : Array[String]) -> Result[Unit, String] {
  match args {
    [_] => do_print("-")
    [_, "print", path, ..] => do_print(path)
    [_, "print"] => do_print("-")
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
fn main {
  match run(@env.args()) {
    Ok(_) => ()
    Err(message) => {
      eprintln(message)
      @sys.exit(1)
    }
  }
}
