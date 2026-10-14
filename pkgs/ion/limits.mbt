// Limits the readers set on their input, so that hostile input raises an
// IonError instead of exhausting the host.

///|
/// The deepest container nesting a reader accepts. A top-level container is
/// at depth 1, so `[[1]]` nests to depth 2. Annotations do not add depth.
///
/// The limit keeps deeply nested hostile input from exhausting the readers'
/// call stack. It does not bound the size of a value.
///
/// The code that walks values (equality, fold, visitor, writers, events, Ion
/// Hash and JSON conversion) keeps its call stack bounded at any depth: it
/// uses an explicit stack, and the JSON conversions recurse only down to this
/// depth. So a value built in code works at any depth.
pub const MAX_NESTING_DEPTH : Int32 = 128

///|
/// How deep a reader is inside nested containers. A reader starts at
/// [`NestingDepth::top`] and calls [`NestingDepth::enter`] for each container
/// it opens, which raises once the depth would pass [`MAX_NESTING_DEPTH`].
pub struct NestingDepth {
  priv level : Int32
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
