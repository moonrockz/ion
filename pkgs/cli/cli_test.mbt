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
  assert_eq(run.out(), "{a: 1}\n[b, 'c d']\n2.50\n")
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
  assert_eq(run.out(), "{name: \"ion\"}\nsym\n[1, 2.5]\n")
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
  assert_eq(run.out(), "{a: [1, 2.5, \"x\"]}\n")
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
    assert_eq(run.out(), "moonrockz/ion 0.3.1\n")
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
    assert_true(
      run.out().contains("Omit the file, or pass `-`, to read stdin."),
    )
  }
  let fromjson = ion(["help", "fromjson"])
  assert_eq(fromjson.status, 0)
  assert_true(
    fromjson.out().contains("Omit the file, or pass `-`, to read stdin."),
  )
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

///|
async test "--catalog supplies the shared tables that imports name" {
  let input = text(
    "$ion_symbol_table::{imports: [{name: \"abcs\", version: 2}]} $10 $11",
  )
  let catalog = "tests/ion-tests/catalog/catalog.ion"
  for args in [["--catalog", catalog, "print"], ["print", "--catalog", catalog]] {
    let run = ion(args, stdin=input)
    assert_eq(run.status, 0)
    assert_eq(run.out(), "a\nb\n")
  }
  // Without it, the import has no exact match and no max_id.
  let missing = ion(["print"], stdin=input)
  assert_eq(missing.status, 1)
  assert_true(missing.stderr.contains("abcs"))
  // A catalog that cannot be read is reported.
  let unreadable = ion(
    ["--catalog", "no-such-catalog.ion", "print"],
    stdin=input,
  )
  assert_eq(unreadable.status, 1)
  assert_eq(
    unreadable.stderr,
    "no-such-catalog.ion: no such file or directory\n",
  )
}

///|
async test "--catalog accepts shared-table informational imports" {
  let run = ion(
    ["print", "--catalog", "tests/fixtures/shared-imports-catalog.ion"],
    stdin=text(
      "$ion_symbol_table::{imports:[{name:\"example\",version:1}]} $10 $11",
    ),
  )
  assert_eq(run.status, 0)
  assert_eq(run.out(), "first\nsecond\n")
}

///|
async test "Ion text in UTF-16 and UTF-32 reads like UTF-8" {
  for encoding in ["utf16", "utf32"] {
    let run = ion(["print", "tests/ion-tests/iontestdata/good/\{encoding}.ion"])
    assert_eq(run.status, 0)
    assert_eq(run.out(), "{foo: \"bar\"}\n")
  }
  let run = ion(["print"], stdin=@utf16.encode("a::[1, 2] b", bom=true))
  assert_eq(run.out(), "a::[1, 2]\nb\n")
  // A schema in UTF-16 validates like one in UTF-8.
  let schema = @fs.read_file_to_string("tests/fixtures/person.isl")
  let validate = ion(
    ["validate", "-", "person", "tests/fixtures/person.ion"],
    stdin=@utf16.encode(schema, endianness=Big),
  )
  assert_eq(validate.status, 1)
  assert_true(
    validate.stderr.has_prefix("value 1: $.name: expected one of [string]"),
  )
}

///|
async test "validate loads the schemas a schema imports" {
  let good = text("{ lead: { name: \"Ada\" }, members: [{ name: \"Alan\" }] }")
  let run = ion(
    ["validate", "tests/fixtures/imports/team.isl", "team"],
    stdin=good,
  )
  assert_eq(run.status, 0)
  assert_eq(run.stderr, "")
  let bad = ion(
    ["validate", "tests/fixtures/imports/team.isl", "team"],
    stdin=text("{ lead: { name: 1 } }"),
  )
  assert_eq(bad.status, 1)
  assert_eq(
    bad.stderr,
    "value 0: $.lead.name: expected one of [string] but found int\n1 of 1 value(s) failed validation\n",
  )
  // --schema-root names the directory that import ids are relative to.
  let wrong_root = ion(
    [
      "validate", "--schema-root", "tests/fixtures", "tests/fixtures/imports/team.isl",
      "team",
    ],
    stdin=good,
  )
  assert_eq(wrong_root.status, 1)
  assert_eq(
    wrong_root.stderr,
    "tests/fixtures/common/people.isl: no such file or directory\n",
  )
}
