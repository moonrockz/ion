// The `ion` command line: read and re-emit Ion, convert to and from JSON,
// hash values, and validate Ion values against an Ion Schema. Ion input may be
// text or binary; a leading version marker decides. Ion input is streamed:
// each value is read, handled, and dropped in turn, so memory stays
// proportional to the largest value rather than to the input.
//
// `moonbitlang/core/argparse` parses the arguments; see `command_line` for
// the commands.

///|
/// The version the command line reports.
let version : String = "moonrockz/ion 0.2.0"

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
  /// The shared symbol tables of the `--catalog` files.
  mut catalog : @core.Catalog
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
    catalog: @core.Catalog::new(),
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
/// The input positional every command takes: a file, or `-` for stdin.
fn input_argument(about : String) -> @argparse.PositionArg {
  @argparse.PositionArg("file", about~, default_values=["-"])
}

///|
/// The names of the commands, in the order the help lists them.
let command_names : Array[String] = [
  "print", "json", "fromjson", "hash", "validate", "version", "help",
]

///|
/// The command `name`, called `prefix` plus its name: `ion print` to render
/// its help alone, or `print` as a subcommand of `ion`.
fn subcommand(name : String, prefix : String) -> @argparse.Command {
  let ion_input = "The Ion input, text or binary; `-` reads stdin."
  let required = @argparse.ValueRange::single()
  let named = prefix + name
  match name {
    "print" =>
      @argparse.Command(
        named,
        about="Write each value as Ion text, one per line (the default command).",
        flags=[
          @argparse.FlagArg("binary", about="Write Ion binary instead.", conflicts_with=[
            "pretty",
          ]),
          @argparse.FlagArg("pretty", about="Indent containers."),
        ],
        positionals=[input_argument(ion_input)],
      )
    "json" =>
      @argparse.Command(
        named,
        about="Write each value as JSON, one per line.",
        positionals=[input_argument(ion_input)],
      )
    "fromjson" =>
      @argparse.Command(
        named,
        about="Read a JSON document and write it as Ion text.",
        positionals=[input_argument("The JSON input; `-` reads stdin.")],
      )
    "hash" =>
      @argparse.Command(
        named,
        about="Write the Ion Hash (SHA-256) of each value, one per line.",
        positionals=[input_argument(ion_input)],
      )
    "validate" =>
      @argparse.Command(
        named,
        about="Check each value against a type of an Ion Schema.",
        positionals=[
          @argparse.PositionArg(
            "schema-file",
            about="The Ion Schema document.",
            num_args=required,
          ),
          @argparse.PositionArg(
            "type-name",
            about="The schema type to check each value against.",
            num_args=required,
          ),
          input_argument(ion_input),
        ],
        options=[
          @argparse.OptionArg(
            "schema-root",
            about="The directory that the ids of schema imports are relative to. Default: the schema file's directory.",
          ),
        ],
      )
    "version" => @argparse.Command(named, about="Write the version.")
    _ =>
      @argparse.Command(
        named,
        about="Write the help of the command line or of one command.",
        positionals=[
          @argparse.PositionArg(
            "command",
            about="The command to describe.",
            num_args=@argparse.ValueRange(lower=0, upper=1),
          ),
        ],
      )
  }
}

///|
/// The command line's grammar. argparse's own help and version handling
/// writes to the process's stdout and exits the process, so the command line
/// declares its own `--help` and `--version` flags and writes to its streams.
fn command_line() -> @argparse.Command {
  @argparse.Command(
    "ion",
    about="Read, write, convert, hash, and validate Amazon Ion. Ion input may be text or binary, and is read one value at a time. With no command, `ion` prints stdin.",
    disable_help_flag=true,
    disable_help_subcommand=true,
    disable_version_flag=true,
    flags=[
      @argparse.FlagArg(
        "help",
        short='h',
        about="Show help information.",
        global=true,
      ),
      @argparse.FlagArg("version", short='V', about="Show the version."),
    ],
    options=[
      @argparse.OptionArg(
        "catalog",
        about="An Ion file of $ion_shared_symbol_table structs, for the shared tables that input imports. May be given more than once.",
        action=Append,
        global=true,
      ),
    ],
    subcommands=command_names.map(name => subcommand(name, "")),
  )
}

