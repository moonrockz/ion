# Tasks

## 1. Decode trait and error

Tracking: bd `ion-sfb`.

- [ ] 1.1 Add `FromIon`, `FromIonError`, `PathSegment` and `ValueRange` to `@ion`, with tests for `message()`, `path()` and `within()`.
- [ ] 1.2 Add `FromIon` for the scalar types (`Unit`, `Bool`, the integer types, `Float`, `Double`, `String`, `Bytes`, `BigInt`, `Decimal`, `Timestamp`, `SymbolToken`, `Ion`), with example tests at every range limit and for typed nulls.

## 2. Containers and new codecs

- [ ] 2.1 Add `FromIon` for `Array[T]` and `Map[String, T]`, with tests for paths, duplicate names and names with no text.
- [ ] 2.2 Add `ToIon` and `FromIon` for `Option[T]`, `Char`, `Byte` and tuples of two and three, with example tests.

## 3. JSON

- [ ] 3.1 Move the Ion to JSON conversion into `@ion`, add `FromIon` for `Json`, and keep `@json.to_json` and its tests green.
- [ ] 3.2 Add `@json.to_ion_via_json` and `@json.from_ion_via_json`, with tests for derived types, Ion to JSON failures and `FromJson` failures.

## 4. Laws and documentation

- [ ] 4.1 Add quickcheck round-trip properties for every supported type.
- [ ] 4.2 Document decoding in the `@ion` and `@json` READMEs (executable examples) and the cookbook.
- [ ] 4.3 Run `moon info && moon fmt`, `mise run test:all`, and `openspec validate --all --strict`.

## Workflow follow-up

- Follow AGENTS.md for review, archive, tracker closure and release approval.
