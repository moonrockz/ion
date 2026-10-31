// Bridges for types that derive core `ToJson` and `FromJson`: encode them as
// the Ion value of their JSON, and decode them from the JSON of an Ion value.

///|
/// An actor event payload whose JSON form is derived.
struct DeadLetter {
  id : Int32
  reason : String
  tags : Array[String]
  retry : Int32?
} derive(ToJson, FromJson, Eq, Debug)

///|
/// A bridge impl: the type gains `ToIon` and `FromIon` in one line each.
impl @ion.ToIon for DeadLetter with fn to_ion(self) {
  @ion.to_ion_via_json(self)
}

///|
impl @ion.FromIon for DeadLetter with fn from_ion(value) {
  @ion.from_ion_via_json(value)
}

///|
test "to_ion_via_json writes the Ion value of the JSON form" {
  // The derived JSON form leaves out a field that is `None`.
  let letter = { id: 7, reason: "timeout", tags: ["a"], retry: None, }
  inspect(
    @text.write_ion(@ion.to_ion_via_json(letter)),
    content=(
      #|{id: 7, reason: "timeout", tags: ["a"]}
    ),
  )
}

///|
test "from_ion_via_json reads the value that to_ion_via_json wrote" {
  let letter = { id: 7, reason: "timeout", tags: ["a", "b"], retry: Some(3), }
  let back : DeadLetter = @ion.from_ion_via_json(@ion.to_ion_via_json(letter))
  assert_eq(back, letter)
}

///|
test "from_ion_via_json reads hand-written Ion with symbols and annotations" {
  let value = @text.read_ion(
    "DeadLetter::{id: 1, reason: timeout, tags: [], retry: 2}",
  )
  let letter : DeadLetter = @ion.from_ion_via_json(value)
  assert_eq(letter, { id: 1, reason: "timeout", tags: [], retry: Some(2), })
}

///|
test "a FromJson failure keeps its message and names its path in Ion terms" {
  let value = @text.read_ion("{id: 1, reason: \"r\", tags: [\"a\", 2]}")
  let error = try (@ion.from_ion_via_json(value) : DeadLetter) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  guard error is JsonDecode(path~, message~) else {
    fail("expected JsonDecode, got \{error.message()}")
  }
  assert_eq(path, [Name("tags"), Index(1)])
  assert_false(message.is_empty())
}

///|
test "a field name made of digits stays a field name in the path" {
  let value = @text.read_ion("{'0': {x: \"a\"}}")
  let error = try
    (@ion.from_ion_via_json(value) : Map[String, Map[String, Int32]])
  catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_eq(error.path(), [Name("0"), Name("x")])
}

///|
test "an Ion to JSON failure raises MissingSymbolText, not an abort" {
  let value = @ion.Ion::from_fields([
    @ion.Field("reason", @ion.Ion(@ion.SymbolToken::from_sid(99))),
  ])
  let error = try (@ion.from_ion_via_json(value) : DeadLetter) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is MissingSymbolText(path=[Name("reason")], ..))
}

///|
test "a bridge impl composes with the containers of FromIon" {
  let value = @text.read_ion(
    "[{id: 1, reason: \"a\", tags: []}, {id: \"two\", reason: \"b\", tags: []}]",
  )
  let error = try (@ion.FromIon::from_ion(value) : Array[DeadLetter]) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_eq(error.path(), [Index(1), Name("id")])
  let letters : Array[DeadLetter] = @ion.FromIon::from_ion(
    @ion.Ion([{ id: 1, reason: "a", tags: [], retry: None, }]),
  )
  assert_eq(letters, [{ id: 1, reason: "a", tags: [], retry: None, }])
}

///|
test "a derived Option field is read from an absent field, not from null" {
  // Core's derived JSON form leaves out `None` and rejects an explicit
  // `null`, so Ion written by hand leaves the field out too.
  let absent : DeadLetter = @ion.from_ion_via_json(
    @text.read_ion("{id: 1, reason: \"r\", tags: []}"),
  )
  assert_eq(absent.retry, None)
  let null = @text.read_ion("{id: 1, reason: \"r\", tags: [], retry: null}")
  let error = try (@ion.from_ion_via_json(null) : DeadLetter) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is JsonDecode(path=[Name("retry")], ..))
  assert_eq(error.message(), "$.retry: Int::from_json: expected number")
}
