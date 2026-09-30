// Runs the ion-tests files through the readers and writers that
// `ion_tests_test.mbt` does not use, and compares them with the sync DOM
// reader (`read_file`), which that test has already checked:
//
// - `stream`: `@text/stream.TextReader` and `@binary/stream.BinaryReader`,
//   fed in chunks of one octet and of 4 KiB, read the same values as the DOM
//   reader from a good file, and fail on a bad file;
// - `events`: `@text/stream.TextEventReader` gives the events of the DOM
//   values, as `@text.IonReader::from_values` does;
// - `binary-events`: the sync and async binary readers give the same events,
//   including binary encodings of every good text file;
// - `cst`: `@text.tokenize` covers a good text file exactly, token by token,
//   and `@text.parse_cst` parses it;
// - `pretty`: the values survive a round trip through the pretty writer;
// - `writers`: the async writers write the same octets as the sync ones.
//
// `reader_skipped` lists the checks this implementation does not pass yet,
// as `check:path`, with the reason. A file in `skipped` skips every check.

///|
/// Checks of one file that this implementation does not pass yet, as
/// `check:path` under `root`, with the reason.
let reader_skipped : Map[String, String] = Map([])

///|
/// The chunk sizes the stream readers are fed in. One octet splits every
/// token and character; 4 KiB is the common case.
let chunk_sizes : Array[Int] = [1, 4096]

///|
/// An async reader over `bytes`, delivered in chunks of `chunk` octets.
fn chunked(bytes : Bytes, chunk : Int) -> @io.MemoryReader {
  @io.MemoryReader(async fn(writer) {
    let mut offset = 0
    while offset < bytes.length() {
      let end = @cmp.minimum(offset + chunk, bytes.length())
      writer.write(bytes[offset:end].to_owned())
      offset = end
    }
  })
}

///|
/// The values a stream reader reads from `bytes` in chunks of `chunk`.
async fn stream_values(
  bytes : Bytes,
  binary : Bool,
  chunk : Int,
) -> Array[@ion.IonValue] {
  let source = chunked(bytes, chunk)
  // Closing the source stops its writer when the reader stops early.
  defer source.close()
  let values : Array[@ion.IonValue] = []
  if binary {
    let reader = @binary_stream.BinaryReader::new(source)
    while reader.next() is Some(value) {
      values.push(value)
    }
  } else {
    let reader = @text_stream.TextReader::new(source)
    while reader.next() is Some(value) {
      values.push(value)
    }
  }
  values
}

///|
/// Check the stream readers against the DOM reader: the same values from a
/// good file, and an error from a bad one.
async fn check_stream(relative : String, bytes : Bytes) -> Unit {
  let binary = relative.has_suffix(".10n")
  let bad = relative.has_prefix("bad/")
  let expected = if bad { [] } else { read_file(root + "/" + relative) }
  for chunk in chunk_sizes {
    let values = stream_values(bytes, binary, chunk) catch {
      error =>
        if bad {
          continue
        } else {
          fail("in chunks of \{chunk}: \{describe(error)}")
        }
    }
    if bad {
      fail("in chunks of \{chunk}: read a bad file: \{show(values)}")
    }
    if !same_values(values, expected) {
      fail("in chunks of \{chunk}: read \{show(values)}")
    }
  }
}

///|
/// Whether two events are the same, comparing scalar values and symbol text.
fn same_event(a : @text.IonEvent, b : @text.IonEvent) -> Bool {
  match (a, b) {
    (Scalar(x), Scalar(y)) => x.equals(y)
    (Annotation(x), Annotation(y)) | (FieldName(x), FieldName(y)) =>
      x.text() == y.text() && (x.text() is Some(_) || x.sid() == y.sid())
    _ => a.to_text() == b.to_text() && !(a is Scalar(_) || b is Scalar(_))
  }
}

///|
/// Check the streaming event reader against the events of the DOM values.
async fn check_events(bytes : Bytes, expected : Array[@ion.IonValue]) -> Unit {
  let source = chunked(bytes, 4096)
  defer source.close()
  let reader = @text_stream.TextEventReader::new(source)
  let events : Array[@text.IonEvent] = []
  while reader.next() is Some(event) {
    events.push(event)
  }
  let wanted = @text.IonReader::from_values(expected).remaining()
  check_same_events(events, wanted)
}

///|
/// Compare event kinds, scalar values, and complete symbol tokens.
fn check_same_events(
  events : Array[@text.IonEvent],
  wanted : Array[@text.IonEvent],
) -> Unit raise {
  if events.length() != wanted.length() {
    fail("\{events.length()} events, expected \{wanted.length()}")
  }
  for index in 0..<events.length() {
    if !same_event(events[index], wanted[index]) {
      fail(
        "event \{index} is \{events[index].to_text()}, expected \{wanted[index].to_text()}",
      )
    }
  }
}

///|
/// Check binary events against the text/DOM events, both synchronously and
/// across chunk boundaries. Version markers and tables emit no events.
async fn check_binary_events(
  bytes : Bytes,
  expected : Array[@ion.IonValue],
) -> Unit {
  let wanted = @text.IonReader::from_values(expected).remaining()
  check_same_events(@binary.BinaryEventReader::new(bytes).remaining(), wanted)
  for chunk in chunk_sizes {
    let source = chunked(bytes, chunk)
    defer source.close()
    let reader = @binary_stream.BinaryEventReader::new(source)
    let events : Array[@text.IonEvent] = []
    while reader.next() is Some(event) {
      events.push(event)
    }
    check_same_events(events, wanted)
  }
}

