///|
/// Convert a core JSON value to Ion. Use `Ion(json)` instead.
#deprecated("Use `@json.Ion(json)` instead")
pub fn to_ion(json : Json) -> @core.IonValue {
  Ion(json)
}
