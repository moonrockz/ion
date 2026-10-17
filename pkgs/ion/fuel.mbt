///|
/// A positive number of simultaneously open nested operations.
pub struct Budget {
  priv units : Int32
} derive(Debug, Eq)

///|
/// Create a positive fuel budget, or raise `DataModel` for zero or less.
pub fn Budget::Budget(units : Int32) -> Budget raise IonError {
  guard units > 0 else {
    raise DataModel("a fuel budget must contain at least one unit")
  }
  { units, }
}

///|
/// The number of units in this budget.
pub fn Budget::units(self : Budget) -> Int32 {
  self.units
}

///|
/// Optional scoped fuel. Nesting is unrestricted unless the caller supplies
/// `Limited(Budget(...))`. Siblings reuse their enclosing operation's fuel.
/// Fuel bounds open operations, not total work, memory, or elapsed time.
pub(all) enum Fuel {
  Unlimited
  Limited(Budget)
} derive(Debug, Eq)

///|
/// The operation that tried to enter a nested scope after fuel ran out.
pub(all) enum FuelOperation {
  TextRead
  BinaryRead
  CstRead
  JsonRead
  SchemaLoad
  SchemaImport
  SchemaValidate
  RegexParse
  RegexCompile
} derive(Debug, Eq)

///|
/// Where fuel ran out. Text offsets count UTF-16 code units; binary offsets
/// count octets. Value paths use the schema validator's `$` notation.
pub(all) enum FuelLocation {
  TextOffset(Int32)
  /// Code-point offset within a regular expression.
  CharacterOffset(Int32)
  /// Index in a compiled regular expression's instruction program.
  RegexInstruction(Int32)
  BinaryOffset(Int32)
  ValuePath(String)
  SchemaId(String)
} derive(Debug, Eq)

///|
/// An immutable scoped fuel cursor used by the library's implementations.
#doc(hidden)
pub struct FuelState {
  priv fuel : Fuel
  priv level : Int32
}

///|
#doc(hidden)
pub fn Fuel::start(self : Fuel) -> FuelState {
  { fuel: self, level: 0, }
}

///|
/// Enter a scope. Keep the outer state to restore fuel on success or error.
#doc(hidden)
pub fn FuelState::enter(
  self : FuelState,
  operation : FuelOperation,
  location : FuelLocation,
) -> FuelState raise IonError {
  match self.fuel {
    Unlimited => self
    Limited(budget) => {
      if self.level >= budget.units {
        raise FuelExhausted(budget~, operation~, location~)
      }
      { fuel: self.fuel, level: self.level + 1, }
    }
  }
}

///|
pub extend Budget with @debug.Debug::{to_repr}

///|
pub extend Budget with Eq::{equal, not_equal}

///|
pub extend Fuel with @debug.Debug::{to_repr}

///|
pub extend Fuel with Eq::{equal, not_equal}

///|
pub extend FuelOperation with @debug.Debug::{to_repr}

///|
pub extend FuelOperation with Eq::{equal, not_equal}

///|
pub extend FuelLocation with @debug.Debug::{to_repr}

///|
pub extend FuelLocation with Eq::{equal, not_equal}
