// Black-box tests for the `ion` command line: each runs `@cli.run` with an
// in-memory stdin, stdout, and stderr, and checks what it writes and the
// exit status it returns.

///|
/// A writer that keeps every octet written to it.
struct Captured {
  mut bytes : Bytes
}

///|
impl @io.Writer for Captured with fn write_once(self, data, offset~, len~) {
  self.bytes = self.bytes + data[offset:offset + len].to_owned()
  len
}

///|
/// What one run of the command line did.
struct Run {
  status : Int
  stdout : Bytes
  stderr : String
}

///|
/// The text a run wrote to stdout.
fn Run::out(self : Run) -> String {
  @utf8.decode(self.stdout) catch {
    _ => "<not UTF-8>"
  }
}

///|
/// Run the command line with `args` and `stdin`.
async fn ion(args : Array[String], stdin? : Bytes = b"") -> Run {
  let input = @io.MemoryReader(async fn(writer) { writer.write(stdin) })
  defer input.close()
  let stdout : Captured = { bytes: b"", }
  let stderr : Captured = { bytes: b"", }
  let status = @cli.run(args, input, stdout, stderr)
  { status, stdout: stdout.bytes, stderr: @utf8.decode(stderr.bytes), }
}

///|
/// Ion text encoded as UTF-8, for stdin.
fn text(ion : String) -> Bytes {
  @utf8.encode(ion)
}

///|
async test "print writes each value as Ion text, one per line" {
  let run = ion(["print"], stdin=text("{ a: 1 } [ b , 'c d' ] 2.50"))
  assert_eq(run.status, 0)
  assert_eq(run.out(), "{a: 1}\n[b, 'c d']\n250d-2\n")
  assert_eq(run.stderr, "")
  // With no arguments, the command line prints stdin.
  assert_eq(ion([], stdin=text("1 2")).out(), "1\n2\n")
  // `-` names stdin.
  assert_eq(ion(["print", "-"], stdin=text("x")).out(), "x\n")
}

///|
async test "print reads a file, and Ion binary as well as text" {
  let expected = @text.write_all(
      @text.read_ion_datagram(
        @fs.read_file_to_string("tests/fixtures/sample.ion"),
      ),
    ) +
    "\n"
  assert_eq(ion(["print", "tests/fixtures/sample.ion"]).out(), expected)
  let values = @text.read_ion_datagram("{ name: \"ion\" } sym [1, 2.5]")
  let run = ion(["print"], stdin=@binary.write_binary(values))
  assert_eq(run.out(), "{name: \"ion\"}\nsym\n[1, 25d-1]\n")
}

///|
async test "print --binary writes Ion binary" {
  let values = @text.read_ion_datagram("{ name: \"ion\", tags: [a, b] } a c::d")
  let run = ion(
    ["print", "--binary"],
    stdin=text("{ name: \"ion\", tags: [a, b] } a c::d"),
  )
  assert_eq(run.status, 0)
  assert_true(@binary.has_version_marker(run.stdout[:], 0))
  let read_back = @binary.read_binary(run.stdout)
  assert_eq(read_back.length(), values.length())
  for index in 0..<values.length() {
    assert_true(read_back[index].equals(values[index]))
  }
  // And back to text through the command line.
  assert_eq(
    ion(["print"], stdin=run.stdout).out(),
    "{name: \"ion\", tags: [a, b]}\na\nc::d\n",
  )
}

///|
async test "print --pretty indents containers" {
  let run = ion(["print", "--pretty"], stdin=text("{ a: [1, 2] } 3"))
  assert_eq(run.out(), "{\n  a: [\n    1,\n    2\n  ]\n}\n3\n")
}

///|
async test "an empty input prints nothing" {
  let run = ion(["print"])
  assert_eq(run.status, 0)
  assert_eq(run.out(), "")
  assert_eq(ion(["print", "--binary"]).stdout, b"")
}

///|
async test "json writes each value as JSON, one per line" {
  let run = ion(
    ["json"],
    stdin=text("{ a: 1.50, t: 2007-01-01T, s: sym } null.int"),
  )
  assert_eq(run.status, 0)
  assert_eq(
    run.out(),
    "{\"a\":1.50,\"t\":\"2007-01-01\",\"s\":\"sym\"}\nnull\n",
  )
}

