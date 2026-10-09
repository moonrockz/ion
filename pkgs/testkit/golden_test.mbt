// Golden output of every walker for the values in
// tests/fixtures/walkers/values.ion. The stack-safe ports must keep it byte
// for byte; never refresh it to make a port pass.

///|
fn hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for byte in bytes {
    let value = byte.to_int()
    out.write_view(digits[value >> 4:(value >> 4) + 1])
    out.write_view(digits[value & 0xF:(value & 0xF) + 1])
  }
  out.to_string()
}

///|
/// The output of `render`, or the error message it raises.
fn outcome(render : () -> String raise @ion.IonError) -> String {
  try render() catch {
    error => "error: " + error.message()
  } noraise {
    text => text
  }
}

///|
/// The events of `value`, with the text of every scalar, annotation and
/// field name.
fn event_trace(value : @ion.IonValue) -> String raise @ion.IonError {
  let parts : Array[String] = []
  for event in @text.IonReader::from_value(value).remaining() {
    parts.push(
      match event {
        Scalar(scalar) => "Scalar(" + @text.write_fragment(scalar) + ")"
        Annotation(token) => "Annotation(" + @text.symbol_to_text(token) + ")"
        FieldName(token) => "FieldName(" + @text.symbol_to_text(token) + ")"
        other => other.to_text()
      },
    )
  }
  parts.join(" ")
}

///|
test "walker goldens" (t : @test.Test) {
  let values = @text.read_ion_datagram(
    @fs.read_file_to_string("tests/fixtures/walkers/values.ion"),
  )
  for index, value in values {
    t.writeln("== value \{index}")
    t.writeln("text: " + outcome(() => @text.write_ion(value)))
    t.writeln("pretty:\n" + outcome(() => @text.write_ion_pretty(value)))
    t.writeln(
      "binary: " + outcome(() => hex(@binary.write_binary_value(value))),
    )
    t.writeln("hash: " + outcome(() => @hash.ion_hash_hex(value)))
    t.writeln("json: " + outcome(() => @json.write_json(value)))
    t.writeln("events: " + outcome(() => event_trace(value)))
  }
  t.snapshot(filename="walkers.txt")
}
