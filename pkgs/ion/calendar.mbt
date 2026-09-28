// Proleptic Gregorian calendar arithmetic and the UTC/local conversion for
// timestamps.
//
// Ion text keeps a timestamp's components in local time plus the local offset,
// while Ion binary keeps them in UTC. Transcoding between the two therefore
// shifts the date and time by the offset, rolling over days, months, leap days,
// and years. `with_offset` moves a timestamp to another offset, keeping the
// instant it names, and `compare_instant` compares those instants.

///|
/// Whether `year` is a leap year in the proleptic Gregorian calendar.
pub fn is_leap_year(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
/// The number of days in `month` of `year`.
pub fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(year) { 29 } else { 28 }
    _ => 30
  }
}

///|
/// The civil date `days` days after `year-month-day`, rolling over months and
/// years. `days` may be negative.
pub fn shift_date(
  year : Int,
  month : Int,
  day : Int,
  days : Int,
) -> (Int, Int, Int) {
  let mut y = year
  let mut m = month
  let mut d = day + days
  while d < 1 {
    m -= 1
    if m < 1 {
      m = 12
      y -= 1
    }
    d += days_in_month(y, m)
  }
  while d > days_in_month(y, m) {
    d -= days_in_month(y, m)
    m += 1
    if m > 12 {
      m = 1
      y += 1
    }
  }
  (y, m, d)
}

///|
/// Integer division that rounds toward negative infinity, so a minute count
/// before midnight maps onto the previous day.
fn floor_div(value : Int, divisor : Int) -> Int {
  let quotient = value / divisor
  if value % divisor != 0 && value < 0 {
    quotient - 1
  } else {
    quotient
  }
}

///|
/// The timestamp's date and time moved by `minutes`, with `offset`. A
/// timestamp with no time of day is returned unchanged.
fn shift_minutes(
  timestamp : Timestamp,
  minutes : Int,
  offset : TimestampOffset,
) -> Timestamp {
  match
    (timestamp.month(), timestamp.day(), timestamp.hour(), timestamp.minute()) {
    (Some(month), Some(day), Some(hour), Some(minute)) => {
      let total = hour * 60 + minute + minutes
      let day_shift = floor_div(total, 1440)
      let minutes_of_day = total - day_shift * 1440
      let (year, month, day) = shift_date(
        timestamp.year(),
        month,
        day,
        day_shift,
      )
      Timestamp::new(
        year~,
        month=Some(month),
        day=Some(day),
        hour=Some(minutes_of_day / 60),
        minute=Some(minutes_of_day % 60),
        second=timestamp.second(),
        fraction=timestamp.fraction(),
        offset=Some(offset),
      )
    }
    _ => timestamp
  }
}

///|
/// The minutes east of UTC that an offset shifts local time by. An unknown
/// offset means the components are in UTC.
fn offset_minutes(offset : TimestampOffset?) -> Int {
  match offset {
    Some(TimestampOffset::Known(minutes)) => minutes
    _ => 0
  }
}

///|
/// The same instant expressed at `offset`: the date and time move by the
/// difference between the offsets. An unknown offset reads and writes the
/// components in UTC. A timestamp with no time of day has no offset, and is
/// returned unchanged.
pub fn Timestamp::with_offset(
  self : Timestamp,
  offset : TimestampOffset,
) -> Timestamp {
  let minutes = offset_minutes(Some(offset)) - offset_minutes(self.offset())
  shift_minutes(self, minutes, offset)
}

///|
/// The same instant in UTC, with the offset `Z`: the form whose components
/// Ion binary stores and Ion Hash serializes.
pub fn Timestamp::as_utc(self : Timestamp) -> Timestamp {
  self.with_offset(TimestampOffset::Known(0))
}

///|
/// Read the components as UTC and move them to the timestamp's own offset.
/// This mixes UTC components with a local offset, so the input does not name
/// the instant its text shows; build the UTC timestamp and use `with_offset`
/// instead.
#deprecated("build the timestamp in UTC and use `with_offset`")
pub fn Timestamp::as_local(self : Timestamp) -> Timestamp {
  match self.offset() {
    Some(offset) => shift_minutes(self, offset_minutes(Some(offset)), offset)
    None => self
  }
}

///|
/// Compare the instants two timestamps name, as `-1`, `0`, or `1`, ignoring
/// their precision and offsets: a component a timestamp leaves out counts as
/// its lowest value, and a timestamp with no time, or an unknown offset, is
/// read in UTC. `2007T`, `2007-01-01`, and `2007-01-01T01:00+01:00` name the
/// same instant, though they are different Ion values.
pub fn Timestamp::compare_instant(self : Timestamp, other : Timestamp) -> Int {
  let a = self.as_utc()
  let b = other.as_utc()
  let fields = (timestamp : Timestamp) => {
    [
      timestamp.year(),
      timestamp.month().unwrap_or(1),
      timestamp.day().unwrap_or(1),
      timestamp.hour().unwrap_or(0),
      timestamp.minute().unwrap_or(0),
      timestamp.second().unwrap_or(0),
    ]
  }
  let (left, right) = (fields(a), fields(b))
  for index in 0..<left.length() {
    if left[index] != right[index] {
      return if left[index] < right[index] { -1 } else { 1 }
    }
  }
  compare_fractions(a.fraction(), b.fraction())
}

///|
/// Compare two fractional seconds exactly; a missing fraction is zero.
fn compare_fractions(a : Decimal?, b : Decimal?) -> Int {
  let zero = Decimal::zero()
  let a = a.unwrap_or(zero)
  let b = b.unwrap_or(zero)
  // Scale both coefficients to the smaller exponent, then compare them.
  let exponent = @cmp.minimum(a.exponent(), b.exponent())
  let scale = (value : Decimal) => {
    value.coefficient() *
    @bigint.BigInt::from_int(10).pow(
      @bigint.BigInt::from_int(value.exponent() - exponent),
    )
  }
  scale(a).compare(scale(b))
}
