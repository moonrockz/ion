// A functional fold over an Ion value tree, with flow control.
//
// The analogue of gherkin's `GherkinFold`: callbacks thread an accumulator
// through the tree and may direct traversal with a `FoldAction`. The fold runs
// on `ValueWalker`, so it works at any nesting depth.

///|
/// Control flow returned by a fold callback.
///
/// - `Continue(a)` — descend into the value's children with the new accumulator
/// - `SkipChildren(a)` — do not descend, continue with siblings
/// - `Stop(a)` — stop the whole traversal and return `a`
pub(all) enum FoldAction[A] {
  Continue(A)
  SkipChildren(A)
  Stop(A)
} derive(Debug, Eq)

///|
/// The accumulator carried by a `FoldAction`.
pub fn[A] FoldAction::value(self : FoldAction[A]) -> A {
  match self {
    Continue(a) | SkipChildren(a) | Stop(a) => a
  }
}

///|
/// Whether this action stops the traversal.
pub fn[A] FoldAction::is_stop(self : FoldAction[A]) -> Bool {
  match self {
    Stop(_) => true
    _ => false
  }
}

///|
/// The callbacks for a fold over an Ion value.
///
/// Build one with [`IonFold::default`] and override the fields you need, or use
/// [`continuing`] to lift a plain accumulator function.
pub(all) struct IonFold[A] {
  /// Called for every value, before its annotations and children.
  visit_value : (A, IonValue) -> FoldAction[A]
  /// Called for each annotation on a value, in order.
  visit_annotation : (A, SymbolToken) -> FoldAction[A]
  /// Called for each struct field name, before its value.
  visit_field_name : (A, SymbolToken) -> FoldAction[A]
}

///|
/// A fold whose callbacks pass the accumulator through unchanged.
pub fn[A] IonFold::default() -> IonFold[A] {
  {
    visit_value: fn(a, _) { Continue(a) },
    visit_annotation: fn(a, _) { Continue(a) },
    visit_field_name: fn(a, _) { Continue(a) },
  }
}

///|
/// Lift a plain `(A, N) -> A` function into a callback that always continues
/// into children.
pub fn[A, N] continuing(f : (A, N) -> A) -> (A, N) -> FoldAction[A] {
  fn(a, n) { Continue(f(a, n)) }
}

///|
/// Fold over this value, depth-first in document order, threading `acc` and
/// honoring [`FoldAction`] flow control.
pub fn[A] IonValue::fold(self : IonValue, acc : A, folder : IonFold[A]) -> A {
  fold_value(self, acc, folder).value()
}

///|
/// Fold over every value of a datagram, in order.
pub fn[A] fold_values(
  values : Array[IonValue],
  acc : A,
  folder : IonFold[A],
) -> A {
  let mut acc = acc
  for value in values {
    match fold_value(value, acc, folder) {
      Stop(a) => return a
      Continue(a) | SkipChildren(a) => acc = a
    }
  }
  acc
}

///|
/// The core of [`IonValue::fold`]: a walk with no recursion. Returns `Stop`
/// to abort the whole traversal. For each value it calls `visit_field_name`
/// (inside a struct), then `visit_value`, then `visit_annotation` for each
/// annotation, then folds the children unless `visit_value` skipped them.
fn[A] fold_value(
  value : IonValue,
  acc : A,
  folder : IonFold[A],
) -> FoldAction[A] {
  let walker = value.walker()
  let mut acc = acc
  while walker.next() is Some(event) {
    let (current, field) = match event {
      Scalar(current, field~) | Enter(current, field~) => (current, field)
      Exit(_, ..) => continue
    }
    if field is Some(name) {
      match (folder.visit_field_name)(acc, name) {
        Stop(a) => return Stop(a)
        Continue(a) | SkipChildren(a) => acc = a
      }
    }
    match (folder.visit_value)(acc, current) {
      Stop(a) => return Stop(a)
      SkipChildren(a) => {
        acc = a
        walker.skip_children()
      }
      Continue(a) => acc = a
    }
    for annotation in current.annotations() {
      match (folder.visit_annotation)(acc, annotation) {
        Stop(a) => return Stop(a)
        Continue(a) | SkipChildren(a) => acc = a
      }
    }
  }
  Continue(acc)
}

///|
pub extend FoldAction with @debug.Debug::{to_repr}

///|
pub extend FoldAction with Eq::{not_equal, equal}