///|
/// The help text of the command line, or of the command `name`.
fn help_text(name : String?) -> String? {
  match name {
    None => Some(command_line().render_help())
    Some(name) if command_names.contains(name) =>
      Some(subcommand(name, "ion ").render_help())
    Some(_) => None
  }
}

///|
/// The single value of a positional or option.
fn value_of(matches : @argparse.Matches, name : String) -> String {
  match matches.values.get(name) {
    Some([value, ..]) => value
    _ => "-"
  }
}

///|
/// Run the command that `args` names, returning its exit status.
async fn dispatch(args : Array[String], streams : Streams) -> Int {
  let matches = command_line().parse(argv=args, env=Map([])) catch {
    error => {
      streams.err.line(error.to_string().trim_end(chars="\n").to_owned())
      return 2
    }
  }
  if matches.flags.get("help") == Some(true) {
    let name = matches.subcommand.map(pair => pair.0)
    streams.out.line(
      help_text(name).unwrap_or("").trim_end(chars="\n").to_owned(),
    )
    return 0
  }
  if matches.flags.get("version") == Some(true) {
    streams.out.line(version)
    return 0
  }
  // A global option may land on the command line or on its command.
  let catalogs : Array[String] = []
  for found in [Some(matches), matches.subcommand.map(pair => pair.1)] {
    for
      path in found
      .map(m => m.values.get("catalog").unwrap_or([]))
      .unwrap_or([]) {
      if !catalogs.contains(path) {
        catalogs.push(path)
      }
    }
  }
  streams.catalog = load_catalog(streams, catalogs)
  match matches.subcommand {
    None => print(streams, "-", Text)
    Some(("print", sub)) => {
      let format = if sub.flags.get("binary") == Some(true) {
        Binary
      } else if sub.flags.get("pretty") == Some(true) {
        Pretty
      } else {
        Text
      }
      print(streams, value_of(sub, "file"), format)
    }
    Some(("json", sub)) => json(streams, value_of(sub, "file"))
    Some(("fromjson", sub)) => from_json(streams, value_of(sub, "file"))
    Some(("hash", sub)) => hash(streams, value_of(sub, "file"))
    Some(("validate", sub)) =>
      validate(
        streams,
        value_of(sub, "schema-file"),
        value_of(sub, "type-name"),
        value_of(sub, "file"),
        match sub.values.get("schema-root") {
          Some([root, ..]) => Some(root)
          _ => None
        },
      )
    Some(("version", _)) => {
      streams.out.line(version)
      0
    }
    Some(("help", sub)) => {
      let name = match sub.values.get("command") {
        Some([name, ..]) => Some(name)
        _ => None
      }
      match help_text(name) {
        Some(text) => {
          streams.out.line(text.trim_end(chars="\n").to_owned())
          0
        }
        None => {
          streams.err.line("error: no command named '\{name.unwrap_or("")}'")
          2
        }
      }
    }
    Some((other, _)) => {
      streams.err.line("error: no command named '\{other}'")
      2
    }
  }
}

///|
/// How `print` writes values.
priv enum Format {
  Text
  Pretty
  Binary
}

///|
/// A catalog of the shared symbol tables in the files at `paths`, each Ion
/// text or binary.
async fn load_catalog(
  streams : Streams,
  paths : Array[String],
) -> @core.Catalog {
  let values : Array[@core.IonValue] = []
  for path in paths {
    each_value(streams, path, value => values.push(value))
  }
  @core.Catalog::load(values)
}

