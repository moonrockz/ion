// Ranges over numbers and timestamps, as `valid_values` takes them.
//
// A range is `range::[lower, upper]`. Each bound is a value, a value annotated
// `exclusive::`, or `min` (for the lower bound) or `max` (for the upper) when
// there is no bound. The bounds are both numbers (`int`, `decimal`, or
// `float`) or both timestamps. Numbers compare by their exact value, whatever
// their Ion type, and timestamps by the instant they name.

///|
/// A bound of a range.
pub(all) enum Bound {
  /// `min` or `max`: there is no bound.
  Unbounded
  /// The bound value is in the range.
  Inclusive(@ion.IonValue)
  /// The bound value is not in the range: `exclusive::` in ISL.
  Exclusive(@ion.IonValue)
} derive(Debug)

///|
/// A range of numbers or of timestamps.
pub struct ValueRange {
  lower : Bound
  upper : Bound
} derive(Debug)

///|
/// A range from `lower` to `upper`.
pub fn ValueRange::new(lower : Bound, upper : Bound) -> ValueRange {
  ValueRange::{ lower, upper, }
}

///|
/// The lower bound.
pub fn ValueRange::lower(self : ValueRange) -> Bound {
  self.lower
}

///|
/// The upper bound.
pub fn ValueRange::upper(self : ValueRange) -> Bound {
  self.upper
}

///|
/// Whether `value` is in the range. A null, a `nan`, and a value that is not
/// the same kind as the bounds (a number or a timestamp) are not in any range.
/// Annotations do not count.
pub fn ValueRange::contains(self : ValueRange, value : @ion.IonValue) -> Bool {
  match kind_of(value) {
    Some(kind) if Some(kind) == range_kind(self) => ()
    _ => return false
  }
  // Values of the same kind always compare.
  let order = (bound : @ion.IonValue) => {
    compare_values(value, bound).unwrap_or(0)
  }
  let above = match self.lower {
    Unbounded => true
    Inclusive(bound) => order(bound) >= 0
    Exclusive(bound) => order(bound) > 0
  }
  let below = match self.upper {
    Unbounded => true
    Inclusive(bound) => order(bound) <= 0
    Exclusive(bound) => order(bound) < 0
  }
  above && below
}

///|
/// What a range compares: numbers or timestamps.
priv enum RangeKind {
  Number
  Instant
} derive(Eq)

///|
/// Whether a value can be compared in a range, and as what. A null or a `nan`
/// cannot.
fn kind_of(value : @ion.IonValue) -> RangeKind? {
  match value.kind() {
    Int(_) | Decimal(_) => Some(Number)
    Float(f) => if f.is_nan() { None } else { Some(Number) }
    Timestamp(_) => Some(Instant)
    _ => None
  }
}

///|
/// What the bounds of a range are. A range has at least one bound.
fn range_kind(range : ValueRange) -> RangeKind? {
  match (range.lower, range.upper) {
    (Inclusive(bound) | Exclusive(bound), _) => kind_of(bound)
    (_, Inclusive(bound) | Exclusive(bound)) => kind_of(bound)
    _ => None
  }
}

///|
/// An exact number: a float's infinities, or `coefficient * 10^exponent`.
priv enum Exact {
  NegativeInfinity
  Finite(BigInt, Int)
  PositiveInfinity
}

///|
/// The exact value of an `int`, `decimal`, or `float`; `None` for anything
/// else, and for `nan`.
fn exact_number(value : @ion.IonValue) -> Exact? {
  match value.kind() {
    Int(n) => Some(Finite(n, 0))
    Decimal(d) => Some(Finite(d.coefficient(), d.exponent()))
    Float(f) =>
      if f.is_nan() {
        None
      } else if f.is_pos_inf() {
        Some(PositiveInfinity)
      } else if f.is_neg_inf() {
        Some(NegativeInfinity)
      } else {
        Some(exact_double(f))
      }
    _ => None
  }
}

///|
/// The exact value of a finite double, `mantissa * 2^exponent`, as a decimal.
/// `2^-k` is `5^k * 10^-k`, so a negative power of two stays exact.
fn exact_double(f : Double) -> Exact {
  let bits = f.reinterpret_as_uint64()
  let biased = ((bits >> 52) & 0x7FFUL).to_int()
  let fraction = bits & 0xF_FFFF_FFFF_FFFFUL
  let (mantissa, exponent) = if biased == 0 {
    (fraction, -1074)
  } else {
    (fraction | (1UL << 52), biased - 1075)
  }
  let mut coefficient = @bigint.BigInt::from_uint64(mantissa)
  if bits >> 63 == 1UL {
    coefficient = -coefficient
  }
  if exponent >= 0 {
    Finite(coefficient * power(2, exponent), 0)
  } else {
    Finite(coefficient * power(5, -exponent), exponent)
  }
}

///|
/// `base` to the power `exponent`, which is not negative.
fn power(base : Int, exponent : Int) -> BigInt {
  @bigint.BigInt::from_int(base).pow(@bigint.BigInt::from_int(exponent))
}

///|
/// The sign of a number: -1, 0, or 1. (`compare` gives only a sign, which is
/// not always -1 or 1: on wasm-gc it can be any number.)
fn sign(n : BigInt) -> Int {
  if n > 0N {
    1
  } else if n < 0N {
    -1
  } else {
    0
  }
}

