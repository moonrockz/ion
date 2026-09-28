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
  annotated `embedded_documents` holds strings, each an Ion document.

A skip list names the files this implementation does not handle yet, each
with its reason. A skipped file that starts to pass fails the test, so the
list stays accurate.

The package does not build for wasm-gc, where `moonbitlang/core`'s `BigInt`
converts a number of about 5,000 digits to and from a string incorrectly.
