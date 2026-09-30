// Ion symbol tokens.
//
// Symbols are interned identifiers. Either encoding can refer to a symbol
// whose text is unknown. That absence is `None`, never an empty string; an
// unknown imported symbol retains its shared-table name and slot.

///|
/// The identity of an imported symbol with unknown text. `sid` is its
/// one-based position in the shared table, not its ID in a stream.
pub struct ImportLocation {
  name : String
  sid : Int
} derive(Eq, Hash, Debug)

///|
/// A symbol token: known text, a stream-local symbol ID, and the shared-table
/// location when an imported symbol's text is unknown.
pub struct SymbolToken {
  text : String?
  sid : Int?
  import_location : ImportLocation?
  import_version : Int?
} derive(Eq, Hash, Debug)

///|
/// A symbol token with known text.
pub fn SymbolToken::new(text : String) -> SymbolToken {
  { text: Some(text), sid: None, import_location: None, import_version: None, }
}

///|
/// A symbol token known only by its symbol ID.
pub fn SymbolToken::from_sid(sid : Int) -> SymbolToken {
  { text: None, sid: Some(sid), import_location: None, import_version: None, }
}

///|
/// An imported symbol with unknown text. The local ID and table version are
/// retained for serialization; equivalence uses only `name` and `import_sid`.
pub fn SymbolToken::from_import(
  sid : Int,
  name : String,
  version : Int,
  import_sid : Int,
) -> SymbolToken {
  {
    text: None,
    sid: Some(sid),
    import_location: Some({ name, sid: import_sid, }),
    import_version: Some(version),
  }
}

///|
/// Ion symbol equivalence. Known text determines identity; otherwise imported
/// symbols compare by table name and slot, and local unknown symbols equal $0.
pub fn SymbolToken::equivalent(self : SymbolToken, other : SymbolToken) -> Bool {
  match (self.text, other.text) {
    (Some(a), Some(b)) => a == b
    (None, None) => self.import_location == other.import_location
    _ => false
  }
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

///|
/// The text of an Ion 1.0 system symbol ID (1..9), or `None` outside that
/// range. The system symbol table is the initial symbol table shared by every
/// Ion stream; IDs `0` and `10` and above have no text without a local symbol
/// table.
pub fn system_symbol_text(sid : Int) -> String? {
  match sid {
    1 => Some("$ion")
    2 => Some("$ion_1_0")
    3 => Some("$ion_symbol_table")
    4 => Some("name")
    5 => Some("version")
    6 => Some("imports")
    7 => Some("symbols")
    8 => Some("max_id")
    9 => Some("$ion_shared_symbol_table")
    _ => None
  }
}
