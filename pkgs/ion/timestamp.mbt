// Ion timestamps.
//
// A timestamp is a moment in time with a precision (year, month, day, minute,
// or second), an optional fractional-second part, and — for values that carry
// a time — a local offset that may be known or explicitly unknown (`-00:00`).
//
// Timestamps are modelled field-by-field: an absent component is `None`, so
// the precision is derived from which components are present rather than kept
// as a separate sentinel.

///|
/// The precision to which an Ion timestamp is specified.
pub(all) enum TimestampPrecision {
  Year
  Month
  Day
  Minute
  Second
} derive(Eq, Hash, Debug)

///|
/// The local offset of an Ion timestamp.
pub(all) enum TimestampOffset {
  /// A known offset from UTC, in minutes east of UTC. `Z` and `+00:00` are
  /// both `Known(0)`.
  Known(Int)
  /// The "unknown local offset" written `-00:00`.
  Unknown
} derive(Eq, Hash, Debug)

///|
/// An Ion `timestamp` value.
pub struct Timestamp {
  year : Int
  month : Int?
  day : Int?
  hour : Int?
  minute : Int?
  second : Int?
  fraction : Decimal?
  offset : TimestampOffset?
} derive(Debug)

///|
/// Build a timestamp from its components. Components left as `None` reduce the
/// precision; `fraction` requires `second`, and `offset` is required for any
/// value that carries a time.
pub fn Timestamp::new(
  year~ : Int,
  month? : Int? = None,
  day? : Int? = None,
  hour? : Int? = None,
  minute? : Int? = None,
  second? : Int? = None,
  fraction? : Decimal? = None,
  offset? : TimestampOffset? = None,
) -> Timestamp {
  { year, month, day, hour, minute, second, fraction, offset, }
}

///|
/// The year component.
pub fn Timestamp::year(self : Timestamp) -> Int {
  self.year
}

///|
/// The month component (`1`-`12`), when present.
pub fn Timestamp::month(self : Timestamp) -> Int? {
  self.month
}

///|
/// The day component (`1`-`31`), when present.
pub fn Timestamp::day(self : Timestamp) -> Int? {
  self.day
}

///|
/// The hour component (`0`-`23`), when present.
pub fn Timestamp::hour(self : Timestamp) -> Int? {
  self.hour
}

///|
/// The minute component (`0`-`59`), when present.
pub fn Timestamp::minute(self : Timestamp) -> Int? {
  self.minute
}

///|
/// The second component (`0`-`59`), when present.
pub fn Timestamp::second(self : Timestamp) -> Int? {
  self.second
}

///|
/// The fractional-second component, when present.
pub fn Timestamp::fraction(self : Timestamp) -> Decimal? {
  self.fraction
}

///|
/// The local offset, when present.
pub fn Timestamp::offset(self : Timestamp) -> TimestampOffset? {
  self.offset
}

///|
/// The precision implied by the components that are present.
pub fn Timestamp::precision(self : Timestamp) -> TimestampPrecision {
  if self.second is Some(_) {
    TimestampPrecision::Second
  } else if self.minute is Some(_) {
    TimestampPrecision::Minute
  } else if self.day is Some(_) {
    TimestampPrecision::Day
  } else if self.month is Some(_) {
    TimestampPrecision::Month
  } else {
    TimestampPrecision::Year
  }
}

///|
/// Left-pad an integer with zeros to `width` digits.
fn pad_int(value : Int, width : Int) -> String {
  let text = value.to_string()
  if text.length() >= width {
    return text
  }
  let sb = StringBuilder()
  for _ in 0..<(width - text.length()) {
    sb.write_string("0")
  }
  sb.write_string(text)
  sb.to_string()
}

///|
/// Render a local offset as Ion text.
fn offset_to_text(offset : TimestampOffset) -> String {
  match offset {
    TimestampOffset::Known(0) => "Z"
    TimestampOffset::Known(minutes) => {
      let sign = if minutes < 0 { "-" } else { "+" }
      let magnitude = if minutes < 0 { -minutes } else { minutes }
      "\{sign}\{pad_int(magnitude / 60, 2)}:\{pad_int(magnitude % 60, 2)}"
    }
    TimestampOffset::Unknown => "-00:00"
  }
}

