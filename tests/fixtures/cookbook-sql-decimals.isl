// Types from the Ion Schema Cookbook page "Modeling SQL Decimals in Ion
// Schema" (https://amazon-ion.github.io/ion-schema/docs/cookbook/sql-decimals),
// each named here. The page writes the last type's exponent as `[-2, max]`;
// the range needs its `range::` annotation.
$ion_schema_2_0

// DECIMAL(5,2): exact precision and exact scale.
type::{
  name: exact_precision_and_scale,
  precision: 5,
  exponent: -2,
}

// DECIMAL(5,2): compatible precision and exact scale.
type::{
  name: compatible_precision_exact_scale,
  precision: range::[min, 5],
  exponent: -2,
}

// DECIMAL(5,2): fits without rounding or truncating.
type::{
  name: fits_decimal_5_2,
  exponent: range::[-2, max],
  valid_values: range::[-999.99, 999.99],
}
