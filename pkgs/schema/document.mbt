// The top level of an Ion Schema 2.0 document.
//
// A schema document is a sequence of Ion values: the version marker
// `$ion_schema_2_0`, an optional `schema_header::{...}`, the
// `type::{...}` definitions, and an optional `schema_footer::{...}`, after
// which nothing counts. Any other top-level value is open content, which the
// loader ignores, unless it is annotated with a reserved symbol.
//
// The reserved symbols are those that match `$ion_schema(_.*)?` and those in
// lower snake case, such as `type` or `foo_bar`. A header, a type definition,
// and a footer may have fields whose names are not reserved; they are user
// content. The header's `user_reserved_fields` can also declare reserved
// symbols, other than ISL keywords, as user fields.
//
// A document with no version marker is ISL 1.0 by the specification. This
// loader reads it as ISL 2.0 instead, so that a schema of type definitions
// alone loads.

///|
/// Load a schema from a parsed schema document. A construct that ISL 2.0 does
/// not allow raises `IonError::DataModel`, and one that this implementation
/// does not implement raises `IonError::Unsupported`.
///
/// `resolver` returns the parsed values of the schema document that an
/// import names by its `id`, such as a file under a base directory. Without
/// it, a schema with imports raises `IonError::Unsupported`. An imported type
/// is in `types()` as `<id>#<name>`.
pub fn Schema::load(
  values : Array[@ion.IonValue],
  resolver? : (String) -> Array[@ion.IonValue] raise @ion.IonError,
) -> Schema raise @ion.IonError {
  let loader : Loader = { resolver, documents: Map([]), types: [], }
  let _ = loader.load_document(None, values)
  Schema::from_types(loader.types)
}

///|
/// The parts of a schema document.
priv struct Parsed {
  imports : Array[@ion.IonValue]
  definitions : Array[Array[@ion.Field]]
  user_fields : UserFields
}

///|
/// Split a schema document into its imports, its type definitions, and the
/// user fields its header declares, checking the order and form of its
/// top-level values.
fn parse_document(values : Array[@ion.IonValue]) -> Parsed raise @ion.IonError {
  let definitions : Array[Array[@ion.Field]] = []
  let mut imports : Array[@ion.IonValue] = []
  let mut user_fields = UserFields::none()
  let mut version_seen = false
  let mut header_seen = false
  for value in values {
    if version_marker(value) is Some(version) {
      if value.has_annotations() {
        raise @ion.IonError::DataModel(
          "a version marker must not have annotations",
        )
      }
      if version_seen || header_seen || !definitions.is_empty() {
        raise @ion.IonError::DataModel(
          "a schema has one version marker, before its header and types",
        )
      }
      match version {
        "$ion_schema_2_0" => version_seen = true
        "$ion_schema_1_0" =>
          // ISL 1.0 gives the same names other meanings, such as nulls in
          // core types, so it must not load as ISL 2.0.
          raise @ion.IonError::Unsupported("Ion Schema 1.0 is not supported")
        _ =>
          raise @ion.IonError::DataModel(
            "unknown Ion Schema version: " + version,
          )
      }
      continue
    }
    let annotations = value.annotations().map(token => token.text())
    let keyword = annotations
      .iter()
      .find_first(text => {
        text == Some("type") ||
        text == Some("schema_header") ||
        text == Some("schema_footer")
      })
    match keyword {
      Some(Some(keyword)) => {
        if annotations.length() != 1 {
          raise @ion.IonError::DataModel(
            "a '\{keyword}' must have no other annotation",
          )
        }
        let fields = match value.kind() {
          @ion.IonValueKind::Struct(fields) => fields
          _ =>
            raise @ion.IonError::DataModel(
              "a '\{keyword}' must be a non-null struct",
            )
        }
        match keyword {
          "schema_header" => {
            if header_seen || !definitions.is_empty() {
              raise @ion.IonError::DataModel(
                "a schema has one header, before its types",
              )
            }
            header_seen = true
            let (declared, header_imports) = load_header(fields)
            user_fields = declared
            imports = header_imports
          }
          "type" => definitions.push(fields)
          _ => {
            check_user_fields(fields, user_fields.footer, "schema footer")
            break
          }
        }
      }
      _ =>
        // Open content.
        for text in annotations {
          if text is Some(text) && is_reserved(text) {
            raise @ion.IonError::DataModel(
              "open content must not be annotated with the reserved symbol '\{text}'",
            )
          }
        }
    }
  }
  { imports, definitions, user_fields, }
}

