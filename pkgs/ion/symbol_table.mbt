// The symbol table of an Ion stream, shared by the text and binary codecs.
//
// The Ion 1.0 system symbols occupy symbol IDs 1 through 9 in every stream. A
// local symbol table appends the symbols it declares at ID 10 and up; a
// version marker resets the table to the system symbols. Reading resolves an
// ID to text (or leaves it text-less); writing assigns an ID to each text a
// value uses, reusing a system ID when the text matches one.

///|
/// The symbols in effect at a point in an Ion stream: the system symbols and
/// the local symbols that follow them.
struct SymbolTable {
  /// The local symbols in ID order from 10. `None` is a slot with unknown
  /// text.
  mut locals : Array[String?]
}

///|
/// A table with only the Ion 1.0 system symbols.
pub fn SymbolTable::system() -> SymbolTable {
  { locals: [], }
}

///|
/// The local symbols in ID order, starting at 10. `None` is a slot with
/// unknown text.
pub fn SymbolTable::locals(self : SymbolTable) -> Array[String?] {
  self.locals
}

///|
/// Whether the table declares no local symbols.
pub fn SymbolTable::is_empty(self : SymbolTable) -> Bool {
  self.locals.is_empty()
}

///|
/// The highest symbol ID the table defines.
pub fn SymbolTable::max_id(self : SymbolTable) -> Int {
  9 + self.locals.length()
}

///|
/// Drop the local symbols, as a version marker does.
pub fn SymbolTable::reset(self : SymbolTable) -> Unit {
  self.locals = []
}

///|
/// The text of a symbol ID: a system symbol, a local symbol, or nothing.
pub fn SymbolTable::text(self : SymbolTable, sid : Int) -> String? {
  match system_symbol_text(sid) {
    Some(text) => Some(text)
    None =>
      if sid >= 10 && sid - 10 < self.locals.length() {
        self.locals[sid - 10]
      } else {
        None
      }
  }
}

///|
/// The token for a symbol ID: its text when the table defines it, and an
/// ID-only token otherwise.
pub fn SymbolTable::token(self : SymbolTable, sid : Int) -> SymbolToken {
  match self.text(sid) {
    Some(text) => SymbolToken::new(text)
    None => SymbolToken::from_sid(sid)
  }
}

///|
/// The symbol ID this table already uses for `text`.
pub fn SymbolTable::find(self : SymbolTable, text : String) -> Int? {
  for sid in 1..<=9 {
    if system_symbol_text(sid) == Some(text) {
      return Some(sid)
    }
  }
  for index in 0..<self.locals.length() {
    if self.locals[index] == Some(text) {
      return Some(index + 10)
    }
  }
  None
}

///|
/// The symbol ID for `text`, adding it to the local symbols when the table
/// does not already define it.
pub fn SymbolTable::intern(self : SymbolTable, text : String) -> Int {
  match self.find(text) {
    Some(sid) => sid
    None => {
      self.locals.push(Some(text))
      self.max_id()
    }
  }
}

///|
/// Apply `value` when it is a local symbol table: a struct whose first
/// annotation is `$ion_symbol_table`. Returns whether it was one; any other
/// value leaves the table unchanged.
///
/// The `symbols` field lists the new local symbols; an element that is not a
/// string declares a slot with unknown text, and a `symbols` field that is not
/// a list declares none. `imports: $ion_symbol_table` appends the symbols to
/// the current ones instead of replacing them. A list of imports names shared
/// symbol tables, which are not implemented, so it raises
/// `IonError::Unsupported` rather than resolve IDs to the wrong text.
pub fn SymbolTable::apply_local_symbol_table(
  self : SymbolTable,
  value : IonValue,
) -> Bool raise IonError {
  let fields = match value.kind() {
    Struct(fields) if is_local_symbol_table_annotation(value) => fields
    _ => return false
  }
  let mut imports : IonValue? = None
  let mut symbols : IonValue? = None
  for field in fields {
    match field.name().text() {
      Some("imports") => {
        if imports is Some(_) {
          raise DataModel("a local symbol table has two imports fields")
        }
        imports = Some(field.value())
      }
      Some("symbols") => {
        if symbols is Some(_) {
          raise DataModel("a local symbol table has two symbols fields")
        }
        symbols = Some(field.value())
      }
      _ => ()
    }
  }
  let append = match imports {
    Some(imports) =>
      match imports.kind() {
        Symbol(token) => token.text() == Some("$ion_symbol_table")
        List(items) if !items.is_empty() =>
          raise Unsupported("shared symbol table imports are not supported")
        _ => false
      }
    None => false
  }
  let declared : Array[String?] = []
  match symbols {
    Some(symbols) =>
      match symbols.kind() {
        List(items) =>
          for item in items {
            declared.push(
              match item.kind() {
                String(text) => Some(text)
                _ => None
              },
            )
          }
        _ => ()
      }
    None => ()
  }
  if append {
    self.locals = self.locals + declared
  } else {
    self.locals = declared
  }
  true
}

///|
/// Whether a value's first annotation is `$ion_symbol_table`.
fn is_local_symbol_table_annotation(value : IonValue) -> Bool {
  match value.annotations() {
    [first, ..] => first.text() == Some("$ion_symbol_table")
    [] => false
  }
}

///|
/// `value` with text for every local symbol ID the table defines, in its
/// annotations, field names, and symbol values at any depth. A symbol ID the
/// table does not define keeps only its ID, and so does a system symbol ID, so
/// a reader gives system symbols their text as it reads them.
pub fn SymbolTable::resolve(self : SymbolTable, value : IonValue) -> IonValue {
  if self.locals.is_empty() {
    // Parsing already gave the system symbols their text.
    return value
  }
  let annotations = value.annotations().map(token => self.resolve_token(token))
  let resolved = match value.kind() {
    Symbol(token) => IonValue::symbol_token(self.resolve_token(token))
    List(items) => IonValue::list(items.map(item => self.resolve(item)))
    Sexp(items) => IonValue::sexp(items.map(item => self.resolve(item)))
    Struct(fields) =>
      IonValue::from_fields(
        fields.map(field => {
          Field::from_token(
            self.resolve_token(field.name()),
            self.resolve(field.value()),
          )
        }),
      )
    _ => value
  }
  resolved.with_annotations(annotations)
}

///|
/// A token with text when it has only an ID that the table defines.
fn SymbolTable::resolve_token(
  self : SymbolTable,
  token : SymbolToken,
) -> SymbolToken {
  match (token.text(), token.sid()) {
    (None, Some(sid)) => self.token(sid)
    _ => token
  }
}
