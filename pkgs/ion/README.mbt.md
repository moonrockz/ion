# The Ion data model (`moonrockz/ion/ion`)

The core package of `moonrockz/ion`: the thirteen Ion types and the values
that hold them, with no dependency on either encoding. The text and binary
codecs, Ion Hash, JSON conversion, and Ion Schema all build on it.

- `IonValue` is the one node type: an `IonValueKind` plus an ordered list of
  annotations. Build values with the constructors (`IonValue::int`,
  `IonValue::list`, `IonValue::from_fields`, ...), read them with `kind()`.
- `Decimal` and integers are exact (`BigInt` coefficients), so precision and
  negative zero survive every round trip.
- `Timestamp` keeps the components it was given; its precision follows from
  which ones are present.
- `SymbolToken` has optional text and an optional symbol ID, and
  `SymbolTable` maps IDs to text as a stream's symbol tables declare them.
- `IonVisitor` and `IonFold` traverse a value depth-first.
- Every failure is an `IonError`: `Syntax`, `DataModel`, or `Unsupported`.

## Building values

Values are immutable. Equivalence follows the Ion data model: annotations
count, struct fields form an unordered multiset, and all NaNs are equivalent.

```mbt check
///|
test "build a value and compare it" {
  let book = @ion.IonValue::from_fields([
    @ion.Field::new("title", @ion.IonValue::string("Ion")),
    @ion.Field::new(
      "tags",
      @ion.IonValue::list([
        @ion.IonValue::symbol("data"),
        @ion.IonValue::symbol("format"),
      ]),
    ),
  ]).with_annotation(@ion.SymbolToken::new("book"))
  inspect(book.ion_type().to_text(), content="struct")
  debug_inspect(
    book.annotations().map(token => token.text()),
    content=(
      #|[Some("book")]
    ),
  )
  // Field order does not matter to equivalence.
  let reordered = @ion.IonValue::from_fields([
    @ion.Field::new(
      "tags",
      @ion.IonValue::list([
        @ion.IonValue::symbol("data"),
        @ion.IonValue::symbol("format"),
      ]),
    ),
    @ion.Field::new("title", @ion.IonValue::string("Ion")),
  ]).with_annotation(@ion.SymbolToken::new("book"))
  assert_true(book.equals(reordered))
  // Annotations do.
  assert_false(book.equals(reordered.with_annotations([])))
}
```

Match on `kind()` to read a value:

```mbt check
///|
test "read a value by its kind" {
  let value = @text.read_ion("{ name: \"Ada\", born: 1815 }")
  match value.kind() {
    Struct(fields) =>
      debug_inspect(
        fields.map(field => field.name().text().unwrap_or("?")),
        content=(
          #|["name", "born"]
        ),
      )
    _ => fail("expected a struct")
  }
}
```

## Exact numbers

A decimal keeps its coefficient and exponent as written, so `1.50` and `1.5`
are different Ion values, and so are `0.0` and `-0.0`. Arithmetic goes
through `moonbitlang/x/decimal`, and returns `None` for what that type cannot
represent.

```mbt check
///|
test "decimals keep their precision" {
  let price = @ion.Decimal::parse("1.50")
  inspect(price.coefficient(), content="150")
  inspect(price.exponent(), content="-2")
  assert_false(
    @ion.IonValue::decimal(price).equals(
      @ion.IonValue::decimal(@ion.Decimal::parse("1.5")),
    ),
  )
  inspect(@ion.Decimal::parse("-0.0").is_negative_zero(), content="true")
  debug_inspect(
    price.add(@ion.Decimal::parse("0.25")).map(sum => sum.to_ion_string()),
    content=(
      #|Some("175d-2")
    ),
  )
}
```

## Timestamps

A timestamp has the precision its components give it, and an optional offset.
`validate` checks that it describes a real moment, which the readers apply to
every timestamp they read.

```mbt check
///|
test "timestamps" {
  let launch = @ion.Timestamp::parse("1969-07-20T20:17:40Z")
  debug_inspect(launch.precision(), content="Second")
  inspect(launch.to_ion_string(), content="1969-07-20T20:17:40Z")
  // The offset is kept, in minutes; `-00:00` is an unknown offset.
  let eastern = @ion.Timestamp::parse("2024-01-01T01:30+02:00")
  debug_inspect(eastern.offset(), content="Some(Known(120))")
  debug_inspect(
    @ion.Timestamp::parse("2024-01-01T01:30-00:00").offset(),
    content="Some(Unknown)",
  )
  // 2001 was not a leap year.
  let invalid = @ion.Timestamp::new(year=2001, month=Some(2), day=Some(29))
  let message = try invalid.validate() catch {
    error => error.message()
  } noraise {
    _ => "valid"
  }
  inspect(message, content="timestamp day is out of range for its month")
}
```

## Symbols and symbol tables

A symbol has text, a symbol ID, or both. The Ion 1.0 system symbols take IDs
1 to 9; a local symbol table declares more from 10. The readers keep a
`SymbolTable` per stream and resolve IDs against it.

```mbt check
///|
test "a symbol table resolves symbol IDs" {
  let table = @ion.SymbolTable::system()
  debug_inspect(table.text(4), content="Some(\"name\")")
  let declaration = @text.read_ion("{ symbols: [\"red\", \"green\"] }").with_annotation(
    @ion.SymbolToken::new("$ion_symbol_table"),
  )
  assert_true(table.apply_local_symbol_table(declaration))
  inspect(table.max_id(), content="11")
  debug_inspect(
    table.lookup(11).text(),
    content=(
      #|Some("green")
    ),
  )
  // An ID beyond the table is an error.
  let beyond = try table.lookup(12) catch {
    error => error.message()
  } noraise {
    token => token.text().unwrap_or("?")
  }
  inspect(
    beyond,
    content="symbol ID $12 is beyond the symbol table, whose largest ID is 11",
  )
}
```

## Traversal

`IonValue::accept` walks a value depth-first with an `IonVisitor`, whose
methods all default to doing nothing. `IonValue::fold` threads an accumulator
instead, and each callback can continue, skip a value's children, or stop.

```mbt check
///|
struct FieldNames {
  names : Array[String]
}

///|
impl @ion.IonVisitor for FieldNames with fn visit_field_name(self, token) {
  self.names.push(token.text().unwrap_or("?"))
}

///|
test "visit every field name" {
  let value = @text.read_ion("{ a: 1, b: { c: 2 }, d: [ { e: 3 } ] }")
  let visitor : FieldNames = { names: [], }
  value.accept(visitor)
  debug_inspect(
    visitor.names,
    content=(
      #|["a", "b", "c", "d", "e"]
    ),
  )
}

///|
test "sum the integers outside annotated values" {
  let value = @text.read_ion("[1, 2, skip::[100, 200], (3 4)]")
  let sum = value.fold(0, {
    ..@ion.IonFold::default(),
    visit_value: (total, value) => {
      if value.has_annotations() {
        return SkipChildren(total)
      }
      match value.kind() {
        Int(n) => Continue(total + n.to_int())
        _ => Continue(total)
      }
    },
  })
  inspect(sum, content="10")
}
```
