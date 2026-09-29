// The Ion text reader: a hand-written recursive-descent parser over UTF-16
// code units. Ion text is UTF-8, but every structural character is ASCII, so
// scanning code units is exact for the grammar while string content is copied
// through unchanged (surrogate pairs included).

///|
/// Whether a code unit is Ion whitespace.
fn is_space_unit(c : UInt16) -> Bool {
  match c.to_int() {
    0x20 | 0x09 | 0x0A | 0x0D | 0x0B | 0x0C => true
    _ => false
  }
}

///|
/// Whether a code unit terminates an unquoted numeric or timestamp token.
fn is_numeric_stop(c : UInt16) -> Bool {
  match c {
    '{' | '}' | '[' | ']' | '(' | ')' | ',' | '"' | '\'' => true
    _ => is_space_unit(c)
  }
}

///|
/// Whether a code unit is one of the nineteen S-expression operator characters.
fn is_operator_char(c : UInt16) -> Bool {
  match c {
    '!'
    | '#'
    | '%'
    | '&'
    | '*'
    | '+'
    | '-'
    | '.'
    | '/'
    | ';'
    | '<'
    | '='
    | '>'
    | '?'
    | '@'
    | '^'
    | '`'
    | '|'
    | '~' => true
    _ => false
  }
}

///|
/// Whether a code unit belongs to the RFC 4648 base64 alphabet.
fn is_base64_char(c : UInt16) -> Bool {
  (c >= 'A' && c <= 'Z') ||
  (c >= 'a' && c <= 'z') ||
  (c >= '0' && c <= '9') ||
  c == '+' ||
  c == '/'
}

///|
/// Parse exactly one Ion value, requiring that only whitespace and comments
/// follow it. Version markers and local symbol tables before the value are
/// applied rather than returned; `catalog` supplies the shared symbol tables
/// they import.
pub fn read_ion(
  text : StringView,
  catalog? : @ion.Catalog = @ion.Catalog::new(),
) -> @ion.IonValue raise @ion.IonError {
  let parser = Parser::new(text)
  let symbols = @ion.SymbolTable::system(catalog~)
  let mut result : @ion.IonValue? = None
  parser.skip_ws()
  while result is None {
    if parser.at_end() {
      raise @ion.IonError::Syntax("expected an Ion value, found end of input")
    }
    result = apply_top_level(symbols, parser.parse_top_level_value())
    parser.skip_ws()
  }
  if !parser.at_end() {
    raise @ion.IonError::Syntax("unexpected trailing input after the Ion value")
  }
  result.unwrap()
}

///|
/// Parse a whole Ion datagram: a whitespace-separated sequence of values.
/// Version markers and local symbol tables are applied rather than returned,
/// so every symbol ID a local symbol table defines comes back with its text.
/// `catalog` supplies the shared symbol tables they import.
pub fn read_ion_datagram(
  text : StringView,
  catalog? : @ion.Catalog = @ion.Catalog::new(),
) -> Array[@ion.IonValue] raise @ion.IonError {
  let parser = Parser::new(text)
  let symbols = @ion.SymbolTable::system(catalog~)
  let values : Array[@ion.IonValue] = []
  parser.skip_ws()
  while !parser.at_end() {
    match apply_top_level(symbols, parser.parse_top_level_value()) {
      Some(value) => values.push(value)
      None => ()
    }
    parser.skip_ws()
  }
  values
}

///|
/// Parse the first top-level value of a datagram from text that may be only
/// the start of the input, as a streaming reader sees it. The result is the
/// value and the number of code units it spans, including the whitespace and
/// comments after it; `None` means no value is available yet.
///
/// A version marker or a local symbol table updates `symbols` and comes back
/// as `Some((None, consumed))`; any other value comes back with the symbol IDs
/// that `symbols` defines resolved. `symbols` changes only when a value is
/// returned, so a caller can retry the same text after `None`.
///
/// While `end_of_input` is false, a value is returned only when it is settled:
/// it closes with `]`, `)`, `}`, or `"`, or the text that follows it shows
/// where it ends. A value that fails to parse is taken to be cut short, so
/// `None` asks for more text. Once `end_of_input` is true, `None` means only
/// whitespace and comments remain, and a malformed value raises.
pub fn read_ion_prefix(
  text : StringView,
  symbols~ : @ion.SymbolTable,
  end_of_input~ : Bool,
) -> (@ion.IonValue?, Int)? raise @ion.IonError {
  let prefix = if end_of_input {
    read_prefix(text, end_of_input=true)
  } else {
    read_prefix(text, end_of_input=false) catch {
      _ => None
    }
  }
  match prefix {
    Some((top_level, consumed)) =>
      Some((apply_top_level(symbols, top_level), consumed))
    None => None
  }
}

///|
/// Apply a top-level value to `symbols`: an unquoted `$ion_1_0` (a marker)
/// resets the table, a local symbol table updates it, and any other
/// unannotated symbol with the text `$ion_1_0` is a no-op; none of them is
/// returned. Any other value comes back with its symbol IDs resolved.
fn apply_top_level(
  symbols : @ion.SymbolTable,
  top_level : TopLevel,
) -> @ion.IonValue? raise @ion.IonError {
  let { value, marker, symbol_ids, } = top_level
  if marker &&
    value.annotations().is_empty() &&
    value.kind() is @ion.IonValueKind::Symbol(token) &&
    token.text() is Some(text) &&
    is_version_marker_literal(text) {
    if text != "$ion_1_0" {
      raise @ion.IonError::Unsupported(
        "the Ion version marker \{text} is not supported; only Ion 1.0 is",
      )
    }
    symbols.reset()
    return None
  }
  let value = if symbol_ids { symbols.resolve(value) } else { value }
  if symbols.apply_local_symbol_table(value) || is_version_marker_symbol(value) {
    None
  } else {
    Some(value)
  }
}

