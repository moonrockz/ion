// Bridges between Ion and types with core `ToJson` and `FromJson`.
//
// MoonBit cannot derive `ToIon` or `FromIon`, and has no blanket impls, so a
// type that derives the core JSON traits gets its Ion codecs through these
// two functions:
//
//   impl ToIon for Event with fn to_ion(self) { to_ion_via_json(self) }
//   impl FromIon for Event with fn from_ion(value) { from_ion_via_json(value) }
//
// Both go through JSON, so they follow the JSON rules: JSON to Ion maps
// numbers by spelling (see `json.mbt`), and Ion to JSON drops annotations,
// turns symbols and timestamps into strings and folds repeated field names
// onto the last (see `to_json.mbt`).

///|
/// Encode a value as the Ion value of its core JSON form.
pub fn[T : ToJson] to_ion_via_json(value : T) -> Ion {
  Ion(value.to_json())
}

///|
/// Decode a value from the core JSON form of an Ion value.
///
/// Raises [`FromIonError::MissingSymbolText`] when the Ion value has a symbol
/// with no text, so it has no JSON form, and
/// [`FromIonError::JsonDecode`] when `FromJson` rejects the JSON. The second
/// keeps core's message, and its path names the same field names and list
/// indexes in the Ion value.
pub fn[T : FromJson] from_ion_via_json(value : Ion) -> T raise FromIonError {
  let json : Json = FromIon::from_ion(value)
  @json.from_json(json) catch {
    @json.JsonDecodeError((path, message)) =>
      raise JsonDecode(path=json_path_segments(json, path), message~)
  }
}

///|
/// The path segments of a core `JsonPath` into `root`.
///
/// A `JsonPath` renders only as a JSON Pointer (`/tags/1`), which cannot tell
/// the field name `"1"` from the index `1`; the JSON value can. A step into an
/// array is an index when it parses as one; every other step is a field name.
fn json_path_segments(root : Json, path : @json.JsonPath) -> Array[PathSegment] {
  let pointer = path.to_string()
  let segments : Array[PathSegment] = []
  if pointer.is_empty() {
    return segments
  }
  let mut current : Json? = Some(root)
  for token in pointer[1:].split("/") {
    let step = token
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~")
    match current {
      Some(Array(items)) =>
        try @string.parse_int(step) catch {
          _ => {
            segments.push(Name(step))
            current = None
          }
        } noraise {
          index => {
            segments.push(Index(index))
            current = items.get(index)
          }
        }
      Some(Object(members)) => {
        segments.push(Name(step))
        current = members.get(step)
      }
      _ => {
        segments.push(Name(step))
        current = None
      }
    }
  }
  segments
}
