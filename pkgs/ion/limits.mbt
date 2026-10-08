// Limits the readers set on their input, so that hostile input raises an
// IonError instead of exhausting the host.

///|
/// The deepest container nesting a reader accepts. A top-level container is
/// at depth 1, so `[[1]]` nests to depth 2. Annotations do not add depth.
///
/// The readers and the code that walks the values they return recurse once
/// per nesting level. The limit keeps that recursion far from the call stack
/// size of every target, including a cold JavaScript or wasm-gc engine.
pub const MAX_NESTING_DEPTH : Int = 128

///|
/// How deep a reader is inside nested containers. A reader starts at
/// [`NestingDepth::top`] and calls [`NestingDepth::enter`] for each container
/// it opens, which raises once the depth would pass [`MAX_NESTING_DEPTH`].
pub struct NestingDepth {
  priv level : Int
}

///|
/// The depth of a top-level value: inside no container.
pub fn NestingDepth::top() -> NestingDepth {
  { level: 0, }
}

///|
/// The depth inside one more container, or `IonError::LimitExceeded` when
/// that container would nest deeper than [`MAX_NESTING_DEPTH`].
pub fn NestingDepth::enter(self : NestingDepth) -> NestingDepth raise IonError {
  if self.level >= MAX_NESTING_DEPTH {
    raise LimitExceeded(
      "containers nest deeper than the limit of \{MAX_NESTING_DEPTH} levels",
    )
  }
  { level: self.level + 1, }
}