///|
/// Binary event readers must reject every bad binary corpus file.
async fn check_bad_binary_events(bytes : Bytes) -> Unit {
  let rejected = try @binary.BinaryEventReader::new(bytes) catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(rejected, msg="the sync event reader accepted bad binary")
  for chunk in chunk_sizes {
    let source = chunked(bytes, chunk)
    defer source.close()
    let reader = @binary_stream.BinaryEventReader::new(source)
    let rejected = try {
      while reader.next() is Some(_) {
        ()
      }
    } catch {
      _ => true
    } noraise {
      _ => false
    }
    assert_true(
      rejected,
      msg="the async event reader accepted bad binary in chunks of \{chunk}",
    )
  }
}

///|
/// Check that the tokens cover `text` exactly, in order, and that the syntax
/// tree parses.
fn check_cst(text : String) -> Unit raise {
  let tokens = @text.tokenize(text)
  let mut position = 0
  for token in tokens {
    if token.start() != position {
      fail("a token starts at \{token.start()}, after a gap from \{position}")
    }
    position = token.end()
  }
  if position != text.length() {
    fail("the tokens end at \{position} of \{text.length()}")
  }
  ignore(@text.parse_cst(text))
}

///|
/// Check that the values survive a round trip through the pretty writer.
fn check_pretty(values : Array[@ion.IonValue]) -> Unit raise {
  let text = @text.write_all_pretty(values)
  if !same_values(values, @text.read_ion_datagram(text)) {
    fail("the pretty round trip changed the values: \{text}")
  }
}

///|
/// A writer that keeps every octet written to it.
struct Octets {
  mut written : Bytes
}

///|
impl @io.Writer for Octets with fn write_once(self, data, offset~, len~) {
  self.written = self.written + data[offset:offset + len].to_owned()
  len
}

///|
/// Check that the async writers write the octets of the sync writers.
async fn check_writers(values : Array[@ion.IonValue]) -> Unit {
  for pretty in [false, true] {
    let sink : Octets = { written: b"", }
    let writer = @text_stream.TextWriter::new(sink, pretty~)
    for value in values {
      writer.write(value)
    }
    let expected = if pretty {
      @text.write_all_pretty(values)
    } else {
      @text.write_all(values)
    }
    if sink.written != @utf8.encode(expected) {
      fail("the text writer (pretty: \{pretty}) wrote different octets")
    }
  }
  let sink : Octets = { written: b"", }
  @binary_stream.write_all(sink, values)
  if sink.written != @binary.write_binary(values) {
    fail("the binary writer wrote different octets")
  }
}

///|
/// Run one check, returning the reason it failed, if it did.
async fn outcome(check : async () -> Unit) -> String? {
  check() catch {
    error => return Some(describe(error))
  }
  None
}

///|
async test "ion-tests through every reader and writer" {
  if !@fs.path_exists(root) {
    fail(
      "\{root} is missing; run `git submodule update --init` to fetch the Ion test data",
    )
  }
  let unexpected : Array[String] = []
  let stale : Array[String] = []
  let mut checks = 0
  let mut passed = 0
  let mut excluded = 0
  for path in files_under(root) {
    let relative = path.view(start_offset=root.length() + 1).to_owned()
    if relative.has_suffix(".md") || skipped.contains(relative) {
      continue
    }
    let bytes = @fs.read_file_to_bytes(path)
    let good = relative.has_prefix("good/")
    let text = !relative.has_suffix(".10n")
    let results : Array[(String, String?)] = []
    results.push(("stream", outcome(() => check_stream(relative, bytes))))
    if good {
      let values = read_file(path)
      let binary = if text { @binary.write_binary(values) } else { bytes }
      results.push(
        ("binary-events", outcome(() => check_binary_events(binary, values))),
      )
      if text {
        let source = @text.decode_ion_text(bytes)
        results.push(("events", outcome(() => check_events(bytes, values))))
        results.push(("cst", outcome(() => check_cst(source))))
      }
      results.push(("pretty", outcome(() => check_pretty(values))))
      results.push(("writers", outcome(() => check_writers(values))))
    } else if !text {
      results.push(
        ("binary-events", outcome(() => check_bad_binary_events(bytes))),
      )
    }
    for result in results {
      let (check, failure) = result
      let key = check + ":" + relative
      checks += 1
      match (failure, reader_skipped.get(key)) {
        (Some(reason), None) => unexpected.push("\{key}: \{reason}")
        (None, Some(_)) => {
          passed += 1
          stale.push(key)
        }
        (Some(_), Some(_)) => excluded += 1
        (None, None) => passed += 1
      }
    }
  }
  println(
    "ion-tests readers: ran \{checks} checks, skipped \{reader_skipped.length()}, \{unexpected.length()} unexpected failures",
  )
  for line in unexpected {
    println("  FAIL " + line)
  }
  for key in stale {
    println("  PASSES BUT SKIPPED " + key)
  }
  let details = unexpected + stale.map(id => "stale skip: " + id)
  for id, reason in reader_skipped {
    details.push("skip \{id}: \{reason}")
  }
  for id, reason in skipped {
    details.push("file omitted \{id}: \{reason}")
  }
  report_conformance(
    "ion-readers",
    checks,
    passed,
    skipped=excluded,
    unexpected=unexpected.length(),
    stale=stale.length(),
    out_of_scope=skipped.length(),
    details~,
  )
  assert_true(unexpected.is_empty() && stale.is_empty())
}
