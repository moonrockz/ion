// Proleptic Gregorian calendar arithmetic and the UTC/local conversion for
// timestamps.
//
// Ion text keeps a timestamp's components in local time plus the local offset,
// while Ion binary keeps them in UTC. Transcoding between the two therefore
// shifts the date and time by the offset, rolling over days, months, leap days,
// and years; `as_utc` and `as_local` are the two directions.

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
/// Shift a timestamp's date and time by its local offset. `direction` is `1` to
/// read local components as UTC and `-1` to read UTC components as local. A
/// timestamp with no time, or with an unknown offset, cannot be shifted and is
/// returned unchanged.
fn shift_to_zone(timestamp : Timestamp, direction : Int) -> Timestamp {
  match
    (
      timestamp.offset(),
      timestamp.month(),
      timestamp.day(),
      timestamp.hour(),
      timestamp.minute(),
    ) {
    (
      Some(TimestampOffset::Known(minutes)),
      Some(month),
      Some(day),
      Some(hour),
      Some(minute),
    ) => {
      let total = hour * 60 + minute - direction * minutes
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
        offset=timestamp.offset(),
      )
    }
    _ => timestamp
  }
}

///|
/// The same instant with its components read in UTC: the local offset is
/// subtracted. This is the form Ion binary stores, and the form Ion Hash
/// serializes.
pub fn Timestamp::as_utc(self : Timestamp) -> Timestamp {
  shift_to_zone(self, 1)
}

///|
/// The same instant with its components read in local time: the local offset is
/// added back. This is the form Ion text uses.
pub fn Timestamp::as_local(self : Timestamp) -> Timestamp {
  shift_to_zone(self, -1)
}