///|
/// Render the fractional seconds (`< 1`) of a decimal as a `.ddd` suffix,
/// preserving the number of digits kept by the source.
fn fraction_to_text(fraction : Decimal) -> String {
  let magnitude = if fraction.coefficient().compare_int(0) < 0 {
    fraction.coefficient().neg()
  } else {
    fraction.coefficient()
  }
  let digits = magnitude.to_string()
  let width = if fraction.exponent() < 0 { -fraction.exponent() } else { 0 }
  let padded = if digits.length() >= width {
    digits
  } else {
    let sb = StringBuilder()
    for _ in 0..<(width - digits.length()) {
      sb.write_string("0")
    }
    sb.write_string(digits)
    sb.to_string()
  }
  "." + padded
}

///|
/// Render this timestamp as Ion text.
pub fn Timestamp::to_ion_string(self : Timestamp) -> String {
  let sb = StringBuilder()
  sb.write_string(pad_int(self.year, 4))
  match self.precision() {
    TimestampPrecision::Year => sb.write_string("T")
    TimestampPrecision::Month => {
      sb.write_string("-" + pad_int(self.month.unwrap(), 2))
      sb.write_string("T")
    }
    TimestampPrecision::Day => {
      sb.write_string("-" + pad_int(self.month.unwrap(), 2))
      sb.write_string("-" + pad_int(self.day.unwrap(), 2))
    }
    TimestampPrecision::Minute => {
      sb.write_string("-" + pad_int(self.month.unwrap(), 2))
      sb.write_string("-" + pad_int(self.day.unwrap(), 2))
      sb.write_string("T")
      sb.write_string(pad_int(self.hour.unwrap(), 2))
      sb.write_string(":" + pad_int(self.minute.unwrap(), 2))
      sb.write_string(offset_to_text(self.offset.unwrap()))
    }
    TimestampPrecision::Second => {
      sb.write_string("-" + pad_int(self.month.unwrap(), 2))
      sb.write_string("-" + pad_int(self.day.unwrap(), 2))
      sb.write_string("T")
      sb.write_string(pad_int(self.hour.unwrap(), 2))
      sb.write_string(":" + pad_int(self.minute.unwrap(), 2))
      sb.write_string(":" + pad_int(self.second.unwrap(), 2))
      match self.fraction {
        Some(fraction) => sb.write_string(fraction_to_text(fraction))
        None => ()
      }
      sb.write_string(offset_to_text(self.offset.unwrap()))
    }
  }
  sb.to_string()
}

///|
/// Read exactly `count` ASCII digits at `start`, returning the value and the
/// index just past them.
fn read_fixed_uint(
  text : StringView,
  start : Int,
  count : Int,
) -> (Int, Int) raise IonError {
  let n = text.length()
  if start + count > n {
    raise IonError::Syntax("truncated timestamp")
  }
  let sb = StringBuilder()
  for index in start..<(start + count) {
    if !is_digit(text[index]) {
      raise IonError::Syntax("expected a digit in timestamp")
    }
    sb.write_view(char_view(text, index))
  }
  let value : Int = @string.parse_int(sb.to_string()) catch {
    _ => raise IonError::Syntax("invalid number in timestamp")
  }
  (value, start + count)
}

///|
/// Read the fractional-seconds digits after a `.`.
fn read_fraction(
  text : StringView,
  start : Int,
) -> (Decimal, Int) raise IonError {
  let n = text.length()
  let sb = StringBuilder()
  let mut i = start
  while i < n && is_digit(text[i]) {
    sb.write_view(char_view(text, i))
    i += 1
  }
  let digits = sb.to_string()
  if digits.is_empty() {
    raise IonError::Syntax(
      "timestamp fractional seconds need at least one digit",
    )
  }
  let coefficient = parse_digits_to_bigint(digits, false)
  (Decimal::new(coefficient, -digits.length()), i)
}