///|
/// Schema documents being loaded, and the types loaded so far.
priv struct Loader {
  resolver : ((String) -> Array[@ion.IonValue] raise @ion.IonError)?
  /// The names of the types each document defines, by the document's id,
  /// known before its imports load, so that documents can import each other.
  documents : Map[String, Array[String]]
  types : Array[TypeDefinition]
}

///|
/// The name a type has in the loaded schema: its own name for the root
/// document, and `<id>#<name>` for an imported one.
fn type_key(id : String?, name : String) -> String {
  match id {
    Some(id) => "\{id}#\{name}"
    None => name
  }
}

///|
/// Load a schema document, `id` for an imported one, and return the names of
/// the types it defines.
fn Loader::load_document(
  self : Loader,
  id : String?,
  values : Array[@ion.IonValue],
) -> Array[String] raise @ion.IonError {
  let parsed = parse_document(values)
  let names : Array[String] = []
  for fields in parsed.definitions {
    let name = type_name(fields)
    if names.contains(name) {
      raise @ion.IonError::DataModel("the type name '\{name}' is defined twice")
    }
    names.push(name)
  }
  if id is Some(id) {
    self.documents[id] = names
  }
  let scope : Map[String, String] = Map([])
  for name in names {
    scope[name] = type_key(id, name)
  }
  let ctx : Context = {
    loader: self,
    id,
    scope,
    user_fields: parsed.user_fields.types,
  }
  for import_ in parsed.imports {
    ctx.header_import(import_)
  }
  for fields in parsed.definitions {
    let definition = load_type_definition(fields, ctx)
    self.types.push({
      name: type_key(id, definition.name),
      constraints: definition.constraints,
    })
  }
  names
}

///|
/// The names of the types the document `id` defines, loading it first if
/// needed. `importer` is the id of the document that imports it.
fn Loader::names_of(
  self : Loader,
  id : String,
  importer : String?,
) -> Array[String] raise @ion.IonError {
  if importer == Some(id) {
    raise @ion.IonError::DataModel("the schema '\{id}' imports itself")
  }
  if self.documents.get(id) is Some(names) {
    return names
  }
  let values = match self.resolver {
    Some(resolver) => resolver(id)
    None =>
      raise @ion.IonError::Unsupported(
        "the schema imports '\{id}', but no resolver was given to load it",
      )
  }
  self.load_document(Some(id), values)
}

///|
/// What a type definition in one schema document can see: the types it
/// defines and imports, by the names they have there, and the reserved
/// symbols the header declares as user fields of a type.
priv struct Context {
  loader : Loader
  id : String?
  scope : Map[String, String]
  user_fields : Array[String]
}

///|
/// The reference to the type named `name` in the document's scope.
fn Context::resolve(
  self : Context,
  name : String,
) -> Constraint raise @ion.IonError {
  match self.scope.get(name) {
    Some(key) => TypeRef(key)
    None =>
      raise @ion.IonError::DataModel(
        "no type named '\{name}' is defined or imported",
      )
  }
}

///|
/// Bring an imported type into the document's scope as `name`.
fn Context::add(
  self : Context,
  name : String,
  key : String,
) -> Unit raise @ion.IonError {
  match self.scope.get(name) {
    Some(existing) if existing != key =>
      raise @ion.IonError::DataModel(
        "the type name '\{name}' is defined or imported twice",
      )
    _ => self.scope[name] = key
  }
}

///|
/// Apply a header import: all the types of a schema, or one type, by its own
/// name or the name after `as`.
fn Context::header_import(
  self : Context,
  import_ : @ion.IonValue,
) -> Unit raise @ion.IonError {
  let fields = match import_.kind() {
    @ion.IonValueKind::Struct(fields) if !import_.has_annotations() => fields
    _ =>
      raise @ion.IonError::DataModel(
        "an import must be a non-null struct without annotations",
      )
  }
  let (id, name, rename) = import_fields(fields, ["id", "type", "as"])
  let names = self.loader.names_of(id, self.id)
  match name {
    None => {
      if rename is Some(_) {
        raise @ion.IonError::DataModel("an import with 'as' needs a 'type'")
      }
      for name in names {
        self.add(name, type_key(Some(id), name))
      }
    }
    Some(name) => {
      if !names.contains(name) {
        raise @ion.IonError::DataModel(
          "the schema '\{id}' has no type '\{name}'",
        )
      }
      self.add(rename.unwrap_or(name), type_key(Some(id), name))
    }
  }
}

