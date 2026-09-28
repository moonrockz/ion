// Black-box tests for moving a timestamp between offsets and comparing the
// instants timestamps name.

///|
/// The text of a timestamp.
fn text_of(timestamp : @ion.Timestamp) -> String {
  timestamp.to_ion_string()
}

///|
test "as_utc gives the same instant in UTC" {
  let eastern = @ion.Timestamp::parse("2024-01-01T01:30+02:00")
  inspect(text_of(eastern.as_utc()), content="2023-12-31T23:30Z")
  // An unknown offset already holds UTC components.
  let unknown = @ion.Timestamp::parse("2024-01-01T01:30:15.25-00:00")
  inspect(text_of(unknown.as_utc()), content="2024-01-01T01:30:15.25Z")
  // A date has no time and no offset to move.
  inspect(
    text_of(@ion.Timestamp::parse("2024-01-01").as_utc()),
    content="2024-01-01",
  )
}

///|
test "with_offset gives the same instant at another offset" {
  let utc = @ion.Timestamp::parse("2024-01-01T00:00:59.5Z")
  inspect(
    text_of(utc.with_offset(@ion.TimestampOffset::Known(-300))),
    content="2023-12-31T19:00:59.5-05:00",
  )
  inspect(
    text_of(utc.with_offset(@ion.TimestampOffset::Known(345))),
    content="2024-01-01T05:45:59.5+05:45",
  )
  inspect(
    text_of(utc.with_offset(@ion.TimestampOffset::Unknown)),
    content="2024-01-01T00:00:59.5-00:00",
  )
  // Across a leap day.
  inspect(
    text_of(
      @ion.Timestamp::parse("2012-02-29T23:30Z").with_offset(
        @ion.TimestampOffset::Known(60),
      ),
    ),
    content="2012-03-01T00:30+01:00",
  )
}

///|
test "moving to UTC and back restores the timestamp" {
  for
    text in [
      "2024-06-30T23:59:59.999+14:00", "0001-01-01T00:00-00:00", "2000-02-29T00:00-12:00",
    ] {
    let timestamp = @ion.Timestamp::parse(text)
    let back = timestamp.as_utc().with_offset(timestamp.offset().unwrap())
    assert_eq(text_of(back), text)
  }
}

///|
test "compare_instant ignores precision and offset" {
  let same = [
    "2007T", "2007-01-01", "2007-01-01T00:00-00:00", "2007-01-01T00:00:00.000Z",
    "2007-01-01T01:00+01:00", "2006-12-31T23:59-00:01",
  ]
  for a in same {
    for b in same {
      assert_eq(
        @ion.Timestamp::parse(a).compare_instant(@ion.Timestamp::parse(b)),
        0,
      )
    }
  }
  let earlier = @ion.Timestamp::parse("2007-01-01T00:00:00.1Z")
  let later = @ion.Timestamp::parse("2007-01-01T00:00:00.10000000000000000001Z")
  assert_eq(earlier.compare_instant(later), -1)
  assert_eq(later.compare_instant(earlier), 1)
  assert_eq(
    @ion.Timestamp::parse("2007-01-01T00:00+01:00").compare_instant(
      @ion.Timestamp::parse("2007-01-01T00:00Z"),
    ),
    -1,
  )
}