///|
/// Whether a top-level value is an unannotated symbol with the text
/// `$ion_1_0` that is not spelled as a version marker, such as `'$ion_1_0'` or
/// `$2`. Such a value is a no-op: a reader drops it and keeps its table.
fn is_version_marker_symbol(value : @ion.IonValue) -> Bool {
  value.annotations().is_empty() &&
  value.kind() is @ion.IonValueKind::Symbol(token) &&
  token.text() == Some("$ion_1_0")
}

///|
/// The number of code units that must follow a value, once whitespace and
/// comments are skipped, before the value is settled. An unquoted scalar can
/// run on into more text, and otherwise a value can still grow only through a
/// token that begins right after it: `::` makes a symbol an annotation, and
/// `'''` continues a long string. Three code units tell both apart from the
/// start of the next value.
let settle_lookahead : Int = 3

///|
/// Whether a value that ends with the code unit `last` is settled whatever
/// text follows it: a container, a lob, or a short string closes with a
/// delimiter that nothing can extend.
fn is_closing_delimiter(last : UInt16) -> Bool {
  match last {
    ']' | ')' | '}' | '"' => true
    _ => false
  }
}

///|
/// The first value of `read_ion_prefix` as the parser read it, and the code
/// units it spans. Raises on a malformed value whether or not the input has
/// ended.
fn read_prefix(
  text : StringView,
  end_of_input~ : Bool,
) -> (TopLevel, Int)? raise @ion.IonError {
  let parser = Parser::new(text)
  parser.skip_ws()
  if parser.at_end() {
    return None
  }
  let top_level = parser.parse_top_level_value()
  let closed = is_closing_delimiter(text[parser.pos - 1])
  parser.skip_ws()
  if !end_of_input && !closed && parser.pos + settle_lookahead > text.length() {
    return None
  }
  Some((top_level, parser.pos))
}

///|
/// A cursor over an Ion text document.
priv struct Parser {
  input : StringView
  mut pos : Int
  /// Depth of nested S-expressions; operators are only recognized inside one.
  mut sexp_depth : Int
  /// Whether the parser has read a symbol-ID literal that a symbol table must
  /// resolve, since the flag was last cleared.
  mut symbol_ids : Bool
}

///|
/// A parser positioned at the start of `input`.
fn Parser::new(input : StringView) -> Parser {
  { input, pos: 0, sexp_depth: 0, symbol_ids: false, }
}

///|
/// Whether the cursor has reached the end of the input.
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.input.length()
}

///|
/// The code unit at `offset` from the cursor, when in range.
fn Parser::peek_at(self : Parser, offset : Int) -> UInt16? {
  let index = self.pos + offset
  if index >= self.input.length() {
    None
  } else {
    Some(self.input[index])
  }
}

///|
/// Whether the input at the cursor begins with `text`.
fn Parser::starts_with(self : Parser, text : StringView) -> Bool {
  let n = text.length()
  if self.pos + n > self.input.length() {
    return false
  }
  self.input[self.pos:self.pos + n] == text
}

///|
/// Skip whitespace and both forms of C-style comment.
fn Parser::skip_ws(self : Parser) -> Unit raise @ion.IonError {
  while !self.at_end() {
    let c = self.input[self.pos]
    if is_space_unit(c) {
      self.pos += 1
    } else if c == '/' {
      match self.peek_at(1) {
        Some('/') => {
          self.pos += 2
          while !self.at_end() {
            let inner = self.input[self.pos]
            if inner == '\n' || inner == '\r' {
              break
            }
            self.pos += 1
          }
        }
        Some('*') => {
          self.pos += 2
          let mut closed = false
          while !self.at_end() {
            if self.input[self.pos] == '*' && self.peek_at(1) == Some('/') {
              self.pos += 2
              closed = true
              break
            }
            self.pos += 1
          }
          if !closed {
            raise @ion.IonError::Syntax("unterminated block comment")
          }
        }
        _ => break
      }
    } else {
      break
    }
  }
}

///|
/// Skip the whitespace allowed inside a blob or clob. Comments are not
/// permitted there, so `/` is left for the blob body to consume.
fn Parser::skip_lob_ws(self : Parser) -> Unit {
  while !self.at_end() && is_space_unit(self.input[self.pos]) {
    self.pos += 1
  }
}

///|
/// Read a top-level value, and whether it is spelled as an unquoted `$ion_`
/// identifier, the only spelling of a version marker.
fn Parser::parse_top_level_value(self : Parser) -> TopLevel raise @ion.IonError {
  let marker = self.starts_with("$ion_")
  self.symbol_ids = false
  let value = self.parse_value()
  { value, marker, symbol_ids: self.symbol_ids, }
}