///|
/// The reference an inline import `{ id: ..., type: ... }` makes. It does not
/// change the document's scope.
fn Context::inline_import(
  self : Context,
  fields : Array[@ion.Field],
) -> Constraint raise @ion.IonError {
  let (id, name, _) = import_fields(fields, ["id", "type"])
  guard name is Some(name) else {
    raise @ion.IonError::DataModel("an inline import needs a 'type'")
  }
  if !self.loader.names_of(id, self.id).contains(name) {
    raise @ion.IonError::DataModel("the schema '\{id}' has no type '\{name}'")
  }
  TypeRef(type_key(Some(id), name))
}

///|
/// The `id` string, and the `type` and `as` symbols, of an import. Each field
/// appears at most once, without annotations, and only the `allowed` ones.
fn import_fields(
  fields : Array[@ion.Field],
  allowed : Array[String],
) -> (String, String?, String?) raise @ion.IonError {
  let mut id : String? = None
  let mut name : String? = None
  let mut rename : String? = None
  for field in fields {
    let key = field.name().text().unwrap_or("")
    let value = field.value()
    if !allowed.contains(key) || value.has_annotations() {
      raise @ion.IonError::DataModel(
        "an import takes only \{allowed.join(", ")}, without annotations",
      )
    }
    let twice = @ion.IonError::DataModel("an import has '\{key}' twice")
    match (key, value.kind()) {
      ("id", @ion.IonValueKind::String(text)) =>
        if id is None {
          id = Some(text)
        } else {
          raise twice
        }
      ("id", @ion.IonValueKind::Symbol(token)) =>
        if id is None {
          id = Some(token.require_text())
        } else {
          raise twice
        }
      ("type", @ion.IonValueKind::Symbol(token)) =>
        if name is None {
          name = Some(token.require_text())
        } else {
          raise twice
        }
      ("as", @ion.IonValueKind::Symbol(token)) =>
        if rename is None {
          rename = Some(token.require_text())
        } else {
          raise twice
        }
      _ =>
        raise @ion.IonError::DataModel(
          "an import's id is a string or symbol, and its type and as are symbols",
        )
    }
  }
  match id {
    Some(id) => (id, name, rename)
    None => raise @ion.IonError::DataModel("an import needs an 'id'")
  }
}

///|
/// The name of a type definition: its one `name` field, a non-null symbol
/// without annotations.
fn type_name(fields : Array[@ion.Field]) -> String raise @ion.IonError {
  let names = fields.filter(field => field.name().text() == Some("name"))
  match names {
    [field] =>
      match field.value().kind() {
        @ion.IonValueKind::Symbol(token) if !field.value().has_annotations() =>
          token.require_text()
        _ =>
          raise @ion.IonError::DataModel(
            "a type's name must be a non-null symbol without annotations",
          )
      }
    _ => raise @ion.IonError::DataModel("a type definition needs one 'name'")
  }
}

