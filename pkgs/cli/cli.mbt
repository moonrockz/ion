// The `ion` command line: read and re-emit Ion, convert to and from JSON,
// hash values, and validate Ion values against an Ion Schema. Ion input may be
// text or binary; a leading version marker decides. Ion input is streamed:
// each value is read, handled, and dropped in turn, so memory stays
// proportional to the largest value rather than to the input.
//
//   ion print [--binary | --pretty] [file|-]
//   ion json [file|-]
//   ion fromjson [file|-]
//   ion hash [file|-]
//   ion validate <schema-file> <type-name> [file|-]
//   ion version
//   ion help

///|
/// The version the command line reports.
let version : String = "moonrockz/ion 0.1.0"

///|
/// The usage text.
let usage : String =
  #|usage: ion <command> [args]
  #|  ion print [--binary | --pretty] [file|-]
  #|                          Ion text or binary in; Ion text (or binary) out
  #|  ion json [file|-]       Ion text or binary in; JSON out
  #|  ion fromjson [file|-]   JSON in; Ion text out
  #|  ion hash [file|-]       the Ion Hash (SHA-256) of each value
  #|  ion validate <schema-file> <type-name> [file|-]
  #|                          check each value against an Ion Schema type
  #|  ion version
  #|  ion help
  #|A missing file, or `-`, reads stdin.