///|
/// A top-level value as the parser read it, before a symbol table applies.
priv struct TopLevel {
  value : @ion.IonValue
  /// Spelled as an unquoted `$ion_` identifier, the only spelling of a
  /// version marker.
  marker : Bool
  /// Holds a symbol-ID literal that the symbol table must resolve.
  symbol_ids : Bool
}

///|
/// The token for a symbol-ID literal such as `$10`, noting that the value
/// holds one the symbol table must resolve.
fn Parser::symbol_id(self : Parser, word : String) -> @ion.SymbolToken? {
  let token = resolve_symbol_id(word)
  if token is Some(token) && token.text() is None && token.sid() != Some(0) {
    self.symbol_ids = true
  }
  token
}

///|
/// Read a value, including any leading annotations.
fn Parser::parse_value(self : Parser) -> @ion.IonValue raise @ion.IonError {
  let annotations = self.parse_annotations()
  let value = self.parse_bare_value()
  if annotations.is_empty() {
    value
  } else {
    value.with_annotations(annotations)
  }
}

///|
/// Read `annotation::` prefixes. A symbol that is not followed by `::` is not
/// an annotation, so the cursor is restored and the scan stops.
fn Parser::parse_annotations(
  self : Parser,
) -> Array[@ion.SymbolToken] raise @ion.IonError {
  let annotations : Array[@ion.SymbolToken] = []
  while true {
    let start = self.pos
    self.skip_ws()
    if self.at_end() {
      break
    }
    let c = self.input[self.pos]
    let mut keyword = false
    let token : @ion.SymbolToken? = if c == '\'' {
      Some(self.parse_quoted_symbol())
    } else if is_identifier_start(c) {
      let word = self.parse_identifier()
      keyword = is_keyword(word)
      Some(
        match self.symbol_id(word) {
          Some(token) => token
          None => @ion.SymbolToken::new(word)
        },
      )
    } else {
      None
    }
    match token {
      None => {
        self.pos = start
        break
      }
      Some(token) => {
        self.skip_ws()
        if self.peek_at(0) == Some(':') && self.peek_at(1) == Some(':') {
          if keyword {
            raise @ion.IonError::Syntax(
              "a keyword must be quoted to be an annotation",
            )
          }
          self.pos += 2
          annotations.push(token)
        } else {
          self.pos = start
          break
        }
      }
    }
  }
  annotations
}

///|
/// Read a value with no leading annotations.
fn Parser::parse_bare_value(self : Parser) -> @ion.IonValue raise @ion.IonError {
  self.skip_ws()
  if self.at_end() {
    raise @ion.IonError::Syntax("expected an Ion value, found end of input")
  }
  let c = self.input[self.pos]
  match c {
    '[' => self.parse_list()
    '(' => self.parse_sexp()
    '{' => self.parse_braced()
    '"' => @ion.IonValue::string(self.parse_double_quoted_string())
    '\'' =>
      if self.peek_at(1) == Some('\'') && self.peek_at(2) == Some('\'') {
        @ion.IonValue::string(self.parse_long_string())
      } else {
        @ion.IonValue::symbol_token(self.parse_quoted_symbol())
      }
    _ => self.parse_unquoted()
  }
}

///|
/// Read a value that begins with an identifier, sign, digit, or (inside an
/// S-expression) an operator.
fn Parser::parse_unquoted(self : Parser) -> @ion.IonValue raise @ion.IonError {
  let c = self.input[self.pos]
  if is_identifier_start(c) {
    return self.parse_word()
  }
  if c == '+' {
    if self.starts_with("+inf") {
      self.pos += 4
      return @ion.IonValue::float(@double.infinity)
    }
  } else if c == '-' {
    if self.starts_with("-inf") {
      self.pos += 4
      return @ion.IonValue::float(@double.neg_infinity)
    }
    match self.peek_at(1) {
      Some(next) if is_digit(next) => return self.parse_numeric()
      _ => ()
    }
  } else if is_digit(c) {
    return self.parse_numeric()
  }
  if self.sexp_depth > 0 && is_operator_char(c) {
    return @ion.IonValue::symbol(self.parse_operator())
  }
  raise @ion.IonError::Syntax(
    "unexpected character at position \{self.pos} of the Ion input",
  )
}

///|
/// Read an identifier, classifying the reserved words `null` (and typed nulls),
/// `true`, `false`, and `nan`; everything else is a symbol.
fn Parser::parse_word(self : Parser) -> @ion.IonValue raise @ion.IonError {
  let word = self.parse_identifier()
  match self.symbol_id(word) {
    Some(token) => return @ion.IonValue::symbol_token(token)
    None => ()
  }
  match word {
    "null" =>
      if self.peek_at(0) == Some('.') {
        self.pos += 1
        if self.at_end() || !is_identifier_start(self.input[self.pos]) {
          raise @ion.IonError::Syntax("expected an Ion type name after 'null.'")
        }
        let type_name = self.parse_identifier()
        match @ion.IonType::from_text(type_name) {
          Some(t) => @ion.IonValue::typed_null(t)
          None =>
            raise @ion.IonError::Syntax(
              "unknown Ion type name in typed null: \{type_name}",
            )
        }
      } else {
        @ion.IonValue::untyped_null()
      }
    "true" => @ion.IonValue::bool(true)
    "false" => @ion.IonValue::bool(false)
    "nan" => @ion.IonValue::float(not_a_number())
    _ => @ion.IonValue::symbol(word)
  }
}

