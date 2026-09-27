// A loaded Ion Schema: a set of named type definitions.

///|
/// A named Ion Schema type: a name and the constraints its values must satisfy.
pub struct TypeDefinition {
  name : String
  constraints : Array[Constraint]
} derive(Debug)

///|
/// A loaded Ion Schema.
pub struct Schema {
  types : Array[TypeDefinition]
} derive(Debug)

///|
/// An empty schema.
pub fn Schema::empty() -> Schema {
  { types: [], }
}

///|
/// A schema built from explicit type definitions.
pub fn Schema::from_types(types : Array[TypeDefinition]) -> Schema {
  { types, }
}

///|
/// The schema's type definitions.
pub fn Schema::types(self : Schema) -> Array[TypeDefinition] {
  self.types
}

///|
/// The named type definition, when present.
pub fn Schema::find(self : Schema, name : String) -> TypeDefinition? {
  for definition in self.types {
    if definition.name == name {
      return Some(definition)
    }
  }
  None
}

///|
/// The type definition's name.
pub fn TypeDefinition::name(self : TypeDefinition) -> String {
  self.name
}

///|
/// The type definition's constraints.
pub fn TypeDefinition::constraints(self : TypeDefinition) -> Array[Constraint] {
  self.constraints
}

///|
pub extend TypeDefinition with @debug.Debug::{to_repr}

///|
pub extend Schema with @debug.Debug::{to_repr}
