# Spec Delta

## Purpose

Convert MoonBit values to Ion values and back, with exact and documented rules
for each type, and errors that name where a value does not decode.

## ADDED Requirements

### Requirement: Decoding accepts the Ion type that encoding writes

Each type that can be decoded from Ion SHALL accept exactly the Ion type that
its encoding writes, and SHALL reject every other Ion type, including every
null, with a type mismatch. Annotations on the decoded value SHALL be ignored.

#### Scenario: Each type reads one Ion type

- **WHEN** a value is decoded as one of these types
- **THEN** only this Ion type decodes, and every other Ion type fails:

| MoonBit type | Ion type written and read |
|---|---|
| `Unit` | untyped `null` |
| `Bool` | `bool` |
| `Int`, `Int64`, `UInt`, `UInt64`, `Byte`, `BigInt` | `int` |
| `Float`, `Double` | `float` |
| `Decimal` | `decimal` |
| `Timestamp` | `timestamp` |
| `String`, `Char` | `string` |
| `SymbolToken` | `symbol` |
| `Bytes` | `blob` |
| `Array[T]`, tuples | `list` |
| `Map[String, T]` | `struct` |

#### Scenario: A symbol does not decode as a string

- **WHEN** the Ion symbol `abc` is decoded as `String`
- **THEN** decoding fails with a type mismatch that expects `string` and keeps
  the symbol

#### Scenario: A decimal does not decode as a double

- **WHEN** the Ion decimal `1.5` is decoded as `Double`
- **THEN** decoding fails with a type mismatch that expects `float`

#### Scenario: A typed null does not decode as a value

- **WHEN** the Ion value `null.int` is decoded as `Int`
- **THEN** decoding fails with a type mismatch that expects `int` and keeps the
  typed null `null.int`

#### Scenario: Annotations are ignored

- **WHEN** the Ion value `a::5` is decoded as `Int`
- **THEN** the result is `5`

### Requirement: Encoding then decoding returns the original value

For every type that implements both directions, decoding the encoding of a
value SHALL return an equal value. The exceptions are documented: `Option[T]`
where `T` itself encodes as a null, and the NaN payload of a `Float` or
`Double`.

#### Scenario: Round trip of an integer at its limit

- **WHEN** `Int64` maximum is encoded and decoded as `Int64`
- **THEN** the result is `Int64` maximum

#### Scenario: Round trip of nested containers

- **WHEN** a `Map[String, Array[(Int, String?)]]` is encoded and decoded
- **THEN** the result equals the original map, in the same key order

### Requirement: Numbers that do not fit their target fail

An Ion `int` outside the range of `Int`, `Int64`, `UInt`, `UInt64` or `Byte`
SHALL fail with an out-of-range error that states the range. An Ion `float`
SHALL decode as `Float` by rounding to the nearest `Float`, and SHALL fail
with an out-of-range error when a finite value rounds to an infinity. NaN and
the infinities SHALL decode as themselves.

#### Scenario: Int overflow

- **WHEN** the Ion int `2147483648` is decoded as `Int`
- **THEN** decoding fails as out of range, with the range from `-2147483648`
  to `2147483647`

#### Scenario: Negative into an unsigned type

- **WHEN** the Ion int `-1` is decoded as `UInt64`
- **THEN** decoding fails as out of range

#### Scenario: Float overflow

- **WHEN** the Ion float `1e39` is decoded as `Float`
- **THEN** decoding fails as out of range

### Requirement: Characters, options and tuples have fixed encodings

A `Char` SHALL encode as an Ion string of one Unicode scalar value, and SHALL
decode only from a string of exactly one. A `Byte` SHALL encode as an Ion int
from 0 to 255. A tuple SHALL encode as an Ion list with one element per
component, and SHALL decode only from a list of the same length. `None` SHALL
encode as the untyped `null` and `Some(x)` as the encoding of `x`. Every null,
typed or untyped, SHALL decode as `None`; every other value SHALL decode as
`Some` of the inner type.

#### Scenario: A string of two characters is not a Char

- **WHEN** the Ion string `"ab"` is decoded as `Char`
- **THEN** decoding fails with a wrong-length error that expects 1 and finds 2

#### Scenario: A list of three is not a pair

- **WHEN** the Ion list `[1, 2, 3]` is decoded as `(Int, Int)`
- **THEN** decoding fails with a wrong-length error that expects 2 and finds 3

#### Scenario: A typed null is None

- **WHEN** the Ion value `null.string` is decoded as `String?`
- **THEN** the result is `None`

### Requirement: Maps reject duplicate and unknown field names

A struct SHALL decode as `Map[String, T]` only when every field name has known
text and no name repeats. A repeated name SHALL fail with a duplicate-field
error that names the field. A name known only by a symbol ID that is not an
Ion 1.0 system symbol SHALL fail with a missing-symbol-text error.

#### Scenario: Duplicate field names

- **WHEN** the Ion struct `{a: 1, a: 2}` is decoded as `Map[String, Int]`
- **THEN** decoding fails with a duplicate-field error for `a`

### Requirement: Decode errors name the value path

Every decode error SHALL carry the path from the decoded root to the value
that failed, as a sequence of struct field names and list indexes, and its
message SHALL render the path in `$` notation (`$.a[2]`). Containers SHALL
add their own step to the path of an error from an element.

#### Scenario: Path of a nested failure

- **WHEN** the Ion struct `{events: [1, "x"]}` is decoded as
  `Map[String, Array[Int]]`
- **THEN** decoding fails with a type mismatch whose path is field `events`
  then index `1`, and whose message starts with `$.events[1]`

### Requirement: Ion and JSON decoding follow existing rules

Decoding as `Ion` SHALL return the value unchanged, annotations included.
Decoding as `Json` SHALL follow the documented Ion to JSON down-conversion,
and SHALL fail with a missing-symbol-text error, with the path of the first
such symbol, when a symbol or field name has no text.

#### Scenario: A symbol with no text does not decode as JSON

- **WHEN** the Ion list `[a, $99]`, where `$99` has no text, is decoded as `Json`
- **THEN** decoding fails with a missing-symbol-text error at index `1`

### Requirement: JSON bridges convert through core JSON

The JSON package SHALL provide `to_ion_via_json`, which encodes any value with
core `ToJson` as the Ion value of its JSON, and `from_ion_via_json`, which
decodes any value with core `FromJson` from the JSON of an Ion value. A
failure in either step SHALL raise the decode error; a `FromJson` failure
SHALL keep its message and SHALL name its path as Ion field names and list
indexes.

#### Scenario: Round trip of a derived type

- **WHEN** a struct that derives `ToJson` and `FromJson` is encoded with
  `to_ion_via_json` and decoded with `from_ion_via_json`
- **THEN** the result equals the original struct

#### Scenario: A FromJson failure names its path

- **WHEN** the Ion struct `{id: "x"}` is decoded with `from_ion_via_json` as a
  struct whose `id` field is an `Int`
- **THEN** decoding fails with a JSON decode error whose path is field `id`