///|
/// The IEEE-754 quiet NaN. MoonBit's `@double` exposes infinities but not a NaN
/// constant, so it is produced arithmetically.
fn not_a_number() -> Double {
  @double.infinity - @double.infinity
}

///|
/// Read an unquoted identifier.
fn Parser::parse_identifier(self : Parser) -> String {
  let start = self.pos
  while !self.at_end() && is_identifier_part(self.input[self.pos]) {
    self.pos += 1
  }
  self.input[start:self.pos].to_owned()
}

///|
/// Read a run of S-expression operator characters. A `//` or `/*` is a comment
/// and therefore terminates the operator.
fn Parser::parse_operator(self : Parser) -> String {
  let start = self.pos
  while !self.at_end() {
    let c = self.input[self.pos]
    if !is_operator_char(c) {
      break
    }
    if c == '/' {
      match self.peek_at(1) {
        Some('/') | Some('*') => break
        _ => ()
      }
    }
    self.pos += 1
  }
  self.input[start:self.pos].to_owned()
}

///|
/// Whether a timestamp (`YYYY-...` or `YYYYT`) begins at the cursor.
fn Parser::looks_like_timestamp(self : Parser) -> Bool {
  if self.pos + 5 > self.input.length() {
    return false
  }
  for offset in 0..<4 {
    if !is_digit(self.input[self.pos + offset]) {
      return false
    }
  }
  let c = self.input[self.pos + 4]
  c == '-' || c == 'T'
}

///|
/// Consume the unquoted token at the cursor (ending at a numeric stop
/// character or end of input).
fn Parser::read_numeric_token(self : Parser) -> StringView {
  let start = self.pos
  while !self.at_end() && !is_numeric_stop(self.input[self.pos]) {
    self.pos += 1
  }
  self.input[start:self.pos]
}

///|
/// Read a number or timestamp.
fn Parser::parse_numeric(self : Parser) -> @ion.IonValue raise @ion.IonError {
  let timestamp = self.looks_like_timestamp()
  let token = self.read_numeric_token()
  if timestamp {
    @ion.IonValue::timestamp(@ion.Timestamp::parse(token))
  } else {
    classify_number(token)
  }
}

///|
/// Classify an unquoted numeric token as an int, float, or decimal.
fn classify_number(token : StringView) -> @ion.IonValue raise @ion.IonError {
  let n = token.length()
  let mut start = 0
  let negative = if token[0] == '-' {
    start = 1
    true
  } else {
    false
  }
  if start + 1 < n && token[start] == '0' {
    let radix_marker = token[start + 1]
    if radix_marker == 'x' || radix_marker == 'X' {
      return @ion.IonValue::big_int(
        parse_radix_int(token, start + 2, 16, negative),
      )
    }
    if radix_marker == 'b' || radix_marker == 'B' {
      return @ion.IonValue::big_int(
        parse_radix_int(token, start + 2, 2, negative),
      )
    }
  }
  let mut has_dot = false
  let mut has_exponent_e = false
  let mut has_exponent_d = false
  for index in start..<n {
    match token[index] {
      '.' => has_dot = true
      'd' | 'D' => has_exponent_d = true
      'e' | 'E' => has_exponent_e = true
      _ => ()
    }
  }
  if has_exponent_d || has_dot || has_exponent_e {
    check_leading_zero(token, start)
    check_underscores(token)
  }
  if has_exponent_d || (has_dot && !has_exponent_e) {
    return @ion.IonValue::decimal(@ion.Decimal::parse(token))
  }
  if has_exponent_e {
    let cleaned = strip_underscores(token)
    let value : Double = @string.parse_double(cleaned) catch {
      // A well-formed literal beyond the range of a double is infinite.
      Failure(_) if is_float_literal(cleaned) =>
        if negative {
          @double.neg_infinity
        } else {
          @double.infinity
        }
      _ => raise @ion.IonError::Syntax("invalid float literal")
    }
    return @ion.IonValue::float(value)
  }
  @ion.IonValue::big_int(parse_decimal_int(token))
}

///|
/// Reject a decimal or float whose integer part, from `start`, has a leading
/// zero, such as `03.4` or `00e0`.
fn check_leading_zero(
  token : StringView,
  start : Int,
) -> Unit raise @ion.IonError {
  if start + 1 < token.length() &&
    token[start] == '0' &&
    (is_digit(token[start + 1]) || token[start + 1] == '_') {
    raise @ion.IonError::Syntax("leading zeros are not allowed in a number")
  }
}

///|
/// Reject an underscore in a decimal or float that does not sit between two
/// digits, such as in `1_.2`, `1.2e_3`, or `6.0__1e1`.
fn check_underscores(token : StringView) -> Unit raise @ion.IonError {
  for index in 0..<token.length() {
    if token[index] == '_' &&
      (
        index == 0 ||
        index + 1 >= token.length() ||
        !is_digit(token[index - 1]) ||
        !is_digit(token[index + 1])
      ) {
      raise @ion.IonError::Syntax(
        "an underscore in a number must sit between two digits",
      )
    }
  }
}

