// The Ion symbol table used by the binary codec.
//
// The Ion 1.0 system symbols occupy symbol IDs 1 through 9 in every stream. A
// local symbol table appends the texts it declares at ID 10 and up. Reading
// resolves an ID to text (or leaves it text-less); writing assigns an ID to
// each text a value uses, reusing a system ID when the text matches one.

///|
/// The local symbols of an Ion binary stream, following the system table.
pub struct SymbolTable {
  mut locals : Array[String]
}

///|
/// A table with only the Ion 1.0 system symbols.
pub fn SymbolTable::system() -> SymbolTable {
  { locals: [], }
}

///|
/// The local symbol texts, in ID order (starting at 10).
pub fn SymbolTable::locals(self : SymbolTable) -> Array[String] {
  self.locals
}

///|
/// Whether the table declares no local symbols.
pub fn SymbolTable::is_empty(self : SymbolTable) -> Bool {
  self.locals.is_empty()
}

///|
/// Replace the local symbols, as a local symbol table declares them.
pub fn SymbolTable::set_locals(
  self : SymbolTable,
  locals : Array[String],
) -> Unit {
  self.locals = locals
}

///|
/// The text of a symbol ID: a system symbol, a local symbol, or nothing.
pub fn SymbolTable::text(self : SymbolTable, sid : Int) -> String? {
  match @ion.system_symbol_text(sid) {
    Some(text) => Some(text)
    None =>
      if sid >= 10 && sid - 10 < self.locals.length() {
        Some(self.locals[sid - 10])
      } else {
        None
      }
  }
}

///|
/// The token for a symbol ID: its text when the table defines it, and an
/// ID-only token otherwise.
pub fn SymbolTable::token(self : SymbolTable, sid : Int) -> @ion.SymbolToken {
  match self.text(sid) {
    Some(text) => @ion.SymbolToken::new(text)
    None => @ion.SymbolToken::from_sid(sid)
  }
}

///|
/// The symbol ID this table already uses for `text`.
pub fn SymbolTable::find(self : SymbolTable, text : String) -> Int? {
  for sid in 1..<=9 {
    if @ion.system_symbol_text(sid) == Some(text) {
      return Some(sid)
    }
  }
  for index in 0..<self.locals.length() {
    if self.locals[index] == text {
      return Some(index + 10)
    }
  }
  None
}

///|
/// The symbol ID for `text`, adding it to the local symbols when the system
/// table does not already define it.
pub fn SymbolTable::intern(self : SymbolTable, text : String) -> Int {
  match self.find(text) {
    Some(sid) => sid
    None => {
      self.locals.push(text)
      self.locals.length() + 9
    }
  }
}
