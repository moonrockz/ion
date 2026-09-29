// Types from the Ion Schema Cookbook page "Optionally ignoring the occurs
// requirement for fields"
// (https://amazon-ion.github.io/ion-schema/docs/cookbook/ignore-occurs-requirements).
// The page uses an `Address` type it does not define; this one is a stand-in.
$ion_schema_2_0

type::{
  name: Address,
  type: struct,
  fields: { street: string, city: string },
}

type::{
  name: CustomerFieldTypes,
  fields: closed::{
    title: { valid_values: ["Dr.", "Mr.", "Mrs.", "Ms."] },
    firstName: string,
    middleName: string,
    lastName: string,
    suffix: { valid_values: ["Jr.", "Sr.", "PhD"] },
    preferredName: string,
    customerId: {
      one_of: [
        { type: string, codepoint_length: 18 },
        { type: int, valid_values: range::[100000, 999999] },
      ],
    },
    addresses: { type: list, element: Address },
    lastUpdated: { timestamp_precision: second },
  },
}

type::{
  name: CustomerFieldOccurrences,
  fields: {
    firstName: { occurs: required },
    lastName: { occurs: required },
    addresses: { occurs: required },
    customerId: { occurs: required },
    lastUpdated: { occurs: required },
  }
}

type::{
  name: Customer,
  all_of: [CustomerFieldTypes, CustomerFieldOccurrences],
}