///|
/// Whether `text` is a well-formed float literal: digits, an optional
/// fraction, and an exponent, with an optional sign.
fn is_float_literal(text : String) -> Bool {
  let mut index = 0
  let n = text.length()
  if index < n && text[index] == '-' {
    index += 1
  }
  let digits_start = index
  while index < n && is_digit(text[index]) {
    index += 1
  }
  if index == digits_start {
    return false
  }
  if index < n && text[index] == '.' {
    index += 1
    while index < n && is_digit(text[index]) {
      index += 1
    }
  }
  if index >= n || (text[index] != 'e' && text[index] != 'E') {
    return false
  }
  index += 1
  if index < n && (text[index] == '+' || text[index] == '-') {
    index += 1
  }
  let exponent_start = index
  while index < n && is_digit(text[index]) {
    index += 1
  }
  index > exponent_start && index == n
}

///|
/// Remove Ion's digit-separating underscores.
fn strip_underscores(text : StringView) -> String {
  let sb = StringBuilder()
  for index in 0..<text.length() {
    if text[index] != '_' {
      sb.write_view(char_view(text, index))
    }
  }
  sb.to_string()
}

///|
/// Remove Ion's digit-separating underscores, rejecting a leading, trailing, or
/// doubled underscore.
fn clean_digits(text : StringView) -> String raise @ion.IonError {
  let sb = StringBuilder()
  let mut saw_digit = false
  let mut previous_underscore = false
  for index in 0..<text.length() {
    if text[index] == '_' {
      if !saw_digit || previous_underscore {
        raise @ion.IonError::Syntax("misplaced underscore in number")
      }
      previous_underscore = true
    } else {
      sb.write_view(char_view(text, index))
      saw_digit = true
      previous_underscore = false
    }
  }
  if previous_underscore {
    raise @ion.IonError::Syntax("number may not end with an underscore")
  }
  sb.to_string()
}

///|
/// Parse a base-10 integer token into a `BigInt`.
fn parse_decimal_int(token : StringView) -> BigInt raise @ion.IonError {
  let mut start = 0
  let mut negative = false
  if token.length() > 0 && (token[0] == '-' || token[0] == '+') {
    negative = token[0] == '-'
    start = 1
  }
  let digits = clean_digits(token[start:])
  if digits.is_empty() {
    raise @ion.IonError::Syntax("integer literal has no digits")
  }
  if digits.length() > 1 && digits[0] == '0' {
    raise @ion.IonError::Syntax("leading zeros are not allowed in an integer")
  }
  let value = @string.parse_bigint(digits, base=10) catch {
    _ => raise @ion.IonError::Syntax("invalid integer literal")
  }
  if negative {
    value.neg()
  } else {
    value
  }
}

///|
/// Parse a radix-prefixed integer (after its `0x`/`0b` marker).
fn parse_radix_int(
  token : StringView,
  start : Int,
  radix : Int,
  negative : Bool,
) -> BigInt raise @ion.IonError {
  let digits = clean_digits(token[start:])
  if digits.is_empty() {
    raise @ion.IonError::Syntax("radix-prefixed integer has no digits")
  }
  let value = @string.parse_bigint(digits, base=radix) catch {
    _ => raise @ion.IonError::Syntax("invalid radix-prefixed integer literal")
  }
  if negative {
    value.neg()
  } else {
    value
  }
}

///|
/// Read a double-quoted string, decoding its escapes.
fn Parser::parse_double_quoted_string(
  self : Parser,
) -> String raise @ion.IonError {
  self.pos += 1
  let sb = StringBuilder()
  while true {
    if self.at_end() {
      raise @ion.IonError::Syntax("unterminated string")
    }
    let c = self.input[self.pos]
    if c == '"' {
      self.pos += 1
      break
    }
    if c == '\n' || c == '\r' {
      raise @ion.IonError::Syntax("unescaped newline in string")
    }
    check_raw_unit(c, long=false)
    if c == '\\' {
      let code = self.parse_escape()
      if code >= 0 {
        sb.write_char(char_from_code(code))
      }
    } else {
      self.copy_code_point(sb)
    }
  }
  sb.to_string()
}

///|
/// Reject a raw control character, which a string, symbol, or clob must
/// escape. Tab, vertical tab, and form feed are whitespace and allowed, and a
/// long string or long clob (`long`) also allows raw newlines.
fn check_raw_unit(c : UInt16, long~ : Bool) -> Unit raise @ion.IonError {
  if c >= 0x20 {
    return
  }
  match c.to_int() {
    0x09 | 0x0B | 0x0C => ()
    0x0A | 0x0D if long => ()
    _ =>
      raise @ion.IonError::Syntax(
        "a raw control character must be escaped in a string, symbol, or clob",
      )
  }
}

///|
/// Consume a raw carriage return, and the line feed after it if any. Either
/// form of line ending reads as a line feed.
fn Parser::skip_carriage_return(self : Parser) -> Unit {
  self.pos += 1
  if self.peek_at(0) == Some('\n') {
    self.pos += 1
  }
}

///|
/// Read a long string: one or more adjacent triple-single-quoted strings,
/// concatenated (comments and whitespace may appear between them).
fn Parser::parse_long_string(self : Parser) -> String raise @ion.IonError {
  let sb = StringBuilder()
  self.parse_long_string_body(sb)
  while true {
    let save = self.pos
    self.skip_ws()
    if self.at_triple_quote() {
      self.parse_long_string_body(sb)
    } else {
      self.pos = save
      break
    }
  }
  sb.to_string()
}

