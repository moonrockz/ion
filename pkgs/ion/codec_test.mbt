// The fixed Ion encodings of `Option`, `Char`, `Byte` and tuples, in both
// directions.

///|
test "None writes the untyped null and Some writes its value" {
  let none : Int32? = None
  assert_true(@ion.Ion(none).is_untyped_null())
  assert_true(@ion.Ion(Some(5)).equals(@ion.Ion(5)))
}

///|
test "every null reads as None, typed or untyped" {
  let untyped : String? = @ion.FromIon::from_ion(@text.read_ion("null"))
  let typed : String? = @ion.FromIon::from_ion(@text.read_ion("null.string"))
  let other : String? = @ion.FromIon::from_ion(@text.read_ion("null.int"))
  assert_eq(untyped, None)
  assert_eq(typed, None)
  assert_eq(other, None)
}

///|
test "a value that is not null reads as Some of the inner type" {
  let value : String? = @ion.FromIon::from_ion(@text.read_ion("\"x\""))
  assert_eq(value, Some("x"))
  let wrong = @text.read_ion("1")
  let error = try (@ion.FromIon::from_ion(wrong) : String?) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is TypeMismatch(expected=String, actual=Int(_), ..))
}

///|
test "Some of a value that writes a null reads back as None" {
  let nested : Int32?? = Some(None)
  let back : Int32?? = @ion.FromIon::from_ion(@ion.Ion(nested))
  assert_eq(back, None)
}

///|
test "Char writes a string of one character" {
  assert_true(@ion.Ion('é').equals(@ion.Ion("é")))
  let emoji : Char = @ion.FromIon::from_ion(@ion.Ion("🦀"))
  assert_eq(emoji, '🦀')
}

///|
test "Char rejects a string that is not exactly one character" {
  let two = @ion.Ion("ab")
  let error = try (@ion.FromIon::from_ion(two) : Char) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is WrongLength(path=[], actual=String("ab"), expected=1))
  assert_eq(error.message(), "$: expected string of length 1, found length 2")
  let empty = @ion.Ion("")
  let error = try (@ion.FromIon::from_ion(empty) : Char) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is WrongLength(expected=1, ..))
}

///|
test "Byte writes an int from 0 to 255 and reads only that range" {
  assert_true(@ion.Ion(b'\xFF').equals(@ion.Ion(255)))
  let low : Byte = @ion.FromIon::from_ion(@ion.Ion(0))
  let high : Byte = @ion.FromIon::from_ion(@ion.Ion(255))
  assert_eq(low, b'\x00')
  assert_eq(high, b'\xFF')
  let over = @ion.Ion(256)
  let error = try (@ion.FromIon::from_ion(over) : Byte) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  guard error is OutOfRange(range~, ..) else {
    fail("expected OutOfRange, got \{error.message()}")
  }
  assert_eq(range, Integers(min=0N, max=255N))
}

///|
test "a pair writes a list of two and reads only a list of two" {
  assert_true(@ion.Ion((1, "a")).equals(@text.read_ion("[1, \"a\"]")))
  let pair : (Int32, String) = @ion.FromIon::from_ion(
    @text.read_ion("[1, \"a\"]"),
  )
  assert_eq(pair, (1, "a"))
  let three = @text.read_ion("[1, 2, 3]")
  let error = try (@ion.FromIon::from_ion(three) : (Int32, Int32)) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is WrongLength(path=[], expected=2, actual=List(_)))
  assert_eq(error.message(), "$: expected list of length 2, found length 3")
}

///|
test "a triple names the index of a failing component" {
  let triple : (Int32, Bool, String) = @ion.FromIon::from_ion(
    @text.read_ion("[1, true, \"c\"]"),
  )
  assert_eq(triple, (1, true, "c"))
  let wrong = @text.read_ion("[1, true, 3]")
  let error = try
    (@ion.FromIon::from_ion(wrong) : (Int32, Bool, String))
  catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is TypeMismatch(path=[Index(2)], expected=String, ..))
}

///|
test "nested containers round-trip in key order" {
  let original : Map[String, Array[(Int32, String?)]] = {
    "b": [(1, Some("x")), (2, None)],
    "a": [],
  }
  let back : Map[String, Array[(Int32, String?)]] = @ion.FromIon::from_ion(
    @ion.Ion(original),
  )
  assert_eq(back.to_array(), original.to_array())
}
