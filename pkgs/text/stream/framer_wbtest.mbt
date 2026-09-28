// White-box tests for the framer that decides when the streaming text reader
// tries a parse.

///|
/// A text whose lexical states are easy to misread: comment starts inside
/// lobs and operators, closing delimiters inside strings, escaped quotes, and
/// long strings that continue past a comment.
let framing : String =
  #|$ion_1_0 1 -2.5e0 2007-01-01T12:30+01:00 null.int nan 'a b'::c ''
  #|'it\'s' "q\"}]" '''long\''''  /* ** */ '''er''' abc a :: b
  #|{a: {{ //8= }}, b: {{ "}}" }}, c: {{ '''x}}''' '''y''' }}, 'd': []}
  #|(a / b // comment ]
  #|  (+ 1 -2) [x, (y)]) {x: '''z'''} "é ✓ 😀" last
  #|

///|
/// A reader over no source, fed by `append` instead of `fill`.
fn detached_reader() -> TextReader {
  TextReader::new(@io.MemoryReader(fn(_) { () }))
}

///|
/// Feed `text` to a reader in chunks of about `chunk` code units, never
/// splitting a surrogate pair, as UTF-8 decoding never does. After each chunk,
/// every value that a parse would settle must be taken, so the framer never
/// holds back a value that is ready. At the end, the values must match the
/// sync reader.
fn check_framing(text : String, chunk : Int) -> Unit raise {
  let reader = detached_reader()
  let values : Array[@ion.IonValue] = []
  let mut offset = 0
  while offset < text.length() {
    let mut end = if offset + chunk < text.length() {
      offset + chunk
    } else {
      text.length()
    }
    if end < text.length() && text[end - 1].is_leading_surrogate() {
      end += 1
    }
    reader.append(text[offset:end].to_owned())
    offset = end
    while true {
      let pending = reader.pending()
      let ready = @text.read_ion_prefix(pending, end_of_input=false)
      match reader.take() {
        Some(value) => values.push(value)
        None => {
          assert_true(ready is None)
          break
        }
      }
    }
  }
  reader.eof = true
  while reader.take() is Some(value) {
    values.push(value)
  }
  let expected = @text.read_ion_datagram(text)
  assert_eq(values.length(), expected.length())
  for index in 0..<expected.length() {
    assert_true(values[index].equals(expected[index]))
  }
}

///|
test "the framer never holds back a settled value" {
  for chunk in 1..<32 {
    check_framing(framing, chunk)
  }
  check_framing(framing, framing.length())
}

///|
test "no parse is tried while a large container is still open" {
  let reader = detached_reader()
  // The first code units after the top level may still settle a value, so
  // the check starts after them.
  reader.append("[1, ")
  ignore(reader.take())
  for _ in 0..<5000 {
    reader.append("1, \"]\", /* ] */ ")
    assert_false(reader.framer.at_top)
  }
  reader.append("] ")
  assert_true(reader.framer.at_top)
}

///|
test "no parse is tried while a large string or comment is still open" {
  for opening in ["\"", "'''", "/*", "{{ \"", "abc"] {
    let reader = detached_reader()
    reader.append(opening + "xyz")
    ignore(reader.take())
    for _ in 0..<1000 {
      reader.append("xyz")
      assert_false(reader.framer.at_top)
    }
  }
}
