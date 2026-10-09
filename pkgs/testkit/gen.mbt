// Generators of Ion values and JSON values for property tests. Generated
// values nest at most `max_depth` levels, so the recursive oracles in
// `reference.mbt` can check them.

///|
/// Symbol texts: bare, quoted, keyword-like, empty and non-ASCII.
let symbol_texts : Array[String] = [
  "a", "name", "a b", "null", "$ion", "", "é", "x1",
]

///|
/// Operator symbols, which an S-expression writes without quotes.
let operator_texts : Array[String] = ["+", "<=", "-->", "*"]

///|
let string_texts : Array[String] = [
  "", "hello", "tab\there", "quote\" and \\", "é ü", "😀", "line\nbreak",
]

///|
let byte_samples : Array[Bytes] = [b"", b"abc", b"\x00\xff\x7f\"\\"]

///|
/// Symbols with no text: `$0`, and a local ID that a writer reserves.
let unknown_tokens : Array[@ion.SymbolToken] = [
  @ion.SymbolToken::from_sid(0),
  @ion.SymbolToken::from_sid(12),
]

///|
/// Symbols with no text from slots 1 and 2 of version 1 of the shared table
/// `shared`, each with the stream-local ID a reader would give it.
let imported_tokens : Array[@ion.SymbolToken] = [
  @ion.SymbolToken::from_import(10, "shared", 1, 1),
  @ion.SymbolToken::from_import(11, "shared", 1, 2),
]

///|
let big_ints : Array[BigInt] = [
  BigInt::from_int64(9_223_372_036_854_775_807L) * BigInt::from_int(1000),
  BigInt::from_int64(-9_223_372_036_854_775_807L) * BigInt::from_int(1000),
]

///|
/// Floats with every special case: zero, negative zero, NaN and infinities.
let float_samples : Array[Double] = [
  0.0,
  0.0 * -1.0,
  1.5,
  -2.25e10,
  1.0e-300,
  0.0 / 0.0,
  1.0 / 0.0,
  -1.0 / 0.0,
]

///|
/// Ion values up to `max_depth` levels deep, with up to `max_width` children
/// per container. They cover every Ion type and its typed null, annotations,
/// structs with repeated field names, S-expressions with operator symbols,
/// decimals with negative zero and exponents, timestamps at every precision,
/// and NaN, infinite and negative-zero floats. With `unknown_symbols` (the
/// default) some symbols, field names and annotations have no text: `$0` or a
/// reserved local ID. With `imported_symbols` some also come from a shared
/// table whose text is unknown.
pub fn gen_value(
  max_depth~ : Int,
  max_width~ : Int,
  unknown_symbols? : Bool = true,
  imported_symbols? : Bool = false,
) -> @quickcheck.Generator[@ion.IonValue] {
  let choices = [
    (8U, @quickcheck.elements(symbol_texts).map(@ion.SymbolToken::new)),
  ]
  if unknown_symbols {
    choices.push((2U, @quickcheck.elements(unknown_tokens)))
  }
  if imported_symbols {
    choices.push((2U, @quickcheck.elements(imported_tokens)))
  }
  let tokens = @quickcheck.frequency(choices)
  value_gen(tokens, max_depth, max_width)
}

///|
fn value_gen(
  tokens : @quickcheck.Generator[@ion.SymbolToken],
  depth : Int,
  width : Int,
) -> @quickcheck.Generator[@ion.IonValue] {
  let core = if depth <= 0 {
    scalar_gen(tokens)
  } else {
    let child = value_gen(tokens, depth - 1, width)
    let operators = @quickcheck.elements(operator_texts).map(
      @ion.IonValue::symbol,
    )
    let field = tokens.zip_with(child, @ion.Field::from_token)
    let count = @quickcheck.int_range(0, width + 1)
    @quickcheck.frequency([
      (3U, scalar_gen(tokens)),
      (
        1U,
        count.flat_map(n => child.array_with_size(n)).map(@ion.IonValue::list),
      ),
      (
        1U,
        count
        .flat_map(n => @quickcheck.one_of([child, operators]).array_with_size(n))
        .map(@ion.IonValue::sexp),
      ),
      (
        1U,
        count
        .flat_map(n => field.array_with_size(n))
        .map(@ion.IonValue::from_fields),
      ),
    ])
  }
  let annotations = @quickcheck.int_range(0, 3).flat_map(n => {
    tokens.array_with_size(n)
  })
  core.zip_with(annotations, (value, annotations) => {
    value.with_annotations(annotations)
  })
}

