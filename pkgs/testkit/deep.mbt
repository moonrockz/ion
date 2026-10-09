// Deep values: chains of one-child containers, built with a loop from the
// inside out, so building one never recurses at any depth.

///|
/// The container that each level of a deep value adds.
pub(all) enum DeepShape {
  /// `[[...]]`
  List
  /// `((...))`
  Sexp
  /// `{name: {name: ...}}`
  Struct
  /// `name::[name::[...]]`
  AnnotatedList
  /// List, struct and sexp in turn, from the outside in.
  Mixed
} derive(Debug, Eq)

///|
pub extend DeepShape with @debug.Debug::{to_repr}

///|
pub extend DeepShape with Eq::{not_equal, equal}

///|
/// The shape of nesting level `level`, where level 0 is the outermost
/// container. `Mixed` resolves to list, struct or sexp; the other shapes are
/// the same at every level.
pub fn DeepShape::at(self : DeepShape, level : Int) -> DeepShape {
  match self {
    Mixed =>
      match level % 3 {
        0 => List
        1 => Struct
        _ => Sexp
      }
    shape => shape
  }
}

///|
/// A value nested `depth` containers deep around `leaf`. The struct field name
/// and the annotation are `name`, the Ion 1.0 system symbol 4, so a binary
/// encoding of the value needs no local symbol table.
pub fn deep_value(
  shape : DeepShape,
  depth : Int,
  leaf? : @ion.IonValue = @ion.IonValue::int(1),
) -> @ion.IonValue {
  let name = @ion.SymbolToken::new("name")
  let mut value = leaf
  for level = depth - 1; level >= 0; level = level - 1 {
    value = match shape.at(level) {
      // `at` never returns `Mixed`; the arm only completes the match.
      List | Mixed => @ion.IonValue::list([value])
      Sexp => @ion.IonValue::sexp([value])
      Struct =>
        @ion.IonValue::from_fields([@ion.Field::from_token(name, value)])
      AnnotatedList => @ion.IonValue::list([value]).with_annotation(name)
    }
  }
  value
}

///|
/// The innermost value of a chain of one-child containers, and how many
/// containers lead to it. The walk is a loop, so it works at any depth.
pub fn innermost(value : @ion.IonValue) -> (@ion.IonValue, Int) {
  let mut current = value
  let mut depth = 0
  while true {
    match current.kind() {
      List([child]) | Sexp([child]) => current = child
      Struct([field]) => current = field.value()
      _ => break
    }
    depth += 1
  }
  (current, depth)
}
