// The Ion Schema Language constraint model.
//
// This is a focused subset of ISL 2.0. Constructs the loader does not
// recognize are reported as unsupported rather than silently ignored, as the
// specification requires.

///|
/// An occurrence range: how many times a matching element or field must (or may)
/// appear.
pub struct Occurs {
  lower : Int
  upper : Int?
} derive(Debug)

///|
/// An occurrence range with an optional upper bound (`None` is unbounded).
pub fn Occurs::new(lower : Int, upper : Int?) -> Occurs {
  { lower, upper, }
}

///|
/// Exactly once.
pub fn Occurs::required() -> Occurs {
  { lower: 1, upper: Some(1), }
}

///|
/// Zero or one time.
pub fn Occurs::optional() -> Occurs {
  { lower: 0, upper: Some(1), }
}

///|
/// Whether `count` is within the range.
pub fn Occurs::allows(self : Occurs, count : Int) -> Bool {
  if count < self.lower {
    return false
  }
  match self.upper {
    Some(upper) => count <= upper
    None => true
  }
}

///|
/// A named field within a `fields` constraint.
pub struct FieldConstraint {
  name : String
  ty : Constraint
  occurs : Occurs
} derive(Debug)

///|
/// A constraint over a value.
pub(all) enum Constraint {
  /// `type: int` or `type: [int, string]`.
  IsType(Array[@ion.IonType])
  /// `$null_or::X`: the value is null, or satisfies `X`.
  NullOr(Constraint)
  /// A reference to a type defined elsewhere in the schema.
  TypeRef(String)
  /// Every element of a list or S-expression satisfies the constraint; the
  /// optional occurrence range constrains the element count.
  Element(Constraint, Occurs?)
  /// The struct's fields, by name.
  Fields(Array[FieldConstraint])
  /// `valid_values: [...]`.
  ValidValues(Array[@ion.IonValue])
  /// `container_length`: the number of elements or fields.
  ContainerLength(Int, Int?)
  /// `codepoint_length`: the number of code points in a string or symbol.
  CodepointLength(Int, Int?)
  /// All of the nested constraints hold.
  AllOf(Array[Constraint])
  /// At least one of the nested constraints holds.
  AnyOf(Array[Constraint])
  /// Exactly one of the nested constraints holds.
  OneOf(Array[Constraint])
  /// The nested constraint does not hold.
  Not(Constraint)
  /// `nothing`: a constraint that no value satisfies.
  Nothing
  /// `contains: [ ... ]`: every listed constraint matches at least one element.
  Contains(Array[Constraint])
} derive(Debug)

///|
/// A constraint that always holds, used for `$any`.
pub fn Constraint::any() -> Constraint {
  AllOf([])
}

///|
pub extend Occurs with @debug.Debug::{to_repr}

///|
pub extend FieldConstraint with @debug.Debug::{to_repr}

///|
pub extend Constraint with @debug.Debug::{to_repr}
