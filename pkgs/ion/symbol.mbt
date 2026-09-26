// Ion symbol tokens.
//
// Symbols are interned identifiers. In Ion text every symbol has text; in Ion
// binary a symbol may be known only by its symbol ID, so the text can be
// absent. That absence is modelled as `None`, never as an empty string.

///|
/// A symbol token: the text of a symbol when it is known, and its symbol ID
/// when the value came from a context (such as Ion binary) that assigned one.
pub struct SymbolToken {
  text : String?
  sid : Int?
} derive(Eq, Hash, Debug)

///|
/// A symbol token with known text.
pub fn SymbolToken::new(text : String) -> SymbolToken {
  { text: Some(text), sid: None, }
}

///|
/// A symbol token known only by its symbol ID.
pub fn SymbolToken::from_sid(sid : Int) -> SymbolToken {
  { text: None, sid: Some(sid), }
}

///|
/// The symbol's text, when known.
pub fn SymbolToken::text(self : SymbolToken) -> String? {
  self.text
}

///|
/// The symbol's ID, when the context assigned one.
pub fn SymbolToken::sid(self : SymbolToken) -> Int? {
  self.sid
}

///|
/// Whether the symbol's text is known.
pub fn SymbolToken::has_text(self : SymbolToken) -> Bool {
  self.text is Some(_)
}

///|
/// The symbol's text, raising [`IonError::Unsupported`] when the symbol is
/// known only by ID.
pub fn SymbolToken::require_text(self : SymbolToken) -> String raise IonError {
  match self.text {
    Some(text) => text
    None =>
      raise IonError::Unsupported(
        "symbol is known only by ID (sid=\{self.sid.unwrap()}); its text is not available",
      )
  }
}
