// Small ASCII/UTF-16 helpers shared by the Ion text reader and writer.

///|
/// A single-character view of `text` at `index`, used to accumulate runs.
fn char_view(text : StringView, index : Int) -> StringView {
  text[index:index + 1]
}

///|
/// A `Char` for a valid Unicode scalar value. Every call site passes one, so
/// the unchecked conversion is safe.
fn char_from_code(code : Int) -> Char {
  code.unsafe_to_char()
}

///|
/// Whether a code unit is an ASCII decimal digit.
fn is_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Whether a code unit may start an unquoted Ion symbol identifier.
fn is_identifier_start(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$'
}

///|
/// Whether a code unit may continue an unquoted Ion symbol identifier.
fn is_identifier_part(c : UInt16) -> Bool {
  is_identifier_start(c) || is_digit(c)
}

///|
/// Whether `word` is an unquoted Ion symbol-ID literal: a `$` followed by one
/// or more digits. Such a word denotes the symbol with that ID, not a symbol
/// whose text is the word itself, so a writer must quote it to keep the text.
fn is_symbol_id_literal(word : String) -> Bool {
  if word.length() < 2 || word[0] != '$' {
    return false
  }
  for index in 1..<word.length() {
    if !is_digit(word[index]) {
      return false
    }
  }
  true
}

///|
/// Whether `word` has the form of an Ion version marker, `$ion_` followed by a
/// major and a minor version, such as `$ion_1_0`. Unquoted at the top level,
/// such a word is a version marker rather than a symbol, so a writer must
/// quote it to keep the symbol.
fn is_version_marker_literal(word : String) -> Bool {
  if !word.has_prefix("$ion_") {
    return false
  }
  let parts = word[5:].split("_").collect()
  parts.length() == 2 &&
  parts
  .iter()
  .all(part => part.length() > 0 && part.iter().all(c => c >= '0' && c <= '9'))
}

///|
/// Whether `word` is an Ion keyword, which is not a symbol unless quoted.
fn is_keyword(word : String) -> Bool {
  word is ("null" | "true" | "false" | "nan")
}