///|
/// Whether `'''` begins at the cursor.
fn Parser::at_triple_quote(self : Parser) -> Bool {
  self.peek_at(0) == Some('\'') &&
  self.peek_at(1) == Some('\'') &&
  self.peek_at(2) == Some('\'')
}

///|
/// Append the body of one triple-single-quoted string.
fn Parser::parse_long_string_body(
  self : Parser,
  sb : StringBuilder,
) -> Unit raise @ion.IonError {
  self.pos += 3
  while true {
    if self.at_end() {
      raise @ion.IonError::Syntax("unterminated long string")
    }
    if self.at_triple_quote() {
      self.pos += 3
      break
    }
    let c = self.input[self.pos]
    check_raw_unit(c, long=true)
    if c == '\\' {
      let code = self.parse_escape()
      if code >= 0 {
        sb.write_char(char_from_code(code))
      }
    } else if c == '\r' {
      self.skip_carriage_return()
      sb.write_char('\n')
    } else {
      self.copy_code_point(sb)
    }
  }
}

///|
/// Read a single-quoted symbol, decoding its escapes.
fn Parser::parse_quoted_symbol(
  self : Parser,
) -> @ion.SymbolToken raise @ion.IonError {
  self.pos += 1
  let sb = StringBuilder()
  while true {
    if self.at_end() {
      raise @ion.IonError::Syntax("unterminated symbol")
    }
    let c = self.input[self.pos]
    if c == '\'' {
      self.pos += 1
      break
    }
    if c == '\n' || c == '\r' {
      raise @ion.IonError::Syntax("unescaped newline in symbol")
    }
    check_raw_unit(c, long=false)
    if c == '\\' {
      let code = self.parse_escape()
      if code >= 0 {
        sb.write_char(char_from_code(code))
      }
    } else {
      self.copy_code_point(sb)
    }
  }
  @ion.SymbolToken::new(sb.to_string())
}

///|
/// Decode one escape sequence. Returns the code point, or `-1` for an escaped
/// newline (which expands to nothing).
fn Parser::parse_escape(self : Parser) -> Int raise @ion.IonError {
  self.pos += 1
  if self.at_end() {
    raise @ion.IonError::Syntax("unterminated escape sequence")
  }
  let c = self.input[self.pos]
  self.pos += 1
  match c {
    '0' => 0x00
    'a' => 0x07
    'b' => 0x08
    't' => 0x09
    'n' => 0x0A
    'v' => 0x0B
    'f' => 0x0C
    'r' => 0x0D
    '"' => 0x22
    '\'' => 0x27
    '/' => 0x2F
    '?' => 0x3F
    '\\' => 0x5C
    '\n' => -1
    '\r' => {
      if self.peek_at(0) == Some('\n') {
        self.pos += 1
      }
      -1
    }
    'x' => self.read_hex(2)
    'u' => {
      let code = self.read_hex(4)
      if code >= 0xD800 && code <= 0xDBFF {
        if self.peek_at(0) == Some('\\') && self.peek_at(1) == Some('u') {
          self.pos += 2
          let low = self.read_hex(4)
          if low >= 0xDC00 && low <= 0xDFFF {
            0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
          } else {
            raise @ion.IonError::Syntax("invalid low surrogate in escape")
          }
        } else {
          raise @ion.IonError::Syntax("unpaired high surrogate in escape")
        }
      } else if code >= 0xDC00 && code <= 0xDFFF {
        raise @ion.IonError::Syntax("unpaired low surrogate in escape")
      } else {
        code
      }
    }
    'U' => {
      let code = self.read_hex(8)
      if code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF) {
        raise @ion.IonError::Syntax(
          "'\\U' escape is not a valid Unicode scalar value",
        )
      }
      code
    }
    _ => raise @ion.IonError::Syntax("invalid escape sequence")
  }
}

///|
/// Read `count` hexadecimal digits.
fn Parser::read_hex(self : Parser, count : Int) -> Int raise @ion.IonError {
  let mut value = 0
  for _ in 0..<count {
    if self.at_end() {
      raise @ion.IonError::Syntax("truncated hexadecimal escape")
    }
    let c = self.input[self.pos]
    let digit = if is_digit(c) {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      raise @ion.IonError::Syntax("invalid hexadecimal digit in escape")
    }
    value = value * 16 + digit
    self.pos += 1
  }
  value
}

///|
/// Dispatch between a struct and a blob/clob, both of which start with `{`.
fn Parser::parse_braced(self : Parser) -> @ion.IonValue raise @ion.IonError {
  if self.peek_at(1) == Some('{') {
    self.parse_lob()
  } else {
    self.parse_struct()
  }
}

///|
/// Read a blob (`{{ ... }}`, base64) or a clob (`{{ "..." }}`).
fn Parser::parse_lob(self : Parser) -> @ion.IonValue raise @ion.IonError {
  self.pos += 2
  self.skip_lob_ws()
  if self.at_end() {
    raise @ion.IonError::Syntax("unterminated blob or clob")
  }
  let c = self.input[self.pos]
  let is_clob = c == '"' || self.at_triple_quote()
  let bytes = if is_clob {
    if c == '"' {
      self.parse_clob_body()
    } else {
      self.parse_long_clob_body()
    }
  } else {
    self.parse_blob_body()
  }
  self.skip_lob_ws()
  if !(self.peek_at(0) == Some('}') && self.peek_at(1) == Some('}')) {
    raise @ion.IonError::Syntax("expected '}}' to close blob or clob")
  }
  self.pos += 2
  if is_clob {
    @ion.IonValue::clob(bytes)
  } else {
    @ion.IonValue::blob(bytes)
  }
}

