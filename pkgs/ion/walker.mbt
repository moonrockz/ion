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
/// The children of a container that the walker is inside.
priv enum WalkChildren {
  Items(Array[IonValue])
  Fields(Array[Field])
}

///|
fn WalkChildren::length(self : WalkChildren) -> Int {
  match self {
    Items(items) => items.length()
    Fields(fields) => fields.length()
  }
}

///|
/// A container the walker is inside, and the index of its next child.
priv struct WalkFrame {
  value : IonValue
  field : SymbolToken?
  children : WalkChildren
  mut next : Int
}

///|
/// A pull-based, depth-first walk over an Ion value that uses no recursion.
/// Build one with [`IonValue::walker`], then call [`ValueWalker::next`] until
/// it returns `None`.
pub struct ValueWalker {
  priv frames : Array[WalkFrame]
  priv mut root : IonValue?
  priv mut entered : Bool
}

///|
/// A walker positioned before `self`.
pub fn IonValue::walker(self : IonValue) -> ValueWalker {
  { frames: [], root: Some(self), entered: false, }
}

///|
/// The next event of the walk, or `None` when the walk is complete.
pub fn ValueWalker::next(self : ValueWalker) -> WalkEvent? {
  self.entered = false
  if self.root is Some(value) {
    self.root = None
    return Some(self.visit(value, None))
  }
  guard self.frames.last() is Some(frame) else { return None }
  match frame.children {
    Items(items) if frame.next < items.length() => {
      let item = items[frame.next]
      frame.next += 1
      Some(self.visit(item, None))
    }
    Fields(fields) if frame.next < fields.length() => {
      let field = fields[frame.next]
      frame.next += 1
      Some(self.visit(field.value, Some(field.name)))
    }
    _ => {
      ignore(self.frames.pop())
      Some(Exit(frame.value, field=frame.field))
    }
  }
}

///|
/// The event for `value`. A container also opens a frame for its children.
fn ValueWalker::visit(
  self : ValueWalker,
  value : IonValue,
  field : SymbolToken?,
) -> WalkEvent {
  let children = match value.kind {
    List(items) | Sexp(items) => WalkChildren::Items(items)
    Struct(fields) => WalkChildren::Fields(fields)
    _ => return Scalar(value, field~)
  }
  self.frames.push({ value, field, children, next: 0, })
  self.entered = true
  Enter(value, field~)
}

///|
/// Skip the children of the container that the last [`ValueWalker::next`]
/// entered: the next event is that container's `Exit`. After any other event
/// it does nothing.
pub fn ValueWalker::skip_children(self : ValueWalker) -> Unit {
  if self.entered && self.frames.last() is Some(frame) {
    frame.next = frame.children.length()
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
