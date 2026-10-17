# Run recursive parsing and validation on heap continuations

Ion accepts unrestricted nesting by default. Readers, schema loading,
validation and regex compilation use MoonBit's compiler-generated
continuations through a local synchronous executor, following
[gleam-parser PR #20](https://github.com/moonrockz/gleam-parser/pull/20).
This preserves the grammar functions, typed errors and cleanup scopes while
keeping public entry points synchronous.

Recursive paths request scheduling before descent and during return,
including error unwinding. The executor resumes bounded batches to reduce
scheduling overhead. Cross-target tests cover deep success, failure and
reuse after failure. Compiler primitives `%async.run` and `%async.suspend`
are isolated in `internal/work`; CI and release builds pin the toolchain.

Fuel is caller policy, independent of machine stack size. `Unlimited` is
the default; `Limited(Budget)` bounds open nested operations and restores
the enclosing budget on success or error. Exhaustion raises a structured
`IonError::FuelExhausted`, including from schema validation. Cycle detection
remains necessary and independent. Fuel does not bound total work or memory.

Existing iterative value walkers and bounded recursive fast paths stay in
place. Text and binary readers also keep direct recursive container grammar
for shallow values and switch to continuations at an internal threshold.
Their scalar decoders are shared; tests cover both grammar paths and fuel
accounting across the switch. This avoids continuation scheduling on ordinary shallow input.
JSON's container grammar uses the executor while core JSON decodes
scalar tokens, preserving its number and Unicode semantics without its
recursive container parser or fixed nesting cap.