///|
/// Read a whole file, or stdin when the path is `-`.
async fn read_all(streams : Streams, path : String) -> Bytes {
  let data = if path == "-" {
    streams.stdin.read_all() catch {
      _ => raise CliError("stdin: cannot be read")
    }
  } else {
    @async_fs.read_file(path) catch {
      error => raise open_failure(path, error)
    }
  }
  data.binary()
}

///|
/// Read a whole file, or stdin when the path is `-`, as UTF-8 text.
async fn read_text(streams : Streams, path : String) -> String {
  @utf8.decode(read_all(streams, path)) catch {
    _ => raise CliError("\{describe_path(path)}: is not UTF-8 text")
  }
}

///|
/// Read a whole file, or stdin when the path is `-`, as Ion text in the
/// encoding its first octets show: UTF-8, UTF-16, or UTF-32.
async fn read_ion_text(streams : Streams, path : String) -> String {
  @text.decode_ion_text(read_all(streams, path)) catch {
    @core.IonError::Syntax(message) =>
      raise CliError("\{describe_path(path)}: \{message}")
    error => raise error
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
    each_value_of("stdin", streams.stdin, streams.catalog, visit)
  } else {
    let file = @async_fs.open(path, mode=ReadOnly) catch {
      error => raise open_failure(path, error)
    }
    defer file.close()
    each_value_of(path, file, streams.catalog, visit)
  }
}

///|
/// Call `visit` on every value of `source`, which `name` names in errors: Ion
/// binary when the source begins with the version marker, and Ion text
/// otherwise. The first octets decide, and the reader reads them before the
/// rest of the source.
async fn each_value_of(
  name : String,
  source : &@io.Reader,
  catalog : @core.Catalog,
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
  if @binary.has_version_marker(head[:], 0) {
    let reader = @binary_stream.BinaryReader::new(source, prefix=head, catalog~)
    while reader.next() is Some(value) {
      visit(value)
    }
  } else {
    let reader = @text_stream.TextReader::new(source, prefix=head, catalog~)
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
/// Load a schema file and the schemas it imports, whose ids are paths under
/// `schema_root`, or else under the schema file's directory.
///
/// The schema loader asks for an import while it loads, but a file is read
/// asynchronously. So the loader runs again after each import it asks for
/// that is not read yet, until every import is read.
async fn load_schema(
  streams : Streams,
  schema_path : String,
  schema_root : String?,
) -> @schema.Schema {
  let root = match schema_root {
    Some(root) => root
    None => directory_of(schema_path)
  }
  let text = read_ion_text(streams, schema_path)
  let read : Map[String, Array[@core.IonValue]] = Map([])
  while true {
    let missing : Ref[String?] = { val: None, }
    let resolver = (id : String) => {
      match read.get(id) {
        Some(values) => values
        None => {
          missing.val = Some(id)
          raise @core.IonError::Unsupported(
            "the import '\{id}' is not read yet",
          )
        }
      }
    }
    let schema = @schema.Schema::load_from_text(text, resolver~) catch {
      error =>
        match missing.val {
          Some(id) => {
            let import_path = "\{root}/\{id}"
            let values = @text.read_ion_datagram(
              read_ion_text(streams, import_path),
            ) catch {
              @core.IonError::Syntax(message) =>
                raise CliError("\{import_path}: \{message}")
              other => raise other
            }
            read[id] = values
            continue
          }
          None => raise error
        }
    }
    return schema
  }
  panic()
}

///|
/// The directory of a file path, or `.` when it has none (or is stdin).
fn directory_of(path : String) -> String {
  match path.rev_find("/") {
    Some(0) => "/"
    Some(index) => path.view(end_offset=index).to_owned()
    None => "."
  }
}

///|
/// Check each value of the input against a schema type, reporting each
/// violation on stderr. Fails when any value has a violation.
async fn validate(
  streams : Streams,
  schema_path : String,
  type_name : String,
  path : String,
  schema_root : String?,
) -> Int {
  let schema = load_schema(streams, schema_path, schema_root)
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
