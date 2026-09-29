// Shared symbol tables and the catalog that holds them.
//
// A local symbol table can import shared symbol tables by name and version.
// A reader finds them in a catalog, which the caller supplies: shared tables
// live outside the stream, for example in a file of
// `$ion_shared_symbol_table::{...}` structs.

///|
/// A shared symbol table: a name, a version, and its symbols in ID order.
/// `None` is a slot with unknown text.
struct SharedSymbolTable {
  name : String
  version : Int
  symbols : Array[String?]
}

///|
/// A shared symbol table named `name`, at `version`, declaring `symbols`.
pub fn SharedSymbolTable::new(
  name : String,
  version : Int,
  symbols : Array[String?],
) -> SharedSymbolTable {
  { name, version, symbols, }
}

///|
/// The table's name.
pub fn SharedSymbolTable::name(self : SharedSymbolTable) -> String {
  self.name
}

///|
/// The table's version.
pub fn SharedSymbolTable::version(self : SharedSymbolTable) -> Int {
  self.version
}

///|
/// The table's symbols in ID order; `None` is a slot with unknown text.
pub fn SharedSymbolTable::symbols(self : SharedSymbolTable) -> Array[String?] {
  self.symbols
}

///|
/// The shared table a value declares: a struct annotated
/// `$ion_shared_symbol_table` with a non-empty string `name`, an optional
/// positive `version` (1 when missing), and a `symbols` list, where an element
/// that is not a string is a slot with unknown text. `None` means the value is
/// not a shared table. A shared table that imports others raises
/// `IonError::Unsupported`.
pub fn SharedSymbolTable::from_value(
  value : IonValue,
) -> SharedSymbolTable? raise IonError {
  let annotated = match value.annotations() {
    [first, ..] => first.text() == Some("$ion_shared_symbol_table")
    [] => false
  }
  let fields = match value.kind() {
    Struct(fields) if annotated => fields
    _ => return None
  }
  let mut name : String? = None
  let mut version = 1
  let symbols : Array[String?] = []
  for field in fields {
    match (field.name().text(), field.value().kind()) {
      (Some("name"), String(text)) if text != "" => name = Some(text)
      (Some("version"), Int(n)) if n >= 1N && n <= 0x7FFF_FFFFN =>
        version = n.to_int()
      (Some("symbols"), List(items)) =>
        for item in items {
          symbols.push(
            match item.kind() {
              String(text) => Some(text)
              _ => None
            },
          )
        }
      (Some("imports"), List(items)) if !items.is_empty() =>
        raise Unsupported(
          "a shared symbol table that imports other tables is not supported",
        )
      _ => ()
    }
  }
  match name {
    Some(name) => Some({ name, version, symbols, })
    None => raise DataModel("a shared symbol table must have a name")
  }
}

///|
/// A catalog of shared symbol tables, by name and version.
struct Catalog {
  tables : Map[String, Array[SharedSymbolTable]]
}

///|
/// An empty catalog.
pub fn Catalog::new() -> Catalog {
  { tables: Map([]), }
}

///|
/// A catalog of the shared tables among `values`; other values are ignored.
pub fn Catalog::load(values : Array[IonValue]) -> Catalog raise IonError {
  let catalog = Catalog::new()
  for value in values {
    match SharedSymbolTable::from_value(value) {
      Some(table) => catalog.add(table)
      None => ()
    }
  }
  catalog
}

///|
/// Add a shared table, replacing one with the same name and version.
pub fn Catalog::add(self : Catalog, table : SharedSymbolTable) -> Unit {
  let versions = self.tables.get(table.name).unwrap_or([])
  let kept = versions.filter(other => other.version != table.version)
  kept.push(table)
  self.tables[table.name] = kept
}

///|
/// The shared table with exactly this name and version.
pub fn Catalog::find(
  self : Catalog,
  name : String,
  version : Int,
) -> SharedSymbolTable? {
  self.tables
  .get(name)
  .unwrap_or([])
  .iter()
  .find_first(table => table.version == version)
}

///|
/// The shared table with this name and the highest version.
pub fn Catalog::latest(self : Catalog, name : String) -> SharedSymbolTable? {
  let mut best : SharedSymbolTable? = None
  for table in self.tables.get(name).unwrap_or([]) {
    match best {
      Some(current) if current.version >= table.version => ()
      _ => best = Some(table)
    }
  }
  best
}

///|
/// Whether the catalog holds no tables.
pub fn Catalog::is_empty(self : Catalog) -> Bool {
  self.tables.is_empty()
}
