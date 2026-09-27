// Interoperability with `moonbitlang/x/decimal`.
//
// Ion's `Decimal` keeps `coefficient * 10^exponent` exactly, including trailing
// zeros (the scale is significant and round-trips) and a signed zero. The
// `moonbitlang/x` `Decimal` is a *normalized* decimal (`coefficient * 10^-scale`,
// `0 <= scale <= max_scale`, no trailing zeros) without a signed zero, so it
// cannot represent every Ion decimal faithfully. It is a good arithmetic
// engine, so these functions convert to it, compute, and convert back —
// documenting where information is dropped.

///|
/// This decimal as a `moonbitlang/x/decimal`, or `None` when it cannot be
/// represented there.
///
/// A non-negative exponent is folded into the coefficient, and a negative one
/// becomes the scale. Two things are lost: `x`'s decimal normalizes trailing
/// zeros, and it has no signed zero, so `-0.` converts to plain `0.` and, for
/// example, `1.50` converts to `1.5`. The conversion returns `None` when the
/// required scale exceeds `@decimal.max_scale`.
pub fn Decimal::to_x(self : Decimal) -> @decimal.Decimal? {
  if self.exponent >= 0 {
    let factor = BigInt::from_int(10).pow(BigInt::from_int(self.exponent))
    @decimal.Decimal::new(self.coefficient.mul(factor), 0)
  } else {
    @decimal.Decimal::new(self.coefficient, -self.exponent)
  }
}

///|
/// Build an Ion decimal from a `moonbitlang/x/decimal`. This direction is
/// exact: the scale becomes a negative exponent.
pub fn Decimal::from_x(value : @decimal.Decimal) -> Decimal {
  {
    coefficient: value.coefficient(),
    exponent: -value.scale(),
    negative_zero: false,
  }
}

///|
/// The sum, via `moonbitlang/x`'s decimal arithmetic, or `None` when an operand
/// or the result is out of that type's range. The result is normalized.
pub fn Decimal::add(self : Decimal, other : Decimal) -> Decimal? {
  match (self.to_x(), other.to_x()) {
    (Some(a), Some(b)) => Some(Decimal::from_x(a + b))
    _ => None
  }
}

///|
/// The difference, via `moonbitlang/x`'s decimal arithmetic, or `None` when an
/// operand or the result is out of that type's range.
pub fn Decimal::subtract(self : Decimal, other : Decimal) -> Decimal? {
  match (self.to_x(), other.to_x()) {
    (Some(a), Some(b)) => Some(Decimal::from_x(a - b))
    _ => None
  }
}

///|
/// The product, via `moonbitlang/x`'s decimal arithmetic, or `None` when an
/// operand or the result is out of that type's range.
pub fn Decimal::multiply(self : Decimal, other : Decimal) -> Decimal? {
  match (self.to_x(), other.to_x()) {
    (Some(a), Some(b)) => Some(Decimal::from_x(a * b))
    _ => None
  }
}

///|
/// Numeric comparison, via `moonbitlang/x`'s decimal arithmetic: `-1`, `0`, or
/// `1`. Unlike `IonValue::equals`, this ignores scale, so `1.5` and `1.50`
/// compare equal. Returns `None` when an operand is out of range.
pub fn Decimal::compare(self : Decimal, other : Decimal) -> Int? {
  match (self.to_x(), other.to_x()) {
    (Some(a), Some(b)) => Some(if a < b { -1 } else if a > b { 1 } else { 0 })
    _ => None
  }
}

///|
/// The nearest `Double`, or `None` when the value is out of range.
pub fn Decimal::to_double(self : Decimal) -> Double? {
  match self.to_x() {
    Some(value) => Some(value.to_double())
    None => None
  }
}
