// Decoding MoonBit values from Ion with `FromIon`.
//
// Each type reads exactly the Ion type that its `ToIon` writes. Every other
// Ion type, every null and every number outside the target's range raises a
// `FromIonError` that names the value path and keeps the value that failed.

///|
/// Parse one Ion value from text.
fn ion(text : String) -> @ion.Ion raise {
  @text.read_ion(text)
}

///|
test "Bool reads an Ion bool" {
  let value : Bool = @ion.FromIon::from_ion(ion("true"))
  assert_eq(value, true)
}

///|
test "annotations on the decoded value are ignored" {
  let value : Int32 = @ion.FromIon::from_ion(ion("a::b::5"))
  assert_eq(value, 5)
}

///|
test "a typed null is a type mismatch that keeps the null type" {
  let result_value = ion("null.int")
  let result = try (@ion.FromIon::from_ion(result_value) : Int32) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(result is TypeMismatch(path=[], expected=Int, actual=Null(Int)))
}

///|
test "an untyped null is a type mismatch for a non-null type" {
  let result_value = ion("null")
  let result = try (@ion.FromIon::from_ion(result_value) : Bool) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(result is TypeMismatch(path=[], expected=Bool, actual=Null(Null)))
}

///|
test "Unit reads only the untyped null" {
  let unit : Unit = @ion.FromIon::from_ion(ion("null"))
  assert_eq(unit, ())
  let typed_value = ion("null.string")
  let typed = try (@ion.FromIon::from_ion(typed_value) : Unit) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(typed is TypeMismatch(expected=Null, actual=Null(String), ..))
}

///|
test "Int reads an Ion int at both limits of its range" {
  let low : Int32 = @ion.FromIon::from_ion(ion("-2147483648"))
  let high : Int32 = @ion.FromIon::from_ion(ion("2147483647"))
  assert_eq(low, -2147483648)
  assert_eq(high, 2147483647)
}

///|
test "Int rejects an Ion int one past its range and states the range" {
  let result_value = ion("2147483648")
  let result = try (@ion.FromIon::from_ion(result_value) : Int32) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  guard result is OutOfRange(path=[], actual=Int(number), range~) else {
    fail("expected OutOfRange, got \{result.message()}")
  }
  assert_eq(number, 2147483648N)
  assert_eq(range, Integers(min=-2147483648N, max=2147483647N))
}

///|
test "Int64 reads an Ion int at both limits of its range" {
  let low : Int64 = @ion.FromIon::from_ion(ion("-9223372036854775808"))
  let high : Int64 = @ion.FromIon::from_ion(ion("9223372036854775807"))
  assert_eq(low, -9223372036854775808L)
  assert_eq(high, 9223372036854775807L)
  let over_value = ion("9223372036854775808")
  let over = try (@ion.FromIon::from_ion(over_value) : Int64) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(over is OutOfRange(..))
}

///|
test "UInt reads zero to 4294967295 and rejects a negative int" {
  let low : UInt32 = @ion.FromIon::from_ion(ion("0"))
  let high : UInt32 = @ion.FromIon::from_ion(ion("4294967295"))
  assert_eq(low, 0U)
  assert_eq(high, 4294967295U)
  let negative_value = ion("-1")
  let negative = try (@ion.FromIon::from_ion(negative_value) : UInt32) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  guard negative is OutOfRange(range~, ..) else {
    fail("expected OutOfRange, got \{negative.message()}")
  }
  assert_eq(range, Integers(min=0N, max=4294967295N))
  let over_value = ion("4294967296")
  let over = try (@ion.FromIon::from_ion(over_value) : UInt32) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(over is OutOfRange(..))
}

///|
test "UInt64 reads zero to 18446744073709551615 and rejects a negative int" {
  let high : UInt64 = @ion.FromIon::from_ion(ion("18446744073709551615"))
  assert_eq(high, 18446744073709551615UL)
  let negative_value = ion("-1")
  let negative = try (@ion.FromIon::from_ion(negative_value) : UInt64) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(negative is OutOfRange(..))
  let over_value = ion("18446744073709551616")
  let over = try (@ion.FromIon::from_ion(over_value) : UInt64) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(over is OutOfRange(..))
}

///|
test "BigInt reads an Ion int of any size" {
  let value : BigInt = @ion.FromIon::from_ion(
    ion("-123456789012345678901234567890"),
  )
  assert_eq(value, -123456789012345678901234567890N)
}

///|
test "Double reads an Ion float, including nan and the infinities" {
  let value : Double = @ion.FromIon::from_ion(ion("2.5e0"))
  assert_eq(value, 2.5)
  let inf : Double = @ion.FromIon::from_ion(ion("-inf"))
  assert_true(inf.is_inf() && inf < 0.0)
  let nan : Double = @ion.FromIon::from_ion(ion("nan"))
  assert_true(nan.is_nan())
}

///|
test "Double rejects an Ion decimal and an Ion int" {
  let decimal_value = ion("1.5")
  let decimal = try (@ion.FromIon::from_ion(decimal_value) : Double) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(decimal is TypeMismatch(expected=Float, actual=Decimal(_), ..))
  let int_value = ion("1")
  let int = try (@ion.FromIon::from_ion(int_value) : Double) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(int is TypeMismatch(expected=Float, actual=Int(_), ..))
}

///|
test "Float rounds an Ion float to the nearest Float" {
  let value : Float = @ion.FromIon::from_ion(ion("0.1e0"))
  assert_eq(value, Float::from_double(0.1))
  let inf : Float = @ion.FromIon::from_ion(ion("+inf"))
  assert_true(inf.is_inf())
}