///|
/// Read a local offset: `Z`, `+HH:MM`, `-HH:MM`, or the unknown-offset form
/// `-00:00`.
fn read_offset(
  text : StringView,
  start : Int,
) -> (TimestampOffset, Int) raise IonError {
  let n = text.length()
  let mut i = start
  if i < n && text[i] == 'Z' {
    return (TimestampOffset::Known(0), i + 1)
  }
  if i >= n || (text[i] != '+' && text[i] != '-') {
    raise IonError::Syntax("timestamp with a time must have a local offset")
  }
  let negative = text[i] == '-'
  i += 1
  let (hours, next) = read_fixed_uint(text, i, 2)
  i = next
  if i >= n || text[i] != ':' {
    raise IonError::Syntax("expected ':' in timestamp offset")
  }
  i += 1
  let (minutes, next) = read_fixed_uint(text, i, 2)
  i = next
  if hours > 23 || minutes > 59 {
    raise IonError::DataModel("timestamp offset is out of range")
  }
  let total = hours * 60 + minutes
  if negative && total == 0 {
    (TimestampOffset::Unknown, i)
  } else if negative {
    (TimestampOffset::Known(-total), i)
  } else {
    (TimestampOffset::Known(total), i)
  }
}

///|
/// Parse an Ion timestamp. For example `2007T`, `2007-02-23`,
/// `2007-02-23T12:14Z`, or `2007-02-23T12:14:33.079-08:00`.
pub fn Timestamp::parse(text : StringView) -> Timestamp raise IonError {
  let n = text.length()
  if n < 5 {
    raise IonError::Syntax("timestamp is too short")
  }
  let (year, next) = read_fixed_uint(text, 0, 4)
  if year < 1 {
    raise IonError::DataModel("timestamp year must be at least 1")
  }
  let mut i = next
  if i == n {
    raise IonError::Syntax(
      "timestamp must end with 'T' unless it has day precision",
    )
  }
  if text[i] == 'T' {
    if i + 1 != n {
      raise IonError::Syntax(
        "unexpected characters after a year-precision timestamp",
      )
    }
    return Timestamp::new(year~)
  }
  if text[i] != '-' {
    raise IonError::Syntax("expected '-' in timestamp")
  }
  i += 1
  let (month, next) = read_fixed_uint(text, i, 2)
  i = next
  if month < 1 || month > 12 {
    raise IonError::DataModel("timestamp month is out of range")
  }
  if i == n {
    raise IonError::Syntax("month-precision timestamp must end with 'T'")
  }
  if text[i] == 'T' {
    if i + 1 != n {
      raise IonError::Syntax(
        "unexpected characters after a month-precision timestamp",
      )
    }
    return Timestamp::new(year~, month=Some(month))
  }
  if text[i] != '-' {
    raise IonError::Syntax("expected '-' in timestamp")
  }
  i += 1
  let (day, next) = read_fixed_uint(text, i, 2)
  i = next
  if day < 1 || day > 31 {
    raise IonError::DataModel("timestamp day is out of range")
  }
  if i == n {
    return Timestamp::new(year~, month=Some(month), day=Some(day))
  }
  if text[i] != 'T' {
    raise IonError::Syntax("expected 'T' in timestamp")
  }
  i += 1
  if i == n {
    return Timestamp::new(year~, month=Some(month), day=Some(day))
  }
  let (hour, next) = read_fixed_uint(text, i, 2)
  i = next
  if hour > 23 {
    raise IonError::DataModel("timestamp hour is out of range")
  }
  if i >= n || text[i] != ':' {
    raise IonError::Syntax("expected ':' in timestamp time")
  }
  i += 1
  let (minute, next) = read_fixed_uint(text, i, 2)
  i = next
  if minute > 59 {
    raise IonError::DataModel("timestamp minute is out of range")
  }
  let mut second : Int? = None
  let mut fraction : Decimal? = None
  if i < n && text[i] == ':' {
    i += 1
    let (value, next) = read_fixed_uint(text, i, 2)
    i = next
    if value > 59 {
      raise IonError::DataModel("timestamp second is out of range")
    }
    second = Some(value)
    if i < n && text[i] == '.' {
      i += 1
      let (value, next) = read_fraction(text, i)
      i = next
      fraction = Some(value)
    }
  }
  let (offset, next) = read_offset(text, i)
  i = next
  if i != n {
    raise IonError::Syntax("unexpected characters after timestamp")
  }
  Timestamp::new(
    year~,
    month=Some(month),
    day=Some(day),
    hour=Some(hour),
    minute=Some(minute),
    second~,
    fraction~,
    offset=Some(offset),
  )
}
