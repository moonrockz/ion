// Conformance tests for Ion Hash against the official suite.
//
// `tests/fixtures/ion_hash_tests.ion` is the conformance data published with
// the specification (<https://github.com/amazon-ion/ion-hash-test>). Each
// top-level struct carries a source value — `ion` as text, or `10n` as Ion
// binary octets — and, under `expect.identity`, the exact bytes that the
// identity hash function would observe. Those bytes are exactly `s(value)`, so
// comparing them checks the serialization directly, with no dependence on a
// particular digest function. The `10n` cases exercise the Ion binary decoder
// as well.

///|
/// The conformance cases, read from the module root (`moon test`'s cwd).
fn ion_hash_cases() -> Array[@ion.IonValue] raise {
  @text.read_ion_datagram(
    @fs.read_file_to_string("tests/fixtures/ion_hash_tests.ion"),
  )
}

///|
/// Lowercase hexadecimal of a byte sequence.
fn to_hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder()
  for index in 0..<bytes.length() {
    let value = bytes[index].to_int()
    sb.write_view(digits[value >> 4:(value >> 4) + 1])
    sb.write_view(digits[value & 0x0F:(value & 0x0F) + 1])
  }
  sb.to_string()
}

///|
/// The value of a `name` field of a struct value, if present.
fn field_value(value : @ion.IonValue, name : String) -> @ion.IonValue? {
  guard value.kind() is @ion.IonValueKind::Struct(fields) else { return None }
  for field in fields {
    if field.name().text() == Some(name) {
      return Some(field.value())
    }
  }
  None
}

///|
/// The bytes of a `(...)` S-expression of hex-int octets.
fn digest_bytes(value : @ion.IonValue) -> Bytes raise @ion.IonError {
  guard value.kind() is @ion.IonValueKind::Sexp(items) else {
    raise @ion.IonError::DataModel("expected an S-expression of octets")
  }
  let out : Array[Byte] = []
  for item in items {
    guard item.kind() is @ion.IonValueKind::Int(magnitude) else {
      raise @ion.IonError::DataModel("expected an octet")
    }
    out.push(magnitude.to_int().to_byte())
  }
  Bytes::from_array(out)
}

///|
/// The final `digest::`/`final_digest::` bytes recorded under an identity-hash
/// expectation, or `None` when the expectation carries no identity hashes.
fn expected_digest(expectation : @ion.IonValue) -> Bytes? raise @ion.IonError {
  match field_value(expectation, "identity") {
    Some(identity) =>
      match identity.kind() {
        @ion.IonValueKind::Sexp(items) => {
          let mut result : Bytes? = None
          for item in items {
            let mut is_digest = false
            for annotation in item.annotations() {
              match annotation.text() {
                Some(name) if name == "digest" || name == "final_digest" =>
                  is_digest = true
                _ => ()
              }
            }
            if is_digest {
              result = Some(digest_bytes(item))
            }
          }
          result
        }
        _ => None
      }
    None => None
  }
}

///|
/// The source value of a case: its `ion` text, or the single value encoded by
/// its `10n` Ion binary octets. The description names the source in a failure.
fn case_source(
  case : @ion.IonValue,
) -> (@ion.IonValue, String)? raise @ion.IonError {
  match field_value(case, "ion") {
    Some(source) => Some((source, @text.write_ion(source)))
    None =>
      match field_value(case, "10n") {
        Some(octets) => {
          let encoded = digest_bytes(octets)
          match @binary.read_binary(encoded) {
            [value] => Some((value, "10n " + to_hex(encoded)))
            _ =>
              raise @ion.IonError::DataModel(
                "a 10n case must encode exactly one value",
              )
          }
        }
        None => None
      }
  }
}

///|
test "Ion Hash conformance: identity serialization" {
  let cases = ion_hash_cases()
  let failures : Array[String] = []
  let mut checked = 0
  let mut with_source = 0
  let mut no_digest = 0
  let mut skipped = 0
  for index, case in cases {
    match case_source(case) {
      Some((source, description)) => {
        with_source += 1
        match field_value(case, "expect") {
          Some(expectation) =>
            match expected_digest(expectation) {
              Some(expected) => {
                checked += 1
                let actual = @hash.ion_hash_with(source, bytes => bytes)
                if to_hex(actual) != to_hex(expected) {
                  failures.push(
                    "case \{index} (\{description}): expected \{to_hex(expected)}, got \{to_hex(actual)}",
                  )
                }
              }
              None => no_digest += 1
            }
          None => no_digest += 1
        }
      }
      None => skipped += 1
    }
  }
  let result = Json::object(
    Map([
      ("suite", Json::string("ion-hash")),
      ("total", Json::number(cases.length().to_double())),
      ("passed", Json::number((checked - failures.length()).to_double())),
      ("skipped", Json::number((no_digest + skipped).to_double())),
      ("known_failures", Json::number(0)),
      ("not_applicable", Json::number(0)),
      ("unexpected", Json::number(failures.length().to_double())),
      ("stale", Json::number(0)),
      ("files", Json::number(1)),
      ("out_of_scope", Json::number(0)),
      (
        "details",
        Json::array(
          (failures +
          [
            "cases without an identity digest: \{no_digest}; cases without a source: \{skipped}",
          ]).map(Json::string),
        ),
      ),
    ]),
  )
  println("CONFORMANCE " + result.stringify())
  if !failures.is_empty() {
    let shown = if failures.length() > 10 {
      failures[:10] + ["... \{failures.length() - 10} more"]
    } else {
      failures
    }
    fail(shown.join("\n"))
  }
  // Every case that carries a source must be checked or explicitly counted as
  // lacking an identity digest, so a fixture that loses its expectations fails
  // loudly instead of being skipped past.
  assert_true(
    checked + no_digest == with_source,
    msg="\{with_source} cases carry a source, but \{checked} were checked and \{no_digest} had no identity digest",
  )
  assert_true(checked > 100, msg="expected many cases, checked \{checked}")
  println(
    "Ion Hash conformance: checked \{checked} of \{with_source}, no identity digest \{no_digest}, skipped \{skipped}",
  )
}
