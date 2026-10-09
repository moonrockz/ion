// Property-based tests for the Ion core data model.
//
// Numbers keep exact precision, so `parse(render(x)) == x` is a meaningful law
// for decimals and timestamps; QuickCheck supplies the components.

///|
test "decimal text round-trips through parsing" {
  @quickcheck.check((pair : (BigInt, Int)) => {
    // Keep the exponent small: the value is arbitrary precision, but the
    // exponent travels as an Ion `int` and the parser reads it back as one.
    let original = @ion.Decimal::new(pair.0, pair.1 % 1000)
    let reparsed = @ion.Decimal::parse(original.to_ion_string())
    reparsed.coefficient().equal(original.coefficient()) &&
    reparsed.exponent() == original.exponent() &&
    reparsed.is_negative_zero() == original.is_negative_zero()
  })
}

///|
test "timestamp text round-trips through parsing" {
  @quickcheck.check((seed : (Int, Int, Int, Int, Int, Int)) => {
    let original = @ion.Timestamp::new(
      year=2000 + (seed.0 & 0xFF),
      month=Some((seed.1 & 0x0F) % 12 + 1),
      day=Some((seed.2 & 0x1F) % 28 + 1),
      hour=Some((seed.3 & 0x1F) % 24),
      minute=Some((seed.4 & 0x3F) % 60),
      second=Some((seed.5 & 0x3F) % 60),
      offset=Some(@ion.TimestampOffset::Known(0)),
    )
    @ion.Timestamp::parse(original.to_ion_string()).to_ion_string() ==
    original.to_ion_string()
  })
}

///|
/// Counts the values it visits.
struct ValueCounter {
  mut count : Int
}

///|
impl @ion.IonVisitor for ValueCounter with fn visit_value(self, _value) {
  self.count += 1
}

///|
fn walker_samples() -> Array[@ion.IonValue] {
  @testkit.gen_value(max_depth=6, max_width=4).samples(count=300, size=8)
}

///|
test "equals is reflexive and symmetric on generated values" {
  let values = walker_samples()
  for index, a in values {
    let b = values[(index + 1) % values.length()]
    if !a.equals(a) {
      fail("not reflexive: \{@text.write_ion(a)}")
    }
    if a.equals(b) != b.equals(a) {
      fail("not symmetric: \{@text.write_ion(a)} and \{@text.write_ion(b)}")
    }
  }
}

///|
test "equals agrees with the reference on generated pairs and near misses" {
  let values = walker_samples()
  for index, a in values {
    let candidates = [
      values[(index + 1) % values.length()],
      @testkit.change_one_leaf(a, index),
      @testkit.reverse_fields(a),
      @text.read_ion(@text.write_ion(a)),
      ..@testkit.near_misses(a),
    ]
    for b in candidates {
      let expected = @testkit.reference_equals(a, b)
      if a.equals(b) != expected || b.equals(a) != expected {
        fail("disagree on \{@text.write_ion(a)} and \{@text.write_ion(b)}")
      }
    }
  }
}

///|
test "fold, the visitor and the reference count the same values" {
  for value in walker_samples() {
    let counter : ValueCounter = { count: 0, }
    value.accept(counter)
    let folded = value.fold(0, {
      ..@ion.IonFold::default(),
      visit_value: (count, _) => Continue(count + 1),
    })
    let expected = @testkit.count_values(value)
    if folded != expected || counter.count != expected {
      fail(
        "fold \{folded}, visitor \{counter.count}, reference \{expected}: \{@text.write_ion(value)}",
      )
    }
  }
}
