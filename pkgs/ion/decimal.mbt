// Ion decimals.
//
// A decimal is `coefficient * 10^exponent`. Both parts are kept exactly as
// written so that trailing zeros (the scale) survive a round-trip, and a zero
// coefficient may carry a sign: Ion keeps `0.` and `-0.` distinct.

///|
/// An Ion `decimal` value, kept as `coefficient * 10^exponent`.
pub struct Decimal {
  coefficient : BigInt
  exponent : Int
  negative_zero : Bool
} derive(Debug)

///|
/// Build a decimal from an explicit coefficient and base-10 exponent.
pub fn Decimal::new(coefficient : BigInt, exponent : Int) -> Decimal {
  { coefficient, exponent, negative_zero: false, }
}

///|
/// Build a decimal from an `Int`, with exponent `0`.
pub fn Decimal::from_int(value : Int) -> Decimal {
  Decimal::new(BigInt::from_int(value), 0)
}

///|
/// The decimal `0.`.
pub fn Decimal::zero() -> Decimal {
  Decimal::from_int(0)
}

///|
/// The decimal `-0.` (negative zero), which Ion keeps distinct from `0.`.
pub fn Decimal::negative_zero() -> Decimal {
  { coefficient: BigInt::from_int(0), exponent: 0, negative_zero: true, }
}

///|
/// The decimal `-0dN`: negative zero at a given exponent, which Ion keeps
/// distinct from `0dN`.
pub fn Decimal::negative_zero_at(exponent : Int) -> Decimal {
  { coefficient: BigInt::from_int(0), exponent, negative_zero: true, }
}

///|
/// The unscaled coefficient (significand) of this decimal.
pub fn Decimal::coefficient(self : Decimal) -> BigInt {
  self.coefficient
}

///|
/// The base-10 exponent of this decimal.
pub fn Decimal::exponent(self : Decimal) -> Int {
  self.exponent
}

///|
/// Whether this value is negative zero.
pub fn Decimal::is_negative_zero(self : Decimal) -> Bool {
  self.negative_zero
}

///|
/// Whether the coefficient is zero.
pub fn Decimal::is_zero(self : Decimal) -> Bool {
  self.coefficient.is_zero()
}

///|
/// Whether this value is negative, including negative zero.
pub fn Decimal::is_negative(self : Decimal) -> Bool {
  self.negative_zero || self.coefficient.compare_int(0) < 0
}

///|
/// The magnitude of the coefficient.
fn Decimal::magnitude(self : Decimal) -> BigInt {
  if self.coefficient.compare_int(0) < 0 {
    self.coefficient.neg()
  } else {
    self.coefficient
  }
}

///|
/// Read an unsigned integer from `text` starting at `start`, allowing Ion's
/// digit-separating underscores. Returns the digits and the index just past the
/// run. Raises when the run is empty or an underscore is misplaced.
fn read_uint_run(
  text : StringView,
  start : Int,
) -> (String, Int) raise IonError {
  let n = text.length()
  let sb = StringBuilder()
  let mut i = start
  let mut last_was_underscore = false
  let mut saw_digit = false
  while i < n && (is_digit(text[i]) || text[i] == '_') {
    if text[i] == '_' {
      if !saw_digit || last_was_underscore {
        raise IonError::Syntax("misplaced underscore in number")
      }
      last_was_underscore = true
    } else {
      sb.write_view(char_view(text, i))
      saw_digit = true
      last_was_underscore = false
    }
    i += 1
  }
  if !saw_digit {
    raise IonError::Syntax("expected a digit")
  }
  if last_was_underscore {
    raise IonError::Syntax("number may not end with an underscore")
  }
  (sb.to_string(), i)
}

///|
/// Read a signed decimal exponent (`d`/`D` body), e.g. `-12` in `1.5d-12`.
fn read_exponent(text : StringView, start : Int) -> (Int, Int) raise IonError {
  let n = text.length()
  let mut i = start
  let mut negative = false
  if i < n && (text[i] == '-' || text[i] == '+') {
    negative = text[i] == '-'
    i += 1
  }
  let (digits, next) = read_uint_run(text, i)
  // Parse the sign with the magnitude so Int::min_value is representable.
  let value = @string.parse_int(if negative { "-" + digits } else { digits }) catch {
    _ => raise IonError::Syntax("decimal exponent is out of range")
  }
  (value, next)
}

