// The symbol table of an Ion stream, shared by the text and binary codecs.
//
// The Ion 1.0 system symbols occupy symbol IDs 1 through 9 in every stream. A
// local symbol table follows them with the symbols of the shared tables it
// imports and then the symbols it declares; a version marker resets the table
// to the system symbols. Reading resolves an ID to text (or leaves it
// text-less); writing assigns an ID to each text a value uses, reusing a
// system ID when the text matches one.
//
// Imports are resolved against a catalog of shared symbol tables, which may
// be empty. An import the catalog cannot satisfy exactly still reserves its
// `max_id` IDs, using the latest version the catalog has, if any, for their
// text. The table keeps each import as a count and the texts it knows, since
// `max_id` can be in the millions.

///|
/// The symbols in effect at a point in an Ion stream: the system symbols, the
/// symbols of the shared tables the local symbol table imports, and the local
/// symbols.
struct SymbolTable {
  /// The shared tables imports resolve against.
  catalog : Catalog
  /// The imports, in ID order after the system symbols.
  mut imports : Array[Import]
  /// The number of IDs the imports take.
  mut imported : Int
  /// The local symbols in ID order after the imported IDs. `None` is a slot
  /// with unknown text.
  mut locals : Array[String?]
}

///|
/// The IDs one import takes: `count` of them, of which the first `known`
/// hold the shared table's texts (or gaps), and the rest have unknown text.
priv struct Import {
  name : String
  version : Int
  count : Int
  known : Array[String?]
}

///|
/// A table with only the Ion 1.0 system symbols, resolving imports against
/// `catalog` (empty by default).
pub fn SymbolTable::system(catalog? : Catalog = Catalog::new()) -> SymbolTable {
  { catalog, imports: [], imported: 0, locals: [], }
}

///|
/// The local symbols in ID order, after the imported IDs. `None` is a slot
/// with unknown text.
pub fn SymbolTable::locals(self : SymbolTable) -> Array[String?] {
  self.locals
}

///|
/// Whether the table defines no symbols beyond the system symbols.
pub fn SymbolTable::is_empty(self : SymbolTable) -> Bool {
  self.imported == 0 && self.locals.is_empty()
}

///|
/// The highest symbol ID the table defines.
pub fn SymbolTable::max_id(self : SymbolTable) -> Int {
  9 + self.imported + self.locals.length()
}

///|
/// Drop the imported and local symbols, as a version marker does.
pub fn SymbolTable::reset(self : SymbolTable) -> Unit {
  self.imports = []
  self.imported = 0
  self.locals = []
}

