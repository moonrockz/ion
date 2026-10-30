// Round-trip laws for the Ion codecs: for every type with `ToIon` and
// `FromIon`, decoding the encoding of a value gives back an equal value.
//
// The documented exceptions are not generated: `Some(x)` where `x` writes a
// null, and the NaN payload of a `Float`.

///|
/// Whether `value` survives `ToIon` then `FromIon`.
fn[T : @ion.ToIon + @ion.FromIon + Eq] round_trips(value : T) -> Bool {
  let back : T = @ion.FromIon::from_ion(@ion.Ion(value)) catch {
    _ => return false
  }
  back == value
}

///|
test "scalars round-trip through Ion" {
  @quickcheck.check((value : Unit) => round_trips(value))
  @quickcheck.check((value : Bool) => round_trips(value))
  @quickcheck.check((value : Byte) => round_trips(value))
  @quickcheck.check((value : Char) => round_trips(value))
  @quickcheck.check((value : Int32) => round_trips(value))
  @quickcheck.check((value : Int64) => round_trips(value))
  @quickcheck.check((value : UInt32) => round_trips(value))
  @quickcheck.check((value : UInt64) => round_trips(value))
  @quickcheck.check((value : BigInt) => round_trips(value))
  @quickcheck.check((value : String) => round_trips(value))
  @quickcheck.check((value : Bytes) => round_trips(value))
}

///|
test "integer limits round-trip through Ion" {
  assert_true(round_trips(-2147483648) && round_trips(2147483647))
  assert_true(
    round_trips(-9223372036854775808L) && round_trips(9223372036854775807L),
  )
  assert_true(round_trips(0U) && round_trips(4294967295U))
  assert_true(round_trips(0UL) && round_trips(18446744073709551615UL))
  assert_true(round_trips(b'\x00') && round_trips(b'\xFF'))
}

///|
test "floats round-trip through Ion, NaN as NaN" {
  @quickcheck.check((value : Double) => {
    let back : Double = @ion.FromIon::from_ion(@ion.Ion(value)) catch {
      _ => return false
    }
    back == value || (back.is_nan() && value.is_nan())
  })
  @quickcheck.check((value : Float) => {
    let back : Float = @ion.FromIon::from_ion(@ion.Ion(value)) catch {
      _ => return false
    }
    back == value || (back.is_nan() && value.is_nan())
  })
}

///|
test "decimals round-trip through Ion with their precision" {
  @quickcheck.check((pair : (BigInt, Int32)) => {
    let original = @ion.Decimal::Decimal(pair.0, pair.1 % 1000)
    let back : @ion.Decimal = @ion.FromIon::from_ion(@ion.Ion(original)) catch {
      _ => return false
    }
    back.to_ion_string() == original.to_ion_string()
  })
}

///|
test "timestamps round-trip through Ion with their precision" {
  @quickcheck.check((seed : ((Int32, Int32), (Int32, Int32))) => {
    let ((year, month), (day, minute)) = seed
    let original = @ion.Timestamp::Timestamp(
      year=1 + (year & 0x1FFF) % 9999,
      month=Some((month & 0x0F) % 12 + 1),
      day=Some((day & 0x1F) % 28 + 1),
      hour=Some((minute & 0x1F) % 24),
      minute=Some((minute & 0x3F) % 60),
      offset=Some(@ion.TimestampOffset::Known(minute % 1440)),
    )
    let back : @ion.Timestamp = @ion.FromIon::from_ion(@ion.Ion(original)) catch {
      _ => return false
    }
    @ion.Ion(back).equals(@ion.Ion(original))
  })
}

///|
test "symbol tokens round-trip through Ion" {
  @quickcheck.check((text : String) => round_trips(@ion.SymbolToken(text)))
  assert_true(round_trips(@ion.SymbolToken::from_sid(99)))
}

///|
test "Ion values decode as themselves" {
  for
    value in @testkit.gen_value(max_depth=6, max_width=4).samples(
      count=300,
      size=8,
    ) {
    let back : @ion.Ion = @ion.FromIon::from_ion(@ion.Ion(value))
    assert_true(back.equals(value))
  }
}

///|
test "options round-trip through Ion" {
  @quickcheck.check((value : Int32?) => round_trips(value))
  @quickcheck.check((value : String?) => round_trips(value))
  @quickcheck.check((value : Array[Bool?]) => round_trips(value))
}

///|
test "arrays and tuples round-trip through Ion" {
  @quickcheck.check((value : Array[Int32]) => round_trips(value))
  @quickcheck.check((value : Array[Array[String]]) => round_trips(value))
  @quickcheck.check((value : (Int64, String)) => round_trips(value))
  @quickcheck.check((value : ((Bool, Char), UInt32)) => {
    let ((flag, character), number) = value
    round_trips((flag, character, number))
  })
}

///|
test "maps round-trip through Ion in key order" {
  @quickcheck.check((value : Map[String, Int32]) => {
    let back : Map[String, Int32] = @ion.FromIon::from_ion(@ion.Ion(value)) catch {
      _ => return false
    }
    back.to_array() == value.to_array()
  })
  @quickcheck.check((value : Map[String, Array[(Int32, String?)]]) => {
    let back : Map[String, Array[(Int32, String?)]] = @ion.FromIon::from_ion(
      @ion.Ion(value),
    ) catch {
      _ => return false
    }
    back.to_array() == value.to_array()
  })
}

///|
test "derived JSON types round-trip through the bridges" {
  @quickcheck.check((seed : ((Int32, String), (Array[String], Int32?))) => {
    let ((id, reason), (tags, retry)) = seed
    let letter = DeadLetter::{ id, reason, tags, retry, }
    let back : DeadLetter = @ion.from_ion_via_json(@ion.to_ion_via_json(letter)) catch {
      _ => return false
    }
    back == letter
  })
}