///|
/// Read the base64 body of a blob, up to its closing `}}`.
fn Parser::parse_blob_body(self : Parser) -> Bytes raise @ion.IonError {
  let sb = StringBuilder()
  while true {
    if self.at_end() {
      raise @ion.IonError::Syntax("unterminated blob")
    }
    if self.peek_at(0) == Some('}') && self.peek_at(1) == Some('}') {
      break
    }
    let c = self.input[self.pos]
    if is_space_unit(c) {
      self.pos += 1
    } else if is_base64_char(c) || c == '=' {
      sb.write_view(char_view(self.input, self.pos))
      self.pos += 1
    } else {
      raise @ion.IonError::Syntax("invalid character in blob")
    }
  }
  @base64.decode(sb.to_string()) catch {
    _ => raise @ion.IonError::Syntax("invalid base64 in blob")
  }
}

///|
/// Decode one clob escape sequence into a byte value, or `None` for an escaped
/// newline. Clobs are byte-oriented, so only `\xHH` and the single-character
/// escapes are valid; `\u` and `\U` are not.
fn Parser::parse_clob_escape(self : Parser) -> Int? raise @ion.IonError {
  self.pos += 1
  if self.at_end() {
    raise @ion.IonError::Syntax("unterminated escape sequence")
  }
  let c = self.input[self.pos]
  self.pos += 1
  match c {
    '0' => Some(0x00)
    'a' => Some(0x07)
    'b' => Some(0x08)
    't' => Some(0x09)
    'n' => Some(0x0A)
    'v' => Some(0x0B)
    'f' => Some(0x0C)
    'r' => Some(0x0D)
    '"' => Some(0x22)
    '\'' => Some(0x27)
    '/' => Some(0x2F)
    '?' => Some(0x3F)
    '\\' => Some(0x5C)
    '\n' => None
    '\r' => {
      if self.peek_at(0) == Some('\n') {
        self.pos += 1
      }
      None
    }
    'x' => Some(self.read_hex(2))
    'u' | 'U' => raise @ion.IonError::Syntax("clobs support only '\\x' escapes")
    _ => raise @ion.IonError::Syntax("invalid escape sequence")
  }
}

///|
/// Read a double-quoted clob body into bytes.
fn Parser::parse_clob_body(self : Parser) -> Bytes raise @ion.IonError {
  let bytes : Array[Byte] = []
  self.pos += 1
  while true {
    if self.at_end() {
      raise @ion.IonError::Syntax("unterminated clob")
    }
    let c = self.input[self.pos]
    if c == '"' {
      self.pos += 1
      break
    }
    if c == '\n' || c == '\r' {
      raise @ion.IonError::Syntax("unescaped newline in clob")
    }
    check_raw_unit(c, long=false)
    if c == '\\' {
      match self.parse_clob_escape() {
        Some(code) => bytes.push(code.to_byte())
        None => ()
      }
    } else {
      if c.to_int() > 0x7F {
        raise @ion.IonError::Syntax(
          "clob may only contain 7-bit ASCII characters",
        )
      }
      bytes.push(c.to_byte())
      self.pos += 1
    }
  }
  Bytes::from_array(bytes)
}

///|
/// Read a long clob body: one or more adjacent `'''`-delimited strings.
fn Parser::parse_long_clob_body(self : Parser) -> Bytes raise @ion.IonError {
  let bytes : Array[Byte] = []
  self.parse_one_long_clob(bytes)
  while true {
    let save = self.pos
    // Unlike a long string, a long clob allows no comments between its parts.
    self.skip_lob_ws()
    if self.at_triple_quote() {
      self.parse_one_long_clob(bytes)
    } else {
      self.pos = save
      break
    }
  }
  Bytes::from_array(bytes)
}

///|
/// Append the body of one `'''`-delimited clob string.
fn Parser::parse_one_long_clob(
  self : Parser,
  bytes : Array[Byte],
) -> Unit raise @ion.IonError {
  self.pos += 3
  while true {
    if self.at_end() {
      raise @ion.IonError::Syntax("unterminated long clob")
    }
    if self.at_triple_quote() {
      self.pos += 3
      break
    }
    let c = self.input[self.pos]
    check_raw_unit(c, long=true)
    if c == '\\' {
      match self.parse_clob_escape() {
        Some(code) => bytes.push(code.to_byte())
        None => ()
      }
    } else if c == '\r' {
      self.skip_carriage_return()
      bytes.push(b'\n')
    } else {
      if c.to_int() > 0x7F {
        raise @ion.IonError::Syntax(
          "clob may only contain 7-bit ASCII characters",
        )
      }
      bytes.push(c.to_byte())
      self.pos += 1
    }
  }
}