///|
async test "fromjson reads JSON and writes Ion" {
  let run = ion(["fromjson"], stdin=text("{\"a\": [1, 2.5, \"x\"]}"))
  assert_eq(run.status, 0)
  assert_eq(run.out(), "{a: [1, 25d-1, \"x\"]}\n")
  let bad = ion(["fromjson"], stdin=text("{\"a\": "))
  assert_eq(bad.status, 1)
  assert_eq(bad.out(), "")
  assert_true(bad.stderr.length() > 0)
}

///|
async test "hash writes each value's Ion Hash" {
  let run = ion(["hash"], stdin=text("{ a: 1 } b"))
  assert_eq(run.status, 0)
  let expected = [@text.read_ion("{ a: 1 }"), @text.read_ion("b")]
    .map(value => @hash.ion_hash_hex(value) catch { _ => "" })
    .join("\n") +
    "\n"
  assert_eq(run.out(), expected)
}

///|
async test "validate reports each violation and fails" {
  let run = ion([
    "validate", "tests/fixtures/person.isl", "person", "tests/fixtures/person.ion",
  ])
  assert_eq(run.status, 1)
  assert_eq(run.out(), "")
  assert_eq(
    run.stderr,
    "value 1: $.name: expected one of [string] but found int\n1 of 2 value(s) failed validation\n",
  )
  let valid = ion(
    ["validate", "tests/fixtures/person.isl", "person"],
    stdin=text("{ name: \"Ada\" }"),
  )
  assert_eq(valid.status, 0)
  assert_eq(valid.stderr, "")
}

///|
async test "a missing or unreadable input is reported in plain words" {
  let missing = ion(["print", "no-such-file.ion"])
  assert_eq(missing.status, 1)
  assert_eq(missing.stderr, "no-such-file.ion: no such file or directory\n")
  let directory = ion(["print", "tests/fixtures"])
  assert_eq(directory.status, 1)
  assert_eq(directory.stderr, "tests/fixtures: cannot be read\n")
}

///|
async test "an error stops a command after the values before it" {
  let run = ion(["print"], stdin=text("1 2 [3, "))
  assert_eq(run.status, 1)
  assert_eq(run.out(), "1\n2\n")
  assert_true(run.stderr.length() > 0)
}

///|
async test "version and help" {
  for args in [["version"], ["--version"], ["-V"]] {
    let run = ion(args)
    assert_eq(run.status, 0)
    assert_eq(run.out(), "moonrockz/ion 0.1.0\n")
  }
  for args in [["help"], ["--help"], ["-h"]] {
    let run = ion(args)
    assert_eq(run.status, 0)
    assert_true(run.out().has_prefix("Usage: ion [options] [command]\n"))
    assert_true(run.out().contains("  validate  "))
  }
  // Help for one command, asked for either way.
  for args in [["help", "print"], ["print", "--help"]] {
    let run = ion(args)
    assert_eq(run.status, 0)
    assert_true(run.out().has_prefix("Usage: ion print [options] [file]\n"))
    assert_true(run.out().contains("--binary"))
  }
}

///|
async test "arguments that do not make a command exit with status 2" {
  for
    args in [
      ["frobnicate"],
      ["print", "--bogus"],
      ["print", "--binary", "--pretty"],
      ["print", "a.ion", "b.ion"],
      ["validate", "schema.isl"],
      ["help", "nosuch"],
    ] {
    let run = ion(args)
    assert_eq(run.status, 2)
    assert_eq(run.out(), "")
    assert_true(run.stderr.has_prefix("error: "))
  }
  // The error comes with the help of the command it concerns.
  let run = ion(["validate", "schema.isl"])
  assert_true(
    run.stderr.contains(
      "Usage: ion validate [options] <schema-file> <type-name> [file]",
    ),
  )
}

///|
async test "validate rejects a type the schema does not define" {
  let run = ion([
    "validate", "tests/fixtures/person.isl", "nosuchtype", "tests/fixtures/person.ion",
  ])
  assert_eq(run.status, 1)
  assert_eq(run.stderr, "tests/fixtures/person.isl: no type named nosuchtype\n")
}
