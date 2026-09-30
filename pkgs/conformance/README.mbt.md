# Conformance tests (`moonrockz/ion/conformance`)

A test-only package: it runs the official Ion 1.0 test data from
[amazon-ion/ion-tests](https://github.com/amazon-ion/ion-tests), checked out
as the `tests/ion-tests` git submodule, and the Ion Schema 1.0 and 2.0 test
data from
[amazon-ion/ion-schema-tests](https://github.com/amazon-ion/ion-schema-tests),
checked out as `tests/ion-schema-tests`. Fetch them with `mise run setup`, or
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
- the sync and async `BinaryEventReader`s give the same events for good
  binary files and binary encodings of every good text file, in chunks of
  one octet and 4 KiB; bad binary files must fail;
- `tokenize` covers a good text file exactly, and `parse_cst` parses it;
- the values survive the pretty writer;
- the async writers write the same octets as the sync writers.

The test in `dsl_test.mbt` runs ion-tests' `conformance/` directory, whose
cases are written in a small declarative language: a document is built from
`text`, `binary`, `ivm`, and `toplevel` fragments, branched with `then` and
`each`, and checked with `produces`, `denotes`, or `signals`. Ion 1.1 tests,
and documents that mix text and binary fragments (which the language
forbids), are counted but not run.

The tests in `ion_schema_tests_test.mbt` run every file under
`tests/ion-schema-tests/ion_schema_1_0` and
`tests/ion-schema-tests/ion_schema_2_0`, one test for each version. Each file
is a schema with `$test::{...}` structs among its types:

- the file's schema must load;
- each value in `should_accept_as_valid` must match the test's `type`, and
  each value in `should_reject_as_invalid` must not. The type is one of the
  file's types, or a type such as `int` that the file can refer to;
- each schema in `valid_schemas` must load, and each schema in
  `invalid_schemas`, and each type in `invalid_types`, must not.

Each type of a file loads on its own, so a type that uses an unsupported
construct makes only its own cases, and those of the types that refer to it,
unsupported. A case that needs such a construct is counted, but it is not a
pass: a schema rejected as unsupported is not correctly rejected.

Skip lists name the files, `check:file` pairs, or DSL cases this
implementation does not handle yet, each with its reason. A skipped file that
starts to pass fails the test, so the list stays accurate. The schema test
can also list known wrong answers, by case or by `$test` struct. Two ISL 1.0
cases are listed: they reject `occurs` ranges that another file of the suite
requires to load. A known failure that starts to pass fails the test too.

The package does not build for wasm-gc, where `moonbitlang/core`'s `BigInt`
converts a number of about 5,000 digits to and from a string incorrectly.
