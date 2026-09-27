// JSON interoperability for Ion.
//
// This package converts between the Ion data model (`@core.IonValue`) and
// MoonBit's core JSON type (`Json`), in both directions:
//
//   * [`to_ion`] maps JSON to Ion. JSON is a strict subset of Ion, so this
//     direction is faithful: a JSON value converted to Ion and back is the
//     same JSON value.
//   * [`to_json`] maps Ion to JSON. Ion is richer than JSON, so this direction
//     is lossy; it follows the Ion cookbook's documented "Down-converting to
//     JSON" process.
//   * [`read_json`] and [`write_json`] are the convenience wrappers that go
//     through JSON text.
//
// The two directions are deliberately not inverses of each other. A symbol, a
// timestamp, and a string all become a JSON string on the way out, so the
// trip back cannot tell them apart; that is inherent to JSON, not a shortcut.

///|
/// Parse JSON text into an Ion value, following the same rules as [`to_ion`].
///
/// The result is always a single Ion value; the caller can re-serialize it as
/// Ion text or binary with `@text` or `@binary`.
pub fn read_json(text : StringView) -> @core.IonValue raise @core.IonError {
  let json = @cjson.parse(text) catch {
    error => raise @core.IonError::Syntax("invalid JSON: \{error}")
  }
  to_ion(json)
}

///|
/// Render an Ion value as JSON text, following the same rules as [`to_json`].
///
/// `indent` is the number of spaces per nesting level; `0` (the default)
/// prints a single line.
pub fn write_json(
  value : @core.IonValue,
  indent? : Int = 0,
) -> String raise @core.IonError {
  to_json(value).stringify(indent~)
}