///|
/// The text of a symbol ID: a system symbol, an imported or local symbol, or
/// nothing for an ID with unknown text or beyond the table.
pub fn SymbolTable::text(self : SymbolTable, sid : Int) -> String? {
  match system_symbol_text(sid) {
    Some(text) => return Some(text)
    None => ()
  }
  let mut index = sid - 10
  if index < 0 {
    return None
  }
  for import_ in self.imports {
    if index < import_.count {
      return if index < import_.known.length() {
        import_.known[index]
      } else {
        None
      }
    }
    index -= import_.count
  }
  if index < self.locals.length() {
    self.locals[index]
  } else {
    None
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
/// The token for a symbol ID that a reader meets, as `token` gives it. An ID
/// beyond the table is an error: the Ion specification requires a reader to
/// reject it rather than keep a symbol no table defines.
pub fn SymbolTable::lookup(
  self : SymbolTable,
  sid : Int,
) -> SymbolToken raise IonError {
  if sid < 0 || sid > self.max_id() {
    raise Syntax(
      "symbol ID $\{sid} is beyond the symbol table, whose largest ID is \{self.max_id()}",
    )
  }
  self.token(sid)
}

///|
/// Reserve `count` IDs from 10 with unknown text, ahead of the local symbols,
/// as an import of a shared table missing from the catalog does. A writer
/// reserves the IDs of symbols whose text it does not know, so the symbols it
/// declares cannot take those IDs.
pub fn SymbolTable::reserve(self : SymbolTable, count : Int) -> Unit {
  self.imports = [
    { name: unknown_symbols_table, version: 1, count, known: [], },
  ]
  self.imported = count
}

///|
/// The name of the shared symbol table that `to_local_symbol_table` imports to
/// reserve IDs with unknown text. No catalog holds it, so a reader reserves the
/// IDs and leaves their text unknown.
let unknown_symbols_table : String = "moonrockz.ion.unknown_symbols"

///|
/// The local symbol table that sets up this table in a stream, or `None` when
/// the system symbols suffice: its imports, each with the `max_id` it takes,
/// and the local symbols.
pub fn SymbolTable::to_local_symbol_table(self : SymbolTable) -> IonValue? {
  if self.is_empty() {
    return None
  }
  let fields : Array[Field] = []
  if !self.imports.is_empty() {
    let imports = self.imports.map(import_ => {
      IonValue::from_fields([
        Field::new("name", IonValue::string(import_.name)),
        Field::new("version", IonValue::int(import_.version)),
        Field::new("max_id", IonValue::int(import_.count)),
      ])
    })
    fields.push(Field::new("imports", IonValue::list(imports)))
  }
  if !self.locals.is_empty() {
    let symbols = self.locals.map(text => {
      match text {
        Some(text) => IonValue::string(text)
        None => IonValue::untyped_null()
      }
    })
    fields.push(Field::new("symbols", IonValue::list(symbols)))
  }
  Some(
    IonValue::from_fields(fields).with_annotations([
      SymbolToken::new("$ion_symbol_table"),
    ]),
  )
}

///|
/// The highest ID of a symbol known only by its ID in `values`, in annotations,
/// field names, and symbol values at any depth, or 0 when there is none.
pub fn highest_symbol_id(values : Array[IonValue]) -> Int {
  let mut highest = 0
  for value in values {
    highest = @cmp.maximum(highest, value_highest_symbol_id(value))
  }
  highest
}

///|
/// `highest_symbol_id` for one value.
fn value_highest_symbol_id(value : IonValue) -> Int {
  let mut highest = 0
  for annotation in value.annotations() {
    highest = @cmp.maximum(highest, token_symbol_id(annotation))
  }
  match value.kind() {
    Symbol(token) => highest = @cmp.maximum(highest, token_symbol_id(token))
    List(items) | Sexp(items) =>
      for item in items {
        highest = @cmp.maximum(highest, value_highest_symbol_id(item))
      }
    Struct(fields) =>
      for field in fields {
        highest = @cmp.maximum(highest, token_symbol_id(field.name()))
        highest = @cmp.maximum(highest, value_highest_symbol_id(field.value()))
      }
    _ => ()
  }
  highest
}

///|
/// The ID of a token known only by its ID, or 0.
fn token_symbol_id(token : SymbolToken) -> Int {
  match (token.text(), token.sid()) {
    (None, Some(sid)) => sid
    _ => 0
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
  let mut first = 10
  for import_ in self.imports {
    for index in 0..<import_.known.length() {
      if import_.known[index] == Some(text) {
        return Some(first + index)
      }
    }
    first += import_.count
  }
  for index in 0..<self.locals.length() {
    if self.locals[index] == Some(text) {
      return Some(index + 10 + self.imported)
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
/// symbol tables, which resolve against the catalog as `resolve_import`
/// describes.
pub fn SymbolTable::apply_local_symbol_table(
  self : SymbolTable,
  value : IonValue,
) -> Bool raise IonError {
  if !is_local_symbol_table_annotation(value) {
    return false
  }
  let fields = match value.kind() {
    Struct(fields) => fields
    // A null struct declares an empty table.
    Null(Struct) => []
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
  let declared : Array[String?] = []
  if symbols.map(symbols => symbols.kind()) is Some(List(items)) {
    for item in items {
      declared.push(
        match item.kind() {
          String(text) => Some(text)
          _ => None
        },
      )
    }
  }
  match imports.map(imports => imports.kind()) {
    Some(Symbol(token)) if token.text() == Some("$ion_symbol_table") => {
      self.locals = self.locals + declared
      return true
    }
    Some(List(items)) => {
      let imports : Array[Import] = []
      for item in items {
        match resolve_import(item, self.catalog) {
          Some(import_) => imports.push(import_)
          None => ()
        }
      }
      self.imports = imports
      self.imported = imports.fold(init=0, (total, import_) => {
        total + import_.count
      })
    }
    _ => {
      self.imports = []
      self.imported = 0
    }
  }
  self.locals = declared
  true
}

///|
/// Resolve one import against `catalog`:
///
/// - an import that is not a struct, or whose `name` is not a non-empty
///   string or is the system table `$ion`, is ignored;
/// - a `version` that is not a positive int is 1;
/// - a table of exactly that name and version supplies the symbols, as many
///   as a valid `max_id` says (padded with unknown text, or truncated), or all
///   of them;
/// - otherwise a valid `max_id` is required: the IDs take the latest version
///   of the table, when the catalog has one, padded or truncated to `max_id`,
///   or unknown text when it has none.
fn resolve_import(
  import_ : IonValue,
  catalog : Catalog,
) -> Import? raise IonError {
  let fields = match import_.kind() {
    Struct(fields) => fields
    _ => return None
  }
  let mut name : String? = None
  let mut version = 1
  let mut max_id : Int? = None
  let seen : Array[String] = []
  for field in fields {
    match field.name().text() {
      Some("name" | "version" | "max_id" as key) => {
        if seen.contains(key) {
          raise DataModel("an import has two \{key} fields")
        }
        seen.push(key)
        match (key, field.value().kind()) {
          ("name", String(text)) => name = Some(text)
          ("version", Int(n)) if n >= 1N && n <= 0x7FFF_FFFFN =>
            version = n.to_int()
          ("max_id", Int(n)) if n >= 0N && n <= 0x7FFF_FFFFN =>
            max_id = Some(n.to_int())
          _ => ()
        }
      }
      _ => ()
    }
  }
  let name = match name {
    None | Some("") | Some("$ion") => return None
    Some(name) => name
  }
  let (symbols, count) = match catalog.find(name, version) {
    Some(table) => (table.symbols(), max_id.unwrap_or(table.symbols().length()))
    None =>
      match max_id {
        Some(count) =>
          (
            catalog.latest(name).map(table => table.symbols()).unwrap_or([]),
            count,
          )
        None =>
          raise DataModel(
            "no exact match for the shared symbol table \{name} version \{version}, and the import declares no max_id",
          )
      }
  }
  let known = symbols[:@cmp.minimum(count, symbols.length())].to_owned()
  Some({ name, version, count, known, })
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
/// `value` with text for every symbol ID the table defines, in its
/// annotations, field names, and symbol values at any depth. A symbol ID the
/// table leaves without text keeps only its ID, and an ID beyond the table
/// raises, as `lookup` does.
pub fn SymbolTable::resolve(
  self : SymbolTable,
  value : IonValue,
) -> IonValue raise IonError {
  if !has_symbol_ids(value) {
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
) -> SymbolToken raise IonError {
  match (token.text(), token.sid()) {
    (None, Some(sid)) if sid > 0 => self.lookup(sid)
    _ => token
  }
}

///|
/// Whether a value holds a symbol known only by a nonzero ID, in an
/// annotation, a field name, or a symbol value at any depth.
fn has_symbol_ids(value : IonValue) -> Bool {
  for annotation in value.annotations() {
    if is_symbol_id(annotation) {
      return true
    }
  }
  match value.kind() {
    Symbol(token) => is_symbol_id(token)
    List(items) | Sexp(items) => {
      for item in items {
        if has_symbol_ids(item) {
          return true
        }
      }
      false
    }
    Struct(fields) => {
      for field in fields {
        if is_symbol_id(field.name()) || has_symbol_ids(field.value()) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
/// Whether a token is known only by a nonzero ID.
fn is_symbol_id(token : SymbolToken) -> Bool {
  token.text() is None && token.sid() is Some(sid) && sid > 0
}
