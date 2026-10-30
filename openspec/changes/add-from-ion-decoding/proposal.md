# Proposal

## Why

moonrockz/ion can encode MoonBit values with `ToIon`, but it cannot decode
them. moonrockz/moon-lander (OpenSpec change `add-typed-actors`) will use Ion
as the payload format for runtime actor events such as dead letters, so it
needs a typed decode path with errors that say where a payload is wrong. Many
of its types derive core `ToJson` and `FromJson`; MoonBit cannot derive
`ToIon` and has no blanket impls, so those types need named bridge functions.

## What Changes

- Add a `FromIon` trait to `@ion`: `fn from_ion(Ion) -> Self raise FromIonError`.
- Add the `FromIonError` suberror. Each case names the value path (field names
  and list indexes) and keeps the value that failed.
- Add `FromIon` for every type that has `ToIon`: `Unit`, `Bool`, `Int`,
  `Int64`, `UInt`, `UInt64`, `Float`, `Double`, `String`, `Bytes`, `BigInt`,
  `Decimal`, `Timestamp`, `SymbolToken`, `Ion`, `Json`, `Array[T]` and
  `Map[String, T]`.
- Add `ToIon` and `FromIon` for `Option[T]`, `Char`, `Byte`, and tuples of
  two and three elements.
- Add the bridges `@ion.to_ion_via_json` (any `ToJson` value to Ion) and
  `@ion.from_ion_via_json` (Ion to any `FromJson` value), re-exported from
  `@json`. A failure in the Ion to JSON step or in `FromJson` raises
  `FromIonError`, not an abort.
- Move the Ion to JSON conversion from `@json` into `@ion`, so that `Json` can
  implement `FromIon`. `@json.to_json` keeps its signature and its rules.
  The message of its `IonError::Unsupported` now names the value path.

No existing API is removed. Adding the trait and impls is not breaking.

## Capabilities

### New Capabilities

- `value-codecs`: conversion between MoonBit values and Ion values in both
  directions, the decode error contract, and the JSON bridges.

### Modified Capabilities

None. The repository has no published specs yet.

## Tracking

- bd: `ion-sfb` (FromIon decoding and codec parity).
- Consumer: moonrockz/moon-lander OpenSpec change `add-typed-actors`.

## Impact

- `pkgs/ion`: new trait, error type, impls and bridge functions; the Ion to
  JSON conversion moves here from `pkgs/json`. `pkg.generated.mbti` grows.
- `pkgs/json`: re-exports `FromIon`, `FromIonError` and the bridges;
  `to_json` delegates to `@ion`.
- No new dependencies. No change to the text or binary codecs, Ion Schema,
  Ion Hash or the CLI.