///|
fn scalar_gen(
  tokens : @quickcheck.Generator[@ion.SymbolToken],
) -> @quickcheck.Generator[@ion.IonValue] {
  @quickcheck.one_of([
    @quickcheck.elements(@ion.IonType::all()).map(@ion.IonValue::typed_null),
    @quickcheck.elements([true, false]).map(@ion.IonValue::bool),
    @quickcheck.int_range(-1000, 1001).map(@ion.IonValue::int),
    @quickcheck.elements(big_ints).map(@ion.IonValue::big_int),
    @quickcheck.elements(float_samples).map(@ion.IonValue::float),
    decimal_gen(),
    @quickcheck.int_range(0, 6).zip_with(@quickcheck.int_range(0, 10000), (
      precision,
      seed,
    ) => @ion.IonValue::timestamp(timestamp_at(precision, seed))),
    tokens.map(@ion.IonValue::symbol_token),
    @quickcheck.elements(string_texts).map(@ion.IonValue::string),
    @quickcheck.elements(byte_samples).map(@ion.IonValue::clob),
    @quickcheck.elements(byte_samples).map(@ion.IonValue::blob),
  ])
}

///|
fn decimal_gen() -> @quickcheck.Generator[@ion.IonValue] {
  @quickcheck.one_of([
    @quickcheck.int_range(-99999, 100000).zip_with(
      @quickcheck.int_range(-5, 6),
      (coefficient, exponent) => {
        @ion.IonValue::decimal(
          @ion.Decimal::new(BigInt::from_int(coefficient), exponent),
        )
      },
    ),
    @quickcheck.elements([
      @ion.Decimal::negative_zero(),
      @ion.Decimal::negative_zero_at(-2),
      @ion.Decimal::zero(),
    ]).map(@ion.IonValue::decimal),
  ])
}

///|
/// A timestamp at precision 0 (year) to 5 (fractional second). Offsets are
/// zero, negative or unknown, so the UTC form never moves to an earlier year.
fn timestamp_at(precision : Int, seed : Int) -> @ion.Timestamp {
  let year = 1970 + seed % 100
  let month = Some(seed % 12 + 1)
  let day = Some(seed % 28 + 1)
  let hour = Some(seed % 24)
  let minute = Some(seed % 60)
  let second = Some(seed % 60)
  let offset = Some(
    match seed % 3 {
      0 => @ion.TimestampOffset::Known(0)
      1 => @ion.TimestampOffset::Known(-480)
      _ => @ion.TimestampOffset::Unknown
    },
  )
  match precision {
    0 => @ion.Timestamp::new(year~)
    1 => @ion.Timestamp::new(year~, month~)
    2 => @ion.Timestamp::new(year~, month~, day~)
    3 => @ion.Timestamp::new(year~, month~, day~, hour~, minute~, offset~)
    4 =>
      @ion.Timestamp::new(year~, month~, day~, hour~, minute~, second~, offset~)
    _ =>
      @ion.Timestamp::new(
        year~,
        month~,
        day~,
        hour~,
        minute~,
        second~,
        fraction=Some(@ion.Decimal::new(BigInt::from_int(seed % 1000), -3)),
        offset~,
      )
  }
}

///|
/// JSON values up to `max_depth` levels deep: null, booleans, integer and
/// fractional numbers, strings, arrays, and objects (whose keys are unique,
/// as in any JSON object).
pub fn gen_json(
  max_depth~ : Int,
  max_width~ : Int,
) -> @quickcheck.Generator[Json] {
  let scalar = @quickcheck.one_of([
    @quickcheck.pure(Json::null()),
    @quickcheck.elements([true, false]).map(Json::boolean),
    @quickcheck.int_range(-1000000, 1000001).map(n => {
      Json::number(n.to_double())
    }),
    @quickcheck.elements([0.5, -1.25, 3.0e-7, 1.0e21]).map(n => Json::number(n)),
    @quickcheck.elements(string_texts).map(Json::string),
  ])
  if max_depth <= 0 {
    return scalar
  }
  let child = gen_json(max_depth=max_depth - 1, max_width~)
  let count = @quickcheck.int_range(0, max_width + 1)
  let entry = @quickcheck.elements(["a", "b", "c", "a b"]).zip(child)
  @quickcheck.frequency([
    (3U, scalar),
    (1U, count.flat_map(n => child.array_with_size(n)).map(Json::array)),
    (
      1U,
      count
      .flat_map(n => entry.array_with_size(n))
      .map(members => {
        let object : Map[String, Json] = Map([])
        for pair in members {
          object.set(pair.0, pair.1)
        }
        Json::object(object)
      }),
    ),
  ])
}
