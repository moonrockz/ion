# Conformance tests (`moonrockz/ion/conformance`)

A test-only package: it runs the official Ion 1.0 test data from
[amazon-ion/ion-tests](https://github.com/amazon-ion/ion-tests), checked out
as the `tests/ion-tests` git submodule. Fetch it with `mise run setup`, or
`git submodule update --init`.

The test in `ion_tests_test.mbt` reads every file under
`tests/ion-tests/iontestdata`:

- each file under `good` must read, and its values must survive a round trip
  through the text writer and through the binary writer;
- each file under `bad` must fail to read;
- in `good/equivs`, the members of each top-level sequence must be
  equivalent, and in `good/non-equivs` no two of them may be. A sequence
  annotated `embedded_documents` holds strings, each an Ion document;
- in `good/timestamp/equivTimeline`, the timestamps of each top-level
  sequence name the same instant, whatever their precision and offset.

The test in `readers_test.mbt` runs the same files through every other
reader and writer, and compares them with the sync reader above:

- the stream readers (`TextReader`, `BinaryReader`), fed in chunks of one
  octet and of 4 KiB, read the same values from a good file and fail on a bad
  one;
- `TextEventReader` gives the events of those values;
- `tokenize` covers a good text file exactly, and `parse_cst` parses it;
- the values survive the pretty writer;
- the async writers write the same octets as the sync writers.

The test in `dsl_test.mbt` runs ion-tests' `conformance/` directory, whose
cases are written in a small declarative language: a document is built from
`text`, `binary`, `ivm`, and `toplevel` fragments, branched with `then` and
`each`, and checked with `produces`, `denotes`, or `signals`. Ion 1.1 tests,
and documents that mix text and binary fragments (which the language
forbids), are counted but not run.

Skip lists name the files, `check:file` pairs, or DSL cases this
implementation does not handle yet, each with its reason. A skipped file that starts to pass fails the test, so the
list stays accurate.

The package does not build for wasm-gc, where `moonbitlang/core`'s `BigInt`
converts a number of about 5,000 digits to and from a string incorrectly.
