// Types from the Ion Schema Cookbook page "Versioned types"
// (https://amazon-ion.github.io/ion-schema/docs/cookbook/versioned-types):
// the schemas of its examples, in the order the page gives them.
$ion_schema_2_0

type::{
  name: Widget,
  fields: closed::{
    version: { type: int, occurs: required },
    name: { type: string, occurs: required },
    color: string,       // since v2
    weight: decimal,     // since v3
    dimensions: string,  // since v3
  },
  // Optional fields added in v2:
  // Either `color` is absent, or `version` >= 2.
  any_of: [
    { fields: { color: nothing } },
    { fields: { version: { valid_values: range::[2, max] } } },
  ],
  // Optional fields added in v3:
  // Either `weight` and `dimensions` are absent, or `version` >= 3.
  any_of: [
    { fields: { weight: nothing, dimensions: nothing } },
    { fields: { version: { valid_values: range::[3, max] } } },
  ],
}

// The `priority` enum, v3 variants
type::{
  name: PriorityV3,
  valid_values: [low, medium, high],
}

// The `priority` enum, v4 variants (adds `critical`)
type::{
  name: PriorityV4,
  valid_values: [low, medium, high, critical],
}

type::{
  name: ApiResponse,
  fields: closed::{
    version: { occurs: required, type: int },
    request_id: { occurs: required, type: any },
    status: { occurs: required, type: string },
    payload: { occurs: required, type: struct },
    metadata: struct,       // added v2, removed v4
    priority: symbol,       // added v3, expanded v4
  },

  // --- request_id type evolution ---
  // In v1, request_id must be int.
  // In v2+, request_id can be int or string.
  any_of: [
    { fields: { request_id: int } },
    { fields: { request_id: { any_of: [int, string] }, version: { valid_values: range::[2, max] } } },
  ],

  // --- metadata lifecycle ---
  // metadata allowed only in v2 and v3
  any_of: [
    { fields: { metadata: nothing } },
    { fields: { version: { valid_values: range::[2, 3] } } },
  ],

  // --- priority lifecycle ---
  // In v3, priority must use the v3 variant set.
  // In v4+, priority may use the expanded variant set.
  // Before v3, priority must be absent.
  any_of: [
    { fields: { priority: nothing } },
    { fields: { version: { valid_values: [3] },
                priority: PriorityV3 } },
    { fields: { version: { valid_values: range::[4, max] },
                priority: PriorityV4 } },
  ],
}

type::{
  name: WidgetStrict,
  fields: closed::{
    version: { occurs: required, type: int },
    name: { occurs: required, type: string },
    color: string,  // required since v2
  },
  // `color` not allowed in v1, required in v2+
  any_of: [
    { fields: { color: nothing, version: { valid_values: [1] } } },
    { fields: { color: { occurs: required }, version: { valid_values: range::[2, max] } } },
  ],
}

type::{
  name: ThreeStateExample,
  fields: closed::{
    version: { occurs: required, type: int },
    name: { occurs: required, type: string },
    email: string,  // optional in v2, required in v3+
  },
  // email not allowed before v2
  any_of: [
    { fields: { email: nothing } },
    { fields: { version: { valid_values: range::[2, max] } } },
  ],
  // email required in v3+
  any_of: [
    { fields: { version: { valid_values: range::[min, 2] } } },
    { fields: { email: { occurs: required } } },
  ],
}

type::{
  name: CartItem,
  fields: closed::{
    version: { occurs: required, type: int },
    product_id: { occurs: required, type: string },
    quantity: { occurs: required, type: int },
    unit_price: decimal,    // since v2
    discount: decimal,      // since v3
  },
  any_of: [
    { fields: { unit_price: nothing } },
    { fields: { version: { valid_values: range::[2, max] } } },
  ],
  any_of: [
    { fields: { discount: nothing } },
    { fields: { version: { valid_values: range::[3, max] } } },
  ],
}

type::{
  name: ShoppingCart,
  fields: closed::{
    version: { occurs: required, type: int },
    cart_id: { occurs: required, type: string },
    items: { occurs: required, type: list, element: CartItem },
    coupon_code: string,    // since v2
    shipping_estimate: {    // since v2
      timestamp_precision: day,
    },
  },
  any_of: [
    { fields: { coupon_code: nothing, shipping_estimate: nothing } },
    { fields: { version: { valid_values: range::[2, max] } } },
  ],
}