///|
/// An error the command line reports in its own words, such as an input it
/// cannot open.
priv suberror CliError {
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
/// How error messages name an input path: `stdin` for `-`.
fn describe_path(path : String) -> String {
  if path == "-" {
    "stdin"
  } else {
    path
  }
}

///|
/// A buffered stream the command line writes to. Octets collect in memory
/// and go to the sink in large writes, since a small write per value is slow.
priv struct Output {
  sink : &@io.Writer
  buffer : @buffer.Buffer
}

///|
/// The size at which buffered output goes to the sink.
let flush_size : Int = 65536

///|
impl @io.Writer for Output with fn write_once(self, data, offset~, len~) {
  self.buffer.write_bytesview(data[offset:offset + len])
  len
}

///|
/// Write a line of text.
fn Output::line(self : Output, text : String) -> Unit {
  self.buffer.write_bytes(@utf8.encode(text))
  self.buffer.write_byte(b'\n')
}

///|
/// Send the buffered octets to the sink once there are many of them.
async fn Output::flush_when_full(self : Output) -> Unit {
  if self.buffer.length() >= flush_size {
    self.flush()
  }
}

///|
/// Send every buffered octet to the sink.
async fn Output::flush(self : Output) -> Unit {
  if !self.buffer.is_empty() {
    self.sink.write(self.buffer.to_bytes())
    self.buffer.reset()
  }
}

///|
/// The standard streams of one run.
priv struct Streams {
  stdin : &@io.Reader
  out : Output
  err : Output
}

///|
/// Run the command line with `args` (without the program name) and the
/// standard streams, and return the exit status: 0 on success, 1 when a
/// command fails, and 2 when the arguments do not make a command.
pub async fn run(
  args : Array[String],
  stdin : &@io.Reader,
  stdout : &@io.Writer,
  stderr : &@io.Writer,
) -> Int {
  let streams : Streams = {
    stdin,
    out: { sink: stdout, buffer: @buffer.Buffer(), },
    err: { sink: stderr, buffer: @buffer.Buffer(), },
  }
  let status = dispatch(args, streams) catch {
    error => {
      streams.err.line(describe(error))
      1
    }
  }
  // Output already written stays written; a failure to flush is reported
  // only as the exit status, since stderr may be what failed.
  streams.out.flush() catch {
    _ => return 1
  }
  streams.err.flush() catch {
    _ => return 1
  }
  status
}

///|
/// Run the command that `args` names, returning its exit status.
async fn dispatch(args : Array[String], streams : Streams) -> Int {
  match args {
    [] => print(streams, "-", Text)
    ["print", .. rest] =>
      match print_arguments(rest) {
        Some((format, path)) => print(streams, path, format)
        None => usage_error(streams)
      }
    ["json"] => json(streams, "-")
    ["json", path] => json(streams, path)
    ["fromjson"] => from_json(streams, "-")
    ["fromjson", path] => from_json(streams, path)
    ["hash"] => hash(streams, "-")
    ["hash", path] => hash(streams, path)
    ["validate", schema_path, type_name] =>
      validate(streams, schema_path, type_name, "-")
    ["validate", schema_path, type_name, path] =>
      validate(streams, schema_path, type_name, path)
    ["version"] => {
      streams.out.line(version)
      0
    }
    ["help"] | ["--help"] | ["-h"] => {
      streams.out.line(usage)
      0
    }
    _ => usage_error(streams)
  }
}

///|
/// Report arguments that do not make a command.
fn usage_error(streams : Streams) -> Int {
  streams.err.line(usage)
  2
}

///|
/// How `print` writes values.
priv enum Format {
  Text
  Pretty
  Binary
}

///|
/// The format and input path of `print [--binary | --pretty] [file|-]`, or
/// `None` when the arguments do not fit that shape.
fn print_arguments(args : ArrayView[String]) -> (Format, String)? {
  let mut format = Text
  let mut path : String? = None
  for arg in args {
    match arg {
      "--binary" if format is Text => format = Binary
      "--pretty" if format is Text => format = Pretty
      _ if arg.has_prefix("--") => return None
      _ if path is None => path = Some(arg)
      _ => return None
    }
  }
  Some((format, path.unwrap_or("-")))
}

///|
/// Read a whole file, or stdin when the path is `-`, as UTF-8 text.
async fn read_text(streams : Streams, path : String) -> String {
  let data = if path == "-" {
    streams.stdin.read_all() catch {
      _ => raise CliError("stdin: cannot be read")
    }
  } else {
    @async_fs.read_file(path) catch {
      error => raise open_failure(path, error)
    }
  }
  data.text() catch {
    _ => raise CliError("\{describe_path(path)}: is not UTF-8 text")
  }
}

///|
/// Call `visit` on every value of a file, or of stdin when the path is `-`,
/// as each value arrives.
async fn each_value(
  streams : Streams,
  path : String,
  visit : async (@core.IonValue) -> Unit,
) -> Unit {
  if path == "-" {
    each_value_of("stdin", streams.stdin, visit)
  } else {
    let file = @async_fs.open(path, mode=ReadOnly) catch {
      error => raise open_failure(path, error)
    }
    defer file.close()
    each_value_of(path, file, visit)
  }
}

///|
/// Call `visit` on every value of `source`, which `name` names in errors: Ion
/// binary when the source begins with the version marker, and Ion text
/// otherwise. The first octets decide, and then go to the reader ahead of the
/// rest of the source.
async fn each_value_of(
  name : String,
  source : &@io.Reader,
  visit : async (@core.IonValue) -> Unit,
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
/// Write each value of the input as Ion text, one per line, or as indented
/// text, or as Ion binary.
async fn print(streams : Streams, path : String, format : Format) -> Int {
  let out = streams.out
  match format {
    Binary => {
      let writer = @binary_stream.BinaryWriter::new(out)
      each_value(streams, path, async fn(value) {
        writer.write(value)
        out.flush_when_full()
      })
    }
    Text | Pretty => {
      // IDs of symbols with unknown text that a table before now reserved.
      let mut reserved = 9
      each_value(streams, path, async fn(value) {
        let (text, now_reserved) = @text.write_stream_value(
          value,
          reserved~,
          pretty=format is Pretty,
        )
        reserved = now_reserved
        out.line(text)
        out.flush_when_full()
      })
    }
  }
  0
}

///|
/// Write each value of the input as JSON, one per line.
async fn json(streams : Streams, path : String) -> Int {
  each_value(streams, path, async fn(value) {
    streams.out.line(@json.write_json(value))
    streams.out.flush_when_full()
  })
  0
}

///|
/// Read a JSON document and write it as Ion text.
async fn from_json(streams : Streams, path : String) -> Int {
  let value = @json.read_json(read_text(streams, path))
  streams.out.line(@text.write_ion(value))
  0
}

///|
/// Write the SHA-256 Ion Hash of each value of the input, one per line.
async fn hash(streams : Streams, path : String) -> Int {
  each_value(streams, path, async fn(value) {
    streams.out.line(@hash.ion_hash_hex(value))
    streams.out.flush_when_full()
  })
  0
}

///|
/// Check each value of the input against a schema type, reporting each
/// violation on stderr. Fails when any value has a violation.
async fn validate(
  streams : Streams,
  schema_path : String,
  type_name : String,
  path : String,
) -> Int {
  let schema = @schema.Schema::load_from_text(read_text(streams, schema_path))
  if schema.find(type_name) is None {
    raise CliError("\{describe_path(schema_path)}: no type named \{type_name}")
  }
  let mut index = 0
  let mut failed = 0
  each_value(streams, path, async fn(value) {
    let violations = schema.validate(type_name, value)
    for violation in violations {
      streams.err.line(
        "value \{index}: \{violation.path()}: \{violation.message()}",
      )
    }
    if !violations.is_empty() {
      failed += 1
    }
    index += 1
    streams.err.flush_when_full()
  })
  if failed == 0 {
    0
  } else {
    streams.err.line("\{failed} of \{index} value(s) failed validation")
    1
  }
}
