// Converting Ion values to JSON.
//
// The conversion itself lives in the core package, as `FromIon` for `Json`,
// so that `Json` decodes like any other type. This wrapper keeps the
// package's `IonError` contract.

///|
/// Convert an Ion value to a core `Json` value following the Ion cookbook's
/// "Down-converting to JSON" rules: nulls become `null`, numbers keep their
/// precision, `nan` and the infinities become `null`, timestamps, symbols,
/// clobs and Base64 blobs become strings, S-expressions become arrays and
/// annotations are dropped. Any nesting depth works.
///
/// Raises [`@core.IonError::Unsupported`] when a symbol or struct field name
/// is known only by symbol ID, so it has no text to emit: for the first such
/// symbol in document order, and the message names its path. Repeated field
/// names fold onto the last occurrence, because a JSON object cannot hold
/// duplicates.
pub fn to_json(value : @core.IonValue) -> Json raise @core.IonError {
  (@core.FromIon::from_ion(value) : Json) catch {
    error => raise @core.IonError::Unsupported(error.message())
  }
}