///|
/// Read a struct.
fn Parser::parse_struct(self : Parser) -> @ion.IonValue raise @ion.IonError {
  self.pos += 1
  let fields : Array[@ion.Field] = []
  self.skip_ws()
  if self.peek_at(0) == Some('}') {
    self.pos += 1
    return @ion.IonValue::from_fields(fields)
  }
  while true {
    self.skip_ws()
    let name = self.parse_field_name()
    self.skip_ws()
    if self.peek_at(0) != Some(':') {
      raise @ion.IonError::Syntax("expected ':' after a struct field name")
    }
    self.pos += 1
    let value = self.parse_value()
    fields.push(@ion.Field::from_token(name, value))
    self.skip_ws()
    match self.peek_at(0) {
      Some(',') => {
        self.pos += 1
        self.skip_ws()
        if self.peek_at(0) == Some('}') {
          self.pos += 1
          break
        }
      }
      Some('}') => {
        self.pos += 1
        break
      }
      _ => raise @ion.IonError::Syntax("expected ',' or '}' in struct")
    }
  }
  @ion.IonValue::from_fields(fields)
}

///|
/// Read a struct field name: an identifier, a quoted symbol, or a string.
fn Parser::parse_field_name(
  self : Parser,
) -> @ion.SymbolToken raise @ion.IonError {
  if self.at_end() {
    raise @ion.IonError::Syntax("expected a struct field name")
  }
  let c = self.input[self.pos]
  if c == '"' {
    @ion.SymbolToken::new(self.parse_double_quoted_string())
  } else if self.at_triple_quote() {
    @ion.SymbolToken::new(self.parse_long_string())
  } else if c == '\'' {
    self.parse_quoted_symbol()
  } else if is_identifier_start(c) {
    let word = self.parse_identifier()
    if is_keyword(word) {
      raise @ion.IonError::Syntax("a keyword must be quoted to be a field name")
    }
    match self.symbol_id(word) {
      Some(token) => token
      None => @ion.SymbolToken::new(word)
    }
  } else {
    raise @ion.IonError::Syntax("invalid struct field name")
  }
}

///|
/// Read a list.
fn Parser::parse_list(self : Parser) -> @ion.IonValue raise @ion.IonError {
  self.pos += 1
  let items : Array[@ion.IonValue] = []
  self.skip_ws()
  if self.peek_at(0) == Some(']') {
    self.pos += 1
    return @ion.IonValue::list(items)
  }
  while true {
    items.push(self.parse_value())
    self.skip_ws()
    match self.peek_at(0) {
      Some(',') => {
        self.pos += 1
        self.skip_ws()
        if self.peek_at(0) == Some(']') {
          self.pos += 1
          break
        }
      }
      Some(']') => {
        self.pos += 1
        break
      }
      _ => raise @ion.IonError::Syntax("expected ',' or ']' in list")
    }
  }
  @ion.IonValue::list(items)
}

///|
/// Read an S-expression, where whitespace separates elements and operators are
/// valid symbols.
fn Parser::parse_sexp(self : Parser) -> @ion.IonValue raise @ion.IonError {
  self.pos += 1
  self.sexp_depth += 1
  let items : Array[@ion.IonValue] = []
  self.skip_ws()
  while !self.at_end() && self.input[self.pos] != ')' {
    items.push(self.parse_value())
    self.skip_ws()
  }
  self.sexp_depth -= 1
  if self.at_end() {
    raise @ion.IonError::Syntax("unterminated S-expression")
  }
  self.pos += 1
  @ion.IonValue::sexp(items)
}

///|
/// Resolve an unquoted symbol word: `$` followed by digits alone is a symbol-ID
/// reference, resolved against the Ion 1.0 system symbol table. Anything else is
/// an ordinary symbol (including `$` followed by non-digits).
fn resolve_symbol_id(word : String) -> @ion.SymbolToken? {
  if !is_symbol_id_literal(word) {
    return None
  }
  let sid : Int = @string.from_str(word[1:]) catch { _ => return None }
  Some(system_symbol_token(sid))
}

///|
/// The token for a symbol ID: a system ID resolves to its text, ID 0 carries no
/// text, and IDs beyond the system range stay text-less for a local symbol
/// table to resolve later.
fn system_symbol_token(sid : Int) -> @ion.SymbolToken {
  match @ion.system_symbol_text(sid) {
    Some(text) => @ion.SymbolToken::new(text)
    None => @ion.SymbolToken::from_sid(sid)
  }
}

///|
/// Append the code point at the cursor to `sb`, advancing past it. A
/// supplementary character is a UTF-16 surrogate pair, and appending its halves
/// separately would drop them, so a pair is copied as one slice. An unpaired
/// surrogate is rejected rather than silently discarded.
fn Parser::copy_code_point(
  self : Parser,
  sb : StringBuilder,
) -> Unit raise @ion.IonError {
  let c = self.input[self.pos]
  if c >= 0xD800 && c <= 0xDBFF {
    match self.peek_at(1) {
      Some(low) if low >= 0xDC00 && low <= 0xDFFF => {
        sb.write_view(self.input[self.pos:self.pos + 2])
        self.pos += 2
      }
      _ => raise @ion.IonError::Syntax("unpaired high surrogate")
    }
  } else if c >= 0xDC00 && c <= 0xDFFF {
    raise @ion.IonError::Syntax("unpaired low surrogate")
  } else {
    sb.write_view(self.input[self.pos:self.pos + 1])
    self.pos += 1
  }
}
