// Runs the Ion 1.0 test data from https://github.com/amazon-ion/ion-tests,
// checked out as the `tests/ion-tests` submodule, as its README describes:
//
// - every file under `good` reads without error, and its values survive a
//   round trip through the text writer and through the binary writer;
// - every file under `bad` fails to read;
// - in `good/equivs`, the values of each top-level sequence are equivalent,
//   and in `good/non-equivs`, no two of them are. A sequence annotated
//   `embedded_documents` holds strings, each an Ion document to compare;
// - in `good/timestamp/equivTimeline`, the timestamps of each top-level
//   sequence name the same instant, whatever their precision and offset.
//
// `skipped` lists the files this implementation does not handle yet, each
// with the reason. A skipped file that starts to pass fails the test, so the
// list stays accurate.

///|
/// The Ion 1.0 test data, relative to the module root.
let root : String = "tests/ion-tests/iontestdata"

///|
/// Files this implementation does not handle yet, by path under `root`, with
/// the reason.
let skipped : Map[String, String] = Map([])

///|
/// Every file under `dir`, recursively, in a stable order.
fn files_under(dir : String) -> Array[String] raise {
  let files : Array[String] = []
  let entries = @fs.read_dir(dir).to_owned()
  entries.sort()
  for entry in entries {
    let path = dir + "/" + entry
    if @fs.is_dir(path) {
      files.append(files_under(path))
    } else {
      files.push(path)
    }
  }
  files
}

///|
/// The values of a test file: Ion binary for `.10n`, and Ion text otherwise,
/// in the encoding its first octets show.
fn read_file(path : String) -> Array[@ion.IonValue] raise {
  let bytes = @fs.read_file_to_bytes(path)
  if path.has_suffix(".10n") {
    @binary.read_binary(bytes[:])
  } else {
    @text.read_ion_datagram(@text.decode_ion_text(bytes))
  }
}

///|
/// Whether two datagrams hold equivalent values in order.
fn same_values(a : Array[@ion.IonValue], b : Array[@ion.IonValue]) -> Bool {
  a.length() == b.length() &&
  a.iter().zip(b.iter()).all(pair => pair.0.equals(pair.1))
}

///|
/// The message of a failure.
fn describe(error : Error) -> String {
  match error {
    @ion.IonError::Syntax(message) => "syntax: " + message
    @ion.IonError::DataModel(message) => "data model: " + message
    @ion.IonError::Unsupported(message) => "unsupported: " + message
    @ion.IonError::LimitExceeded(message) => "limit exceeded: " + message
    Failure(message) =>
      match message.find("FAILED: ") {
        Some(index) => message.view(start_offset=index + 8).to_owned()
        None => message
      }
    _ => error.to_string()
  }
}

///|
/// A short rendering of values for failure messages.
fn show(values : Array[@ion.IonValue]) -> String {
  @text.write_all(values) catch {
    _ => "<unwritable>"
  }
}

///|
/// Check that `values` survive a round trip through both writers.
fn check_round_trips(values : Array[@ion.IonValue]) -> Unit raise {
  let text = @text.write_all(values)
  let from_text = @text.read_ion_datagram(text)
  if !same_values(values, from_text) {
    fail("text round trip changed the values: \{text}")
  }
  let from_binary = @binary.read_binary(@binary.write_binary(values))
  if !same_values(values, from_binary) {
    fail("binary round trip changed the values: \{show(from_binary)}")
  }
}

///|
/// The members of a top-level sequence to compare: its values, or for an
/// `embedded_documents` sequence, the documents its strings hold.
fn members(sequence : @ion.IonValue) -> Array[Array[@ion.IonValue]] raise {
  let items = match sequence.kind() {
    List(items) | Sexp(items) => items
    _ => fail("a top-level value is not a sequence: \{show([sequence])}")
  }
  let embedded = sequence
    .annotations()
    .iter()
    .any(annotation => annotation.text() == Some("embedded_documents"))
  items.map(item => {
    if embedded {
      match item.kind() {
        String(document) => @text.read_ion_datagram(document)
        _ => fail("an embedded document is not a string")
      }
    } else {
      [item]
    }
  })
}