///|
/// Compare two exact numbers: -1, 0, or 1.
fn compare_exact(a : Exact, b : Exact) -> Int {
  match (a, b) {
    (NegativeInfinity, NegativeInfinity)
    | (PositiveInfinity, PositiveInfinity) => 0
    (NegativeInfinity, _) | (_, PositiveInfinity) => -1
    (_, NegativeInfinity) | (PositiveInfinity, _) => 1
    (Finite(c1, e1), Finite(c2, e2)) => {
      let (s1, s2) = (sign(c1), sign(c2))
      if s1 != s2 || s1 == 0 {
        return if s1 < s2 { -1 } else if s1 > s2 { 1 } else { 0 }
      }
      // The same sign. Compare the magnitudes first, as the position of the
      // leading digit, so a large exponent never scales a coefficient.
      let m1 = digits(c1) + e1
      let m2 = digits(c2) + e2
      if m1 != m2 {
        return if m1 < m2 { -s1 } else { s1 }
      }
      let e = if e1 < e2 { e1 } else { e2 }
      sign(c1 * power(10, e1 - e) - c2 * power(10, e2 - e))
    }
  }
}

///|
/// The number of decimal digits in a coefficient's magnitude.
fn digits(n : BigInt) -> Int {
  let text = n.to_string()
  if text.has_prefix("-") {
    text.length() - 1
  } else {
    text.length()
  }
}

///|
/// Compare two values of the same range kind: numbers by value, timestamps by
/// instant. `None` when they cannot be compared.
fn compare_values(a : @ion.IonValue, b : @ion.IonValue) -> Int? {
  match (a.kind(), b.kind()) {
    (Timestamp(x), Timestamp(y)) => Some(x.compare_instant(y))
    _ =>
      match (exact_number(a), exact_number(b)) {
        (Some(x), Some(y)) => Some(compare_exact(x, y))
        _ => None
      }
  }
}

///|
/// Load a `range::[lower, upper]` of numbers or timestamps.
fn load_value_range(value : @ion.IonValue) -> ValueRange raise @ion.IonError {
  let (lower_value, upper_value) = range_bounds(value)
  let lower = load_bound(lower_value, "min")
  let upper = load_bound(upper_value, "max")
  let range : ValueRange = { lower, upper, }
  match (lower, upper) {
    (Unbounded, Unbounded) =>
      raise @ion.IonError::DataModel("a range needs at least one bound")
    (Inclusive(a) | Exclusive(a), Inclusive(b) | Exclusive(b)) => {
      if kind_of(a) != kind_of(b) {
        raise @ion.IonError::DataModel(
          "the bounds of a range must both be numbers or both be timestamps",
        )
      }
      let order = compare_values(a, b).unwrap_or(0)
      let exclusive = lower is Exclusive(_) || upper is Exclusive(_)
      if order > 0 || (order == 0 && exclusive) {
        raise @ion.IonError::DataModel("the range contains no value")
      }
    }
    _ => ()
  }
  range
}

///|
/// Whether a bound of the range is a timestamp with the unknown offset.
fn ValueRange::has_unknown_offset(self : ValueRange) -> Bool {
  [self.lower, self.upper]
  .iter()
  .any(bound => {
    match bound {
      Inclusive(value) | Exclusive(value) =>
        value.kind() is @ion.IonValueKind::Timestamp(timestamp) &&
        timestamp.offset().unwrap_or(@ion.TimestampOffset::Unknown) is Unknown
      Unbounded => false
    }
  })
}

///|
/// The two bounds of a `range::[lower, upper]`.
fn range_bounds(
  value : @ion.IonValue,
) -> (@ion.IonValue, @ion.IonValue) raise @ion.IonError {
  let annotations = value.annotations().map(token => token.text())
  match value.kind() {
    List([lower, upper]) if annotations == [Some("range")] => (lower, upper)
    _ =>
      raise @ion.IonError::DataModel(
        "a range must be a list of two bounds annotated with 'range'",
      )
  }
}

///|
/// Load one bound of a range. `open` is the symbol for no bound: `min` for
/// the lower bound, `max` for the upper.
fn load_bound(
  value : @ion.IonValue,
  open : String,
) -> Bound raise @ion.IonError {
  match bound_value(value, open) {
    None => Unbounded
    Some((bare, exclusive)) if kind_of(bare) is Some(_) =>
      if exclusive {
        Exclusive(bare)
      } else {
        Inclusive(bare)
      }
    _ =>
      raise @ion.IonError::DataModel(
        "a range bound must be a number, a timestamp, or '\{open}'",
      )
  }
}

///|
/// One bound of a range, without its annotations, and whether it is
/// `exclusive::`; `None` for `open` (`min` or `max`), which cannot be
/// exclusive.
fn bound_value(
  value : @ion.IonValue,
  open : String,
) -> (@ion.IonValue, Bool)? raise @ion.IonError {
  let annotations = value.annotations().map(token => token.text())
  let exclusive = match annotations {
    [] => false
    [Some("exclusive")] => true
    _ =>
      raise @ion.IonError::DataModel(
        "a range bound may only be annotated with 'exclusive'",
      )
  }
  match value.kind() {
    Symbol(token) if token.text() == Some(open) =>
      if exclusive {
        raise @ion.IonError::DataModel("'\{open}' cannot be exclusive")
      } else {
        None
      }
    _ => Some((value.with_annotations([]), exclusive))
  }
}

///|
pub extend Bound with @debug.Debug::{to_repr}

///|
pub extend ValueRange with @debug.Debug::{to_repr}
