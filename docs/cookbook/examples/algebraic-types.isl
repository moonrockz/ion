$ion_schema_2_0

type::{
  name: point,
  type: struct,
  fields: closed::{
    x: {type: decimal, occurs: required},
    y: {type: decimal, occurs: required},
    label: {type: $null_or::string},
  },
}

type::{
  name: positive_decimal,
  type: decimal,
  valid_values: range::[exclusive::0., max],
}

type::{
  name: circle,
  type: struct,
  fields: closed::{
    kind: {type: symbol, valid_values: [circle], occurs: required},
    center: {type: point, occurs: required},
    radius: {type: positive_decimal, occurs: required},
  },
}

type::{
  name: rectangle,
  type: struct,
  fields: closed::{
    kind: {type: symbol, valid_values: [rectangle], occurs: required},
    width: {type: positive_decimal, occurs: required},
    height: {type: positive_decimal, occurs: required},
  },
}

type::{name: shape, one_of: [circle, rectangle]}
type::{name: color, type: symbol, valid_values: [red, green, blue]}

type::{
  name: none_int,
  type: symbol,
  valid_values: [none],
  annotations: closed::[],
}

type::{
  name: some_int,
  type: int,
  annotations: {ordered_elements: [{valid_values: [some], occurs: required}]},
}

type::{name: option_int, one_of: [none_int, some_int]}

type::{
  name: leaf,
  type: struct,
  fields: closed::{
    kind: {type: symbol, valid_values: [leaf], occurs: required},
    value: {type: int, occurs: required},
  },
}

type::{
  name: branch,
  type: struct,
  fields: closed::{
    kind: {type: symbol, valid_values: [branch], occurs: required},
    children: {type: list, element: tree, occurs: required},
  },
}

type::{name: tree, one_of: [leaf, branch]}
