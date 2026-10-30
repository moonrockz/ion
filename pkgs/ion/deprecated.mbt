///|
/// Build a value from a kind, with no annotations. Use `Ion(kind)` instead.
#deprecated("Use `Ion(kind)` instead")
pub fn Ion::new(kind : IonValueKind) -> IonValue {
  Ion(kind)
}

///|
#deprecated("Use `Ion(kind)` instead")
pub extend IonValueKind with ToIon::{to_ion}

///|
#deprecated("Use `Ion(value)` instead")
pub extend Ion with ToIon::{to_ion}

///|
#deprecated("Use `Ion(value)` instead")
pub extend Decimal with ToIon::{to_ion}

///|
#deprecated("Use `Ion(value)` instead")
pub extend Timestamp with ToIon::{to_ion}

///|
#deprecated("Use `Ion(value)` instead")
pub extend SymbolToken with ToIon::{to_ion}

///|
/// `FromIon` is called through the trait, not as a method.
#deprecated("Use `FromIon::from_ion(value)` instead")
pub extend Ion with FromIon::{from_ion}

///|
#deprecated("Use `FromIon::from_ion(value)` instead")
pub extend Decimal with FromIon::{from_ion}

///|
#deprecated("Use `FromIon::from_ion(value)` instead")
pub extend Timestamp with FromIon::{from_ion}

///|
#deprecated("Use `FromIon::from_ion(value)` instead")
pub extend SymbolToken with FromIon::{from_ion}
