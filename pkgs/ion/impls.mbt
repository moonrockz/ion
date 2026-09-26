// Explicit trait-extension declarations for the derived implementations on the
// public data-model types.
//
// When a public type derives a trait, the compiler promotes that impl's methods
// as regular methods; declaring the extensions explicitly keeps the promotion
// intentional (and avoids the `implicit_impl_as_method` warning).

///|
pub extend IonType with Eq::{not_equal, equal}

///|
pub extend IonType with Hash::{hash, hash_combine}

///|
pub extend IonType with @debug.Debug::{to_repr}

///|
pub extend SymbolToken with Eq::{not_equal, equal}

///|
pub extend SymbolToken with Hash::{hash, hash_combine}

///|
pub extend SymbolToken with @debug.Debug::{to_repr}

///|
pub extend TimestampPrecision with Eq::{not_equal, equal}

///|
pub extend TimestampPrecision with Hash::{hash, hash_combine}

///|
pub extend TimestampPrecision with @debug.Debug::{to_repr}

///|
pub extend TimestampOffset with Eq::{not_equal, equal}

///|
pub extend TimestampOffset with Hash::{hash, hash_combine}

///|
pub extend TimestampOffset with @debug.Debug::{to_repr}

///|
pub extend Decimal with @debug.Debug::{to_repr}

///|
pub extend Timestamp with @debug.Debug::{to_repr}

///|
pub extend IonValueKind with @debug.Debug::{to_repr}

///|
pub extend Field with @debug.Debug::{to_repr}

///|
pub extend IonValue with @debug.Debug::{to_repr}

///|
pub extend IonError with @debug.Debug::{to_repr}
