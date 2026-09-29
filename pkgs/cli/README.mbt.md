# The `ion` command line as a library (`moonrockz/ion/cli`)

The commands of the `ion` executable, behind one function:

```mbt nocheck
pub async fn run(
  args : Array[String],  // without the program name
  stdin : &@io.Reader,
  stdout : &@io.Writer,
  stderr : &@io.Writer,
) -> Int                 // the exit status
```

The module's root package calls it with the process's arguments and standard
streams. A program can call it with its own, and tests call it with
in-memory streams. The exit status is 0 on success, 1 when a command fails
(including a validation failure), and 2 when the arguments do not make a
command. `moonbitlang/core/argparse` parses the arguments; since its own help
and version handling writes to the process's stdout and exits the process,
the command line declares its own `--help` and `--version` flags and writes
their text to the streams it was given. See the [executable's README](../README.md) for the commands.

```mbt check
///|
/// A writer that keeps what the command line writes.
struct Sink {
  mut written : Bytes
}

///|
impl @io.Writer for Sink with fn write_once(self, data, offset~, len~) {
  self.written = self.written + data[offset:offset + len].to_owned()
  len
}

///|
async test "run a command with in-memory streams" {
  let stdin = @io.MemoryReader(async fn(writer) {
    writer.write(@utf8.encode("{ name: \"Ada\" } { name: 42 }"))
  })
  defer stdin.close()
  let stdout : Sink = { written: b"", }
  let stderr : Sink = { written: b"", }
  let status = @cli.run(["json"], stdin, stdout, stderr)
  inspect(status, content="0")
  inspect(
    @utf8.decode(stdout.written),
    content=(
      #|{"name":"Ada"}
      #|{"name":42}
      #|
    ),
  )
}

///|
async test "a failing command reports on stderr" {
  let stdin = @io.MemoryReader(async fn(writer) { writer.write(b"[1, 2") })
  defer stdin.close()
  let stdout : Sink = { written: b"", }
  let stderr : Sink = { written: b"", }
  let status = @cli.run(["print"], stdin, stdout, stderr)
  inspect(status, content="1")
  inspect(
    @utf8.decode(stderr.written),
    content=(
      #|expected ',' or ']' in list
      #|
    ),
  )
}
```