///|
test "Float rejects a finite Ion float that overflows a Float" {
  let result_value = ion("1e39")
  let result = try (@ion.FromIon::from_ion(result_value) : Float) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(result is OutOfRange(range=Float32, actual=Float(_), ..))
}

///|
test "String reads an Ion string but not an Ion symbol" {
  let value : String = @ion.FromIon::from_ion(ion("\"abc\""))
  assert_eq(value, "abc")
  let symbol_value = ion("abc")
  let symbol = try (@ion.FromIon::from_ion(symbol_value) : String) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(
    symbol is TypeMismatch(path=[], expected=String, actual=Symbol(_)),
  )
}

///|
test "SymbolToken reads an Ion symbol, with or without text" {
  let named : @ion.SymbolToken = @ion.FromIon::from_ion(ion("abc"))
  assert_eq(named.text(), Some("abc"))
  let unknown : @ion.SymbolToken = @ion.FromIon::from_ion(
    @ion.Ion(@ion.SymbolToken::from_sid(99)),
  )
  assert_eq(unknown.sid(), Some(99))
}

///|
test "Bytes reads an Ion blob but not an Ion clob" {
  let value : Bytes = @ion.FromIon::from_ion(ion("{{aGk=}}"))
  assert_eq(value, b"hi")
  let clob_value = ion("{{\"hi\"}}")
  let clob = try (@ion.FromIon::from_ion(clob_value) : Bytes) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(clob is TypeMismatch(expected=Blob, actual=Clob(_), ..))
}

///|
test "Decimal reads an Ion decimal and keeps its precision" {
  let value : @ion.Decimal = @ion.FromIon::from_ion(ion("1.50"))
  assert_eq(value.to_ion_string(), "1.50")
  let int_value = ion("1")
  let int = try (@ion.FromIon::from_ion(int_value) : @ion.Decimal) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(int is TypeMismatch(expected=Decimal, ..))
}

///|
test "Timestamp reads an Ion timestamp and keeps its precision" {
  let value : @ion.Timestamp = @ion.FromIon::from_ion(ion("2024-02-29T"))
  assert_eq(value.to_ion_string(), "2024-02-29")
}

///|
test "Ion reads any value unchanged, annotations included" {
  let original = ion("a::{b: null.int}")
  let value : @ion.Ion = @ion.FromIon::from_ion(original)
  assert_true(value.equals(original))
}

///|
test "the error message renders the path, the expectation and the value" {
  let mismatch = @ion.FromIonError::TypeMismatch(
    path=[Name("events"), Index(1)],
    expected=Int,
    actual=Null(Int),
  )
  assert_eq(mismatch.message(), "$.events[1]: expected int, found null.int")
  let range = @ion.FromIonError::OutOfRange(
    path=[],
    actual=Int(300N),
    range=Integers(min=0N, max=255N),
  )
  assert_eq(range.message(), "$: int 300 is outside the range 0 to 255")
}

///|
test "within puts a segment in front of the error path" {
  let error = @ion.FromIonError::DuplicateField(path=[Index(0)], name="a")
  let outer = error.within(Name("items"))
  assert_eq(outer.path(), [Name("items"), Index(0)])
}

///|
test "Array reads an Ion list element by element" {
  let value : Array[Int32] = @ion.FromIon::from_ion(ion("[1, 2, 3]"))
  assert_eq(value, [1, 2, 3])
}

///|
test "Array rejects an S-expression" {
  let sexp = ion("(1 2)")
  let error = try (@ion.FromIon::from_ion(sexp) : Array[Int32]) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is TypeMismatch(path=[], expected=List, actual=Sexp(_)))
}

///|
test "Array adds the element index to the path of an element error" {
  let list = ion("[1, \"two\", 3]")
  let error = try (@ion.FromIon::from_ion(list) : Array[Int32]) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is TypeMismatch(path=[Index(1)], expected=Int, ..))
}

///|
test "Map reads an Ion struct and keeps the field order" {
  let value : Map[String, Int32] = @ion.FromIon::from_ion(ion("{b: 2, a: 1}"))
  assert_eq(value.to_array(), [("b", 2), ("a", 1)])
}

///|
test "Map names the field and the index of a nested failure" {
  let value = ion("{events: [1, \"x\"]}")
  let error = try
    (@ion.FromIon::from_ion(value) : Map[String, Array[Int32]])
  catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_eq(error.path(), [Name("events"), Index(1)])
  assert_eq(error.message(), "$.events[1]: expected int, found string")
}

///|
test "Map rejects a struct with a repeated field name" {
  let value = ion("{a: 1, a: 2}")
  let error = try (@ion.FromIon::from_ion(value) : Map[String, Int32]) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  assert_true(error is DuplicateField(path=[], name="a"))
}

///|
test "Map rejects a field name with no known text" {
  let value = @ion.Ion::from_fields([
    @ion.Field::from_token(@ion.SymbolToken::from_sid(99), @ion.Ion(1)),
  ])
  let error = try (@ion.FromIon::from_ion(value) : Map[String, Int32]) catch {
    error => error
  } noraise {
    _ => fail("expected a decode error")
  }
  guard error is MissingSymbolText(path=[], token~) else {
    fail("expected MissingSymbolText, got \{error.message()}")
  }
  assert_eq(token.sid(), Some(99))
}

///|
test "Map resolves a field name that is an Ion 1.0 system symbol ID" {
  let value = @ion.Ion::from_fields([
    @ion.Field::from_token(@ion.SymbolToken::from_sid(4), @ion.Ion(1)),
  ])
  let map : Map[String, Int32] = @ion.FromIon::from_ion(value)
  assert_eq(map.to_array(), [("name", 1)])
}
