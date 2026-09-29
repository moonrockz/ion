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
pub fn Schema::load(
  values : Array[@ion.IonValue],
) -> Schema raise @ion.IonError {
  let types : Array[TypeDefinition] = []
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
      if version_seen || header_seen || !types.is_empty() {
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
            if header_seen || !types.is_empty() {
              raise @ion.IonError::DataModel(
                "a schema has one header, before its types",
              )
            }
            header_seen = true
            user_fields = load_header(fields)
          }
          "type" => types.push(load_type_definition(fields, user_fields.types))
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
  Schema::from_types(types)
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
/// Load the schema header: its imports, which are not supported, its
/// `user_reserved_fields`, and its user content.
fn load_header(fields : Array[@ion.Field]) -> UserFields raise @ion.IonError {
  let user_fields = match field_value(fields, "user_reserved_fields") {
    Some(declaration) => load_user_reserved_fields(declaration)
    None => UserFields::none()
  }
  for key in ["user_reserved_fields", "imports"] {
    if fields.filter(field => field.name().text() == Some(key)).length() > 1 {
      raise @ion.IonError::DataModel("a schema header has at most one '\{key}'")
    }
  }
  for field in fields {
    match field.name().text() {
      Some("user_reserved_fields") => ()
      Some("imports") =>
        match field.value().kind() {
          @ion.IonValueKind::List([]) => ()
          _ =>
            raise @ion.IonError::Unsupported("schema imports are not supported")
        }
      _ => ()
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
  user_fields
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