///|
/// Check that the members of each top-level sequence are all equivalent, or,
/// when `equivalent` is false, that no two of them are.
fn check_equivalence(
  values : Array[@ion.IonValue],
  equivalent : Bool,
) -> Unit raise {
  for sequence in values {
    let documents = members(sequence)
    for i in 0..<documents.length() {
      for j in (i + 1)..<documents.length() {
        let same = same_values(documents[i], documents[j])
        if same != equivalent {
          let relation = if equivalent { "differ" } else { "are equivalent" }
          fail(
            "members \{i} and \{j} \{relation}: \{show(documents[i])} vs \{show(documents[j])}",
          )
        }
      }
    }
  }
}

///|
/// Check that the timestamps of each top-level sequence name the same
/// instant. They need not be equivalent: they differ in precision and offset.
fn check_same_instants(values : Array[@ion.IonValue]) -> Unit raise {
  for sequence in values {
    let timestamps : Array[@ion.Timestamp] = []
    match sequence.kind() {
      List(items) | Sexp(items) =>
        for item in items {
          match item.kind() {
            Timestamp(timestamp) => timestamps.push(timestamp)
            _ => fail("a timeline member is not a timestamp: \{show([item])}")
          }
        }
      _ => fail("a top-level value is not a sequence: \{show([sequence])}")
    }
    for i in 0..<timestamps.length() {
      for j in (i + 1)..<timestamps.length() {
        if timestamps[i].compare_instant(timestamps[j]) != 0 {
          fail(
            "\{timestamps[i].to_ion_string()} and \{timestamps[j].to_ion_string()} name different instants",
          )
        }
      }
    }
  }
}

///|
/// Check one file, raising with the reason when it does not behave as its
/// directory requires.
fn check_file(relative : String) -> Unit raise {
  let path = root + "/" + relative
  if relative.has_prefix("bad/") {
    let values = read_file(path) catch { _ => return }
    fail("read without error: \{show(values)}")
  }
  let values = read_file(path)
  check_round_trips(values)
  if relative.has_prefix("good/timestamp/equivTimeline/") {
    check_same_instants(values)
  }
  if relative.has_prefix("good/equivs/") {
    check_equivalence(values, true)
  } else if relative.has_prefix("good/non-equivs/") {
    check_equivalence(values, false)
  }
}

///|
test "ion-tests" {
  if !@fs.path_exists(root) {
    fail(
      "\{root} is missing; run `git submodule update --init` to fetch the Ion test data",
    )
  }
  let unexpected : Array[String] = []
  let stale : Array[String] = []
  let mut checked = 0
  let mut passed = 0
  let mut excluded = 0
  for path in files_under(root) {
    let relative = path.view(start_offset=root.length() + 1).to_owned()
    if relative.has_suffix(".md") {
      continue
    }
    checked += 1
    let failure = try check_file(relative) catch {
      error => Some(describe(error))
    } noraise {
      _ => None
    }
    match (failure, skipped.get(relative)) {
      (Some(reason), None) => unexpected.push("\{relative}: \{reason}")
      (None, Some(_)) => {
        passed += 1
        stale.push(relative)
      }
      (Some(_), Some(_)) => excluded += 1
      (None, None) => passed += 1
    }
  }
  println(
    "ion-tests: checked \{checked} files, skipped \{skipped.length()}, \{unexpected.length()} unexpected failures",
  )
  for line in unexpected {
    println("  FAIL " + line)
  }
  for relative in stale {
    println("  PASSES BUT SKIPPED " + relative)
  }
  let details = unexpected + stale.map(id => "stale skip: " + id)
  for id, reason in skipped {
    details.push("skip \{id}: \{reason}")
  }
  report_conformance(
    "ion-files",
    checked,
    passed,
    skipped=excluded,
    unexpected=unexpected.length(),
    stale=stale.length(),
    details~,
  )
  assert_true(unexpected.is_empty() && stale.is_empty())
}
