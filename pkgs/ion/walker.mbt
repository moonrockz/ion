// Walking an Ion value without recursion.
//
// A `ValueWalker` keeps the containers it is inside on a heap stack, so a
// walk costs heap memory per nesting level, not call stack. Every walker in
// the library that must handle values of any depth runs on it.

///|
/// One step of a depth-first walk over an Ion value, in document order.
///
/// `field` is the struct field name the value has in its parent, or `None`
/// outside a struct. A typed null of a container type, such as `null.list`,
/// is a `Scalar`: it has no children.
pub(all) enum WalkEvent {
  /// A value with no children.
  Scalar(IonValue, field~ : SymbolToken?)
  /// A list, S-expression or struct, before its children.
  Enter(IonValue, field~ : SymbolToken?)
  /// The same container, after its children.
  Exit(IonValue, field~ : SymbolToken?)
} derive(Debug)

///|
pub extend WalkEvent with @debug.Debug::{to_repr}

///|
/// Where the last step of a walk arrived. The walker's `current` and
/// `current_field` hold the value it arrived at, so a step allocates nothing.
priv enum WalkStep {
  AtScalar
  AtEnter
  AtExit
  Done
}

///|
/// A container the walker is inside, and the index of its next child.
priv struct WalkFrame {
  value : IonValue
  field : SymbolToken?
  mut next : Int
}

///|
/// A pull-based, depth-first walk over an Ion value that uses no recursion.
/// Build one with [`IonValue::walker`], then call [`ValueWalker::next`] until
/// it returns `None`.
pub struct ValueWalker {
  priv frames : Array[WalkFrame]
  priv mut started : Bool
  priv mut entered : Bool
  priv mut current : IonValue
  priv mut current_field : SymbolToken?
}

///|
/// A walker positioned before `self`.
pub fn IonValue::walker(self : IonValue) -> ValueWalker {
  {
    frames: [],
    started: false,
    entered: false,
    current: self,
    current_field: None,
  }
}

///|
/// The next event of the walk, or `None` when the walk is complete.
pub fn ValueWalker::next(self : ValueWalker) -> WalkEvent? {
  match self.step() {
    AtScalar => Some(Scalar(self.current, field=self.current_field))
    AtEnter => Some(Enter(self.current, field=self.current_field))
    AtExit => Some(Exit(self.current, field=self.current_field))
    Done => None
  }
}

///|
/// Advance the walk by one event and record where it arrived. The library's
/// own walkers call this in place of [`ValueWalker::next`], so they build no
/// `WalkEvent` per value.
fn ValueWalker::step(self : ValueWalker) -> WalkStep {
  self.entered = false
  if !self.started {
    self.started = true
    return self.arrive(self.current, None)
  }
  guard self.frames.last() is Some(frame) else { return Done }
  let index = frame.next
  match frame.value.kind {
    List(items) | Sexp(items) if index < items.length() => {
      frame.next = index + 1
      self.arrive(items[index], None)
    }
    Struct(fields) if index < fields.length() => {
      frame.next = index + 1
      let field = fields[index]
      self.arrive(field.value, Some(field.name))
    }
    _ => {
      ignore(self.frames.pop())
      self.current = frame.value
      self.current_field = frame.field
      AtExit
    }
  }
}

///|
/// Arrive at `value`. A container also opens a frame for its children.
fn ValueWalker::arrive(
  self : ValueWalker,
  value : IonValue,
  field : SymbolToken?,
) -> WalkStep {
  self.current = value
  self.current_field = field
  match value.kind {
    List(_) | Sexp(_) | Struct(_) => {
      self.frames.push({ value, field, next: 0, })
      self.entered = true
      AtEnter
    }
    _ => AtScalar
  }
}

///|
/// Skip the children of the container that the last [`ValueWalker::next`]
/// entered: the next event is that container's `Exit`. After any other event
/// it does nothing.
pub fn ValueWalker::skip_children(self : ValueWalker) -> Unit {
  if self.entered && self.frames.last() is Some(frame) {
    frame.next = match frame.value.kind {
      List(items) | Sexp(items) => items.length()
      Struct(fields) => fields.length()
      _ => frame.next
    }
  }
}

///|
/// The number of containers the walk is inside now: 1 after the `Enter` of a
/// top-level container, 0 again after its `Exit`.
pub fn ValueWalker::depth(self : ValueWalker) -> Int {
  self.frames.length()
}

///|
/// The events of a walk over `self`, as an iterator.
pub fn IonValue::walk(self : IonValue) -> Iter[WalkEvent] {
  let walker = self.walker()
  Iter::new(() => walker.next())
}

///|
/// Fold `self` bottom-up with no recursion. `scalar` gives a result for each
/// value with no children; `container` gives a result for each list,
/// S-expression or struct from its children's results, in order, each with
/// its field name (`None` outside a struct).
///
/// `container` runs after all of that container's children. A walk that must
/// act in document order (such as raising for the first bad symbol) uses
/// [`IonValue::walk`] instead. The children's results are kept until their
/// container finishes, so memory grows with the width of the open levels.
pub fn[R] IonValue::fold_up(
  self : IonValue,
  scalar~ : (IonValue) -> R raise?,
  container~ : (IonValue, Array[(SymbolToken?, R)]) -> R raise?,
) -> R raise? {
  let walker = self.walker()
  // One array per open container for its children's results; the first
  // array collects the result of `self`.
  let results : Array[Array[(SymbolToken?, R)]] = [[]]
  while walker.next() is Some(event) {
    match event {
      Scalar(value, field~) =>
        results[results.length() - 1].push((field, scalar(value)))
      Enter(_, ..) => results.push([])
      Exit(value, field~) =>
        if results.pop() is Some(children) {
          results[results.length() - 1].push(
            (field, container(value, children)),
          )
        }
    }
  }
  results[0][0].1
}
