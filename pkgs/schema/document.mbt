// The top level of an Ion Schema document.
//
// A schema document is a sequence of Ion values: an optional version marker,
// an optional `schema_header::{...}`, the `type::{...}` definitions, and an
// optional `schema_footer::{...}`, after which nothing counts. The version
// marker `$ion_schema_2_0` makes the document ISL 2.0; `$ion_schema_1_0`, or
// no version marker, makes it ISL 1.0.
//
// In ISL 2.0, any other top-level value is open content, which the loader
// ignores, unless it is annotated with a reserved symbol. The reserved
// symbols are those that match `$ion_schema(_.*)?` and those in lower snake
// case, such as `type` or `foo_bar`. A header, a type definition, and a
// footer may have fields whose names are not reserved; they are user
// content. The header's `user_reserved_fields` can also declare reserved
// symbols, other than ISL keywords, as user fields.
//
// In ISL 1.0, there are no reserved symbols: any other top-level value, and
// any field that is not a keyword, is open content. A document has a header
// only if it has a footer.

///|
/// The version of the Ion Schema Language that a schema document uses.
priv enum IslVersion {
  Isl10
  Isl20
} derive(Eq)

///|
/// Load a schema from a parsed schema document, in ISL 1.0 or ISL 2.0 as its
/// version marker says. A construct that the version does not allow raises
/// `IonError::DataModel`, and one that this implementation does not
/// implement raises `IonError::Unsupported`.
///
/// The schema holds ISL 2.0 constraints: the loader translates each ISL 1.0
/// construct into the ISL 2.0 constraints with the same meaning. For
/// example, the ISL 1.0 `nullable::int` loads as `null.null`, `null.int`, or
/// `int`.
///
/// `resolver` returns the parsed values of the schema document that an
/// import names by its `id`, such as a file under a base directory. Without
/// it, a schema with imports raises `IonError::Unsupported`. An imported type
/// is in `types()` as `<id>#<name>`.
pub fn Schema::load(
  values : Array[@ion.IonValue],
  resolver? : (String) -> Array[@ion.IonValue] raise @ion.IonError,
) -> Schema raise @ion.IonError {
  let loader : Loader = {
    resolver,
    documents: Map([]),
    definitions: Map([]),
    types: [],
  }
  let _ = loader.load_document(None, values)
  Schema::from_types(loader.types)
}

///|
/// The parts of a schema document.
priv struct Parsed {
  version : IslVersion
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
  let mut version = Isl10
  let mut version_seen = false
  let mut header_seen = false
  let mut footer_seen = false
  for value in values {
    if version_marker(value) is Some(marker) {
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
      version = match marker {
        "$ion_schema_2_0" => Isl20
        "$ion_schema_1_0" => Isl10
        _ =>
          raise @ion.IonError::DataModel(
            "unknown Ion Schema version: " + marker,
          )
      }
      version_seen = true
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
            let (declared, header_imports) = load_header(fields, version)
            user_fields = declared
            imports = header_imports
          }
          "type" => definitions.push(fields)
          _ => {
            if version == Isl20 {
              check_user_fields(fields, user_fields.footer, "schema footer")
            }
            footer_seen = true
            break
          }
        }
      }
      _ =>
        // Open content.
        for text in annotations {
          if version == Isl20 && text is Some(text) && is_reserved(text) {
            raise @ion.IonError::DataModel(
              "open content must not be annotated with the reserved symbol '\{text}'",
            )
          }
        }
    }
  }
  if version == Isl10 && header_seen != footer_seen {
    raise @ion.IonError::DataModel(
      "an Ion Schema 1.0 schema has a header only if it has a footer",
    )
  }
  { version, imports, definitions, user_fields, }
}

///|
/// Schema documents being loaded, and the types loaded so far.
priv struct Loader {
  resolver : ((String) -> Array[@ion.IonValue] raise @ion.IonError)?
  /// The names of the types each document defines, by the document's id,
  /// known before its imports load, so that documents can import each other.
  documents : Map[String, Array[String]]
  /// The type definitions of each document, by type key, with the scope
  /// they are in, for what a type reference refers to before it loads.
  definitions : Map[String, (Array[@ion.Field], Context)]
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
    version: parsed.version,
    scope,
    user_fields: parsed.user_fields.types,
  }
  for fields in parsed.definitions {
    self.definitions[type_key(id, type_name(fields))] = (fields, ctx)
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
  version : IslVersion
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
/// change the document's scope. ISL 1.0 also allows an `as`, which has no
/// effect.
fn Context::inline_import(
  self : Context,
  fields : Array[@ion.Field],
) -> Constraint raise @ion.IonError {
  let allowed = match self.version {
    Isl10 => ["id", "type", "as"]
    Isl20 => ["id", "type"]
  }
  let (id, name, _) = import_fields(fields, allowed)
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
/// declares, and its imports. In ISL 2.0, its other fields must be user
/// content. In ISL 1.0, they are open content, and `user_reserved_fields` is
/// one of them.
fn load_header(
  fields : Array[@ion.Field],
  version : IslVersion,
) -> (UserFields, Array[@ion.IonValue]) raise @ion.IonError {
  let user_fields = match field_value(fields, "user_reserved_fields") {
    Some(declaration) if version == Isl20 =>
      load_user_reserved_fields(declaration)
    _ => UserFields::none()
  }
  let keys = if version == Isl20 {
    ["user_reserved_fields", "imports"]
  } else {
    ["imports"]
  }
  for key in keys {
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
  if version == Isl10 {
    return (user_fields, imports)
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
