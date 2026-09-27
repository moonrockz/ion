// Errors raised by the Ion reader, writer, and schema validator.

///|
/// An error raised while reading, writing, or validating Ion.
pub(all) suberror IonError {
  /// A syntax or encoding error in Ion text or binary input.
  Syntax(String)
  /// Syntactically valid input that violates the Ion data model, such as a
  /// timestamp year before 1 or an out-of-range month.
  DataModel(String)
  /// A construct this implementation does not (yet) support.
  Unsupported(String)
} derive(Debug)

///|
/// The human-readable message carried by an [`IonError`].
pub fn IonError::message(self : IonError) -> String {
  match self {
    Syntax(message) => message
    DataModel(message) => message
    Unsupported(message) => message
  }
}