///|
/// The text of a version marker: a symbol that matches `$ion_schema_\d.*`,
/// with or without annotations.
fn version_marker(value : @ion.IonValue) -> String? {
  match value.kind() {
    @ion.IonValueKind::Symbol(token) =>
      match token.text() {
        Some(text) if text.has_prefix("$ion_schema_") &&
          text.length() > 12 &&
          text[12] >= '0' &&
          text[12] <= '9' => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
/// Whether a symbol is reserved: `$ion_schema`, `$ion_schema_...`, or lower
/// snake case (`[a-z][a-z0-9]*(_[a-z0-9]+)*`).
fn is_reserved(text : String) -> Bool {
  if text == "$ion_schema" || text.has_prefix("$ion_schema_") {
    return true
  }
  let chars : Array[Char] = text.iter().collect()
  if chars.is_empty() || !(chars[0] >= 'a' && chars[0] <= 'z') {
    return false
  }
  let mut previous = chars[0]
  for c in chars[1:] {
    let lower_or_digit = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
    if !(lower_or_digit || (c == '_' && previous != '_')) {
      return false
    }
    previous = c
  }
  previous != '_'
}

///|
/// The keywords of ISL 2.0, which cannot be declared as user fields.
let isl_keywords : Array[String] = [
  "all_of", "annotations", "any_of", "as", "byte_length", "codepoint_length", "container_length",
  "contains", "element", "exponent", "field_names", "fields", "id", "ieee754_float",
  "imports", "name", "not", "occurs", "one_of", "ordered_elements", "precision",
  "regex", "schema_footer", "schema_header", "timestamp_offset", "timestamp_precision",
  "type", "user_reserved_fields", "utf8_byte_length", "valid_values",
]

///|
/// Whether a field is user content, given the reserved symbols declared as
/// user fields where it appears: its name is not reserved, or is declared.
fn is_user_field(name : String, declared : Array[String]) -> Bool {
  !is_reserved(name) || declared.contains(name)
}

///|
/// The reserved symbols the schema header declares as user fields, for the
/// header, for type definitions, and for the footer.
priv struct UserFields {
  header : Array[String]
  types : Array[String]
  footer : Array[String]
}

///|
fn UserFields::none() -> UserFields {
  { header: [], types: [], footer: [], }
}

///|
/// Load the schema header: the user fields its `user_reserved_fields`
/// declares, and its imports. Its other fields must be user content.
fn load_header(
  fields : Array[@ion.Field],
) -> (UserFields, Array[@ion.IonValue]) raise @ion.IonError {
  let user_fields = match field_value(fields, "user_reserved_fields") {
    Some(declaration) => load_user_reserved_fields(declaration)
    None => UserFields::none()
  }
  for key in ["user_reserved_fields", "imports"] {
    if fields.filter(field => field.name().text() == Some(key)).length() > 1 {
      raise @ion.IonError::DataModel("a schema header has at most one '\{key}'")
    }
  }
  let imports = match field_value(fields, "imports") {
    None => []
    Some(value) =>
      match value.kind() {
        @ion.IonValueKind::List(items) if !value.has_annotations() => items
        _ =>
          raise @ion.IonError::DataModel(
            "imports must be a non-null list without annotations",
          )
      }
  }
  check_user_fields(
    fields.filter(field => {
      field.name().text() != Some("user_reserved_fields") &&
      field.name().text() != Some("imports")
    }),
    user_fields.header,
    "schema header",
  )
  (user_fields, imports)
}

///|
/// Check that every field is user content.
fn check_user_fields(
  fields : Array[@ion.Field],
  declared : Array[String],
  context : String,
) -> Unit raise @ion.IonError {
  for field in fields {
    let name = field.name().require_text()
    if !is_user_field(name, declared) {
      raise @ion.IonError::DataModel(
        "the reserved symbol '\{name}' is not a field of a \{context}",
      )
    }
  }
}

///|
/// Load a `user_reserved_fields` struct: at most one each of `schema_header`,
/// `type`, and `schema_footer`, each a list of symbols that are not ISL
/// keywords.
fn load_user_reserved_fields(
  value : @ion.IonValue,
) -> UserFields raise @ion.IonError {
  let fields = match value.kind() {
    @ion.IonValueKind::Struct(fields) if !value.has_annotations() => fields
    _ =>
      raise @ion.IonError::DataModel(
        "user_reserved_fields must be a non-null struct without annotations",
      )
  }
  let declared : Map[String, Array[String]] = Map([])
  for field in fields {
    let place = field.name().require_text()
    if !["schema_header", "type", "schema_footer"].contains(place) ||
      declared.contains(place) {
      raise @ion.IonError::DataModel(
        "user_reserved_fields takes at most one each of schema_header, type, and schema_footer",
      )
    }
    let items = match field.value().kind() {
      @ion.IonValueKind::List(items) if !field.value().has_annotations() =>
        items
      _ =>
        raise @ion.IonError::DataModel(
          "user_reserved_fields.\{place} must be a non-null list without annotations",
        )
    }
    let names : Array[String] = []
    for item in items {
      match item.kind() {
        @ion.IonValueKind::Symbol(token) if !item.has_annotations() => {
          let name = token.require_text()
          if isl_keywords.contains(name) {
            raise @ion.IonError::DataModel(
              "the ISL keyword '\{name}' cannot be a user field",
            )
          }
          names.push(name)
        }
        _ =>
          raise @ion.IonError::DataModel(
            "a user field must be a non-null symbol without annotations",
          )
      }
    }
    declared[place] = names
  }
  {
    header: declared.get("schema_header").unwrap_or([]),
    types: declared.get("type").unwrap_or([]),
    footer: declared.get("schema_footer").unwrap_or([]),
  }
}