///|
/// Parse the body of an Ion decimal: an optional sign, a coefficient with an
/// optional decimal point, and an optional `d`/`D` exponent. For example
/// `-1_234.56d-7`, `0.`, or `123d0`.
pub fn Decimal::parse(text : StringView) -> Decimal raise IonError {
  let n = text.length()
  let mut i = 0
  let mut negative = false
  if i < n && (text[i] == '-' || text[i] == '+') {
    negative = text[i] == '-'
    i += 1
  }
  let digits = StringBuilder()
  let mut fraction_digits = 0
  let mut saw_digit = false
  // Integer part.
  let mut last_was_underscore = false
  while i < n && (is_digit(text[i]) || text[i] == '_') {
    if text[i] == '_' {
      if !saw_digit || last_was_underscore {
        raise IonError::Syntax("misplaced underscore in decimal")
      }
      last_was_underscore = true
    } else {
      digits.write_view(char_view(text, i))
      saw_digit = true
      last_was_underscore = false
    }
    i += 1
  }
  if last_was_underscore {
    raise IonError::Syntax("decimal may not end with an underscore")
  }
  // Fraction part.
  if i < n && text[i] == '.' {
    i += 1
    let mut fraction_seen = false
    let mut last_underscore = false
    while i < n && (is_digit(text[i]) || text[i] == '_') {
      if text[i] == '_' {
        if !fraction_seen || last_underscore {
          raise IonError::Syntax("misplaced underscore in decimal fraction")
        }
        last_underscore = true
      } else {
        digits.write_view(char_view(text, i))
        fraction_digits += 1
        saw_digit = true
        fraction_seen = true
        last_underscore = false
      }
      i += 1
    }
    if last_underscore {
      raise IonError::Syntax("decimal fraction may not end with an underscore")
    }
  }
  if !saw_digit {
    raise IonError::Syntax("decimal literal has no digits")
  }
  let mut exponent = 0
  if i < n && (text[i] == 'd' || text[i] == 'D') {
    i += 1
    let (value, next) = read_exponent(text, i)
    exponent = value
    i = next
  }
  if i != n {
    raise IonError::Syntax("unexpected character in decimal literal")
  }
  let coefficient = parse_digits_to_bigint(digits.to_string(), negative)
  let negative_zero = negative && coefficient.is_zero()
  let adjusted = exponent.to_int64() - fraction_digits.to_int64()
  if adjusted < -2147483648L || adjusted > 2147483647L {
    raise IonError::Syntax("decimal exponent is out of range")
  }
  { coefficient, exponent: adjusted.to_int(), negative_zero, }
}

///|
/// Parse a run of ASCII digits into a (possibly negative) `BigInt`.
fn parse_digits_to_bigint(digits : String, negative : Bool) -> BigInt {
  if digits.is_empty() {
    return BigInt::from_int(0)
  }
  let magnitude = @string.parse_bigint(digits, base=10) catch {
    _ => BigInt::from_int(0)
  }
  if negative {
    magnitude.neg()
  } else {
    magnitude
  }
}

///|
/// Render this decimal as Ion text, preserving coefficient, exponent, and
/// signed zero. Use positional notation for non-positive exponents when the
/// adjusted exponent is at least -6; otherwise retain `d` notation. Positive
/// exponents require `d` notation to preserve precision.
pub fn Decimal::to_ion_string(self : Decimal) -> String {
  let sign = if self.is_negative() { "-" } else { "" }
  let digits = self.magnitude().to_string()
  if self.exponent == 0 {
    return "\{sign}\{digits}."
  }
  // Widen before adding: even the minimum Int exponent must remain compact.
  let point = digits.length().to_int64() + self.exponent.to_int64()
  if self.exponent < 0 && point - 1L >= -6L {
    let buffer = StringBuilder()
    buffer.write_string(sign)
    if point > 0L {
      let index = point.to_int()
      buffer.write_view(digits[:index])
      buffer.write_string(".")
      buffer.write_view(digits[index:])
    } else {
      buffer.write_string("0.")
      for _ in 0..<(-point).to_int() {
        buffer.write_string("0")
      }
      buffer.write_string(digits)
    }
    return buffer.to_string()
  }
  "\{sign}\{digits}d\{self.exponent}"
}
