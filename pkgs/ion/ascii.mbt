// ASCII scanning helpers shared by the Ion readers.
//
// Ion text is UTF-8, so multi-byte characters never collide with the ASCII
// structure this file recognizes; scanning happens one UTF-16 code unit at a
// time, which matches the ASCII subset exactly.

///|
/// Whether `c` is an ASCII decimal digit (`0`-`9`).
fn is_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// The one-character string view at `index`, used to accumulate clean digit
/// runs while skipping Ion's digit-separating underscores.
fn char_view(text : StringView, index : Int) -> StringView {
  text[index:index + 1]
}
