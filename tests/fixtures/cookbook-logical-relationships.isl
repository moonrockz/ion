// Ion Schema Cookbook: expressing logical relationships between fields.
// https://amazon-ion.github.io/ion-schema/docs/cookbook/logical-relationships.html
//
// Exercised by pkgs/schema/cookbook_test.mbt. The `any_of` + `nothing` forms
// express propositional logic, and `contains` reasons about list elements.

type::{
  name: Address,
  fields: {
    country: string,
    street: string,
    postal_code: string,
    zip: int,
    state: string,
    province: string,
  },
}

type::{
  name: a_or_b,
  type: struct,
  any_of: [
    { fields: { a: { occurs: required } } },
    { fields: { b: { occurs: required } } },
  ],
}

type::{
  name: a_implies_b,
  type: struct,
  any_of: [
    { fields: { a: nothing } },
    { fields: { b: { occurs: required } } },
  ],
}

type::{
  name: a_implies_not_b,
  type: struct,
  any_of: [
    { fields: { a: nothing } },
    { fields: { b: nothing } },
  ],
}

type::{
  name: a_iff_b,
  type: struct,
  any_of: [
    { fields: { a: { occurs: required }, b: { occurs: required } } },
    { fields: { a: nothing, b: nothing } },
  ],
}

type::{
  name: a_xor_b,
  type: struct,
  any_of: [
    { fields: { a: { occurs: required }, b: nothing } },
    { fields: { a: nothing, b: { occurs: required } } },
  ],
}

type::{
  name: contains_a_implies_contains_b,
  type: list,
  any_of: [
    { not: { contains: [A] } },
    { contains: [B] },
  ],
}
