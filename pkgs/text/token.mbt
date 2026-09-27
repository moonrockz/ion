// The Ion text lexer: a lossless token stream (the concrete syntax layer).
//
// `tokenize` turns Ion text into a flat sequence of tokens, each carrying its
// source span. Whitespace and comments are tokens too, so the stream can be
// re-rendered verbatim; the AST parser and the SAX reader are separate.

///|
/// The lexical kind of an Ion text token.
pub(all) enum IonTokenKind {
  /// A run of whitespace.
  Whitespace
  /// A line (`//`) or block (`/* */`) comment.
  Comment
  /// The untyped `null`.
  Null
  /// A typed null such as `null.int`.
  TypedNull(@ion.IonType)
  Bool(Bool)
  Int(@bigint.BigInt)
  Float(Double)
  Decimal(@ion.Decimal)
  Timestamp(@ion.Timestamp)
  /// An unquoted symbol identifier.
  Symbol(String)
  /// A single-quoted symbol.
  QuotedSymbol(String)
  /// A `"..."` string.
  String(String)
  /// A `'''...'''` long string (already concatenated if adjacent).
  LongString(String)
  Clob(Bytes)
  Blob(Bytes)
  /// `[`
  ListStart
  /// `]`
  ListEnd
  /// `(`
  SexpStart
  /// `)`
  SexpEnd
  /// `{` that begins a struct (not a lob).
  StructStart
  /// `}` that ends a struct.
  StructEnd
  /// `,`
  Comma
  /// `:`
  Colon
  /// `::`
  DoubleColon
  /// An unquoted operator inside an S-expression.
  Operator(String)
} derive(Debug)

///|
/// A token: its kind and its inclusive-start/exclusive-end span in the source.
pub struct IonToken {
  kind : IonTokenKind
  start : Int
  end : Int
} derive(Debug)

///|
/// The token's kind.
pub fn IonToken::kind(self : IonToken) -> IonTokenKind {
  self.kind
}

///|
/// The token's start offset in the source.
pub fn IonToken::start(self : IonToken) -> Int {
  self.start
}

///|
/// The token's end offset (exclusive) in the source.
pub fn IonToken::end(self : IonToken) -> Int {
  self.end
}

///|
/// The raw source text of this token.
pub fn IonToken::slice(self : IonToken, source : StringView) -> StringView {
  source[self.start:self.end]
}

///|
/// A short human-readable name for the token kind.
pub fn IonTokenKind::to_text(self : IonTokenKind) -> String {
  match self {
    Whitespace => "whitespace"
    Comment => "comment"
    Null => "null"
    TypedNull(t) => "null." + t.to_text()
    Bool(b) => if b { "bool(true)" } else { "bool(false)" }
    Int(_) => "int"
    Float(_) => "float"
    Decimal(_) => "decimal"
    Timestamp(_) => "timestamp"
    Symbol(s) => "symbol(" + s + ")"
    QuotedSymbol(s) => "quoted-symbol(" + s + ")"
    String(_) => "string"
    LongString(_) => "long-string"
    Clob(_) => "clob"
    Blob(_) => "blob"
    ListStart => "["
    ListEnd => "]"
    SexpStart => "("
    SexpEnd => ")"
    StructStart => "{"
    StructEnd => "}"
    Comma => ","
    Colon => ":"
    DoubleColon => "::"
    Operator(s) => "operator(" + s + ")"
  }
}

///|
/// Tokenize Ion text into a lossless token stream.
pub fn tokenize(text : StringView) -> Array[IonToken] raise @ion.IonError {
  let parser = Lexer::new(text)
  let tokens : Array[IonToken] = []
  while !parser.at_end() {
    let start = parser.pos
    let kind = parser.next_token()
    tokens.push({ kind, start, end: parser.pos, })
  }
  tokens
}

///|
/// A cursor over Ion text that produces tokens.
priv struct Lexer {
  input : StringView
  mut pos : Int
  /// Depth of S-expressions, where operators are symbols.
  mut sexp_depth : Int
}

///|
fn Lexer::new(input : StringView) -> Lexer {
  { input, pos: 0, sexp_depth: 0, }
}

///|
fn Lexer::at_end(self : Lexer) -> Bool {
  self.pos >= self.input.length()
}

///|
fn Lexer::peek_at(self : Lexer, offset : Int) -> UInt16? {
  let index = self.pos + offset
  if index >= self.input.length() {
    None
  } else {
    Some(self.input[index])
  }
}

///|
fn Lexer::starts_with(self : Lexer, text : StringView) -> Bool {
  let n = text.length()
  if self.pos + n > self.input.length() {
    return false
  }
  self.input[self.pos:self.pos + n] == text
}

///|
fn Lexer::at_triple_quote(self : Lexer) -> Bool {
  self.peek_at(0) == Some('\'') &&
  self.peek_at(1) == Some('\'') &&
  self.peek_at(2) == Some('\'')
}

///|
/// Consume one token and return its kind.
fn Lexer::next_token(self : Lexer) -> IonTokenKind raise @ion.IonError {
  let c = self.input[self.pos]
  if is_space_unit(c) {
    while !self.at_end() && is_space_unit(self.input[self.pos]) {
      self.pos += 1
    }
    return Whitespace
  }
  if c == '/' {
    match self.peek_at(1) {
      Some('/') => {
        while !self.at_end() &&
              self.input[self.pos] != '\n' &&
              self.input[self.pos] != '\r' {
          self.pos += 1
        }
        return Comment
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
        return Comment
      }
      _ => ()
    }
  }
  match c {
    '[' => {
      self.pos += 1
      ListStart
    }
    ']' => {
      self.pos += 1
      ListEnd
    }
    ',' => {
      self.pos += 1
      Comma
    }
    '(' => {
      self.pos += 1
      self.sexp_depth += 1
      SexpStart
    }
    ')' => {
      self.pos += 1
      if self.sexp_depth > 0 {
        self.sexp_depth -= 1
      }
      SexpEnd
    }
    '{' =>
      if self.peek_at(1) == Some('{') {
        self.lob_token()
      } else {
        self.pos += 1
        StructStart
      }
    '}' => {
      self.pos += 1
      StructEnd
    }
    ':' =>
      if self.peek_at(1) == Some(':') {
        self.pos += 2
        DoubleColon
      } else {
        self.pos += 1
        Colon
      }
    '"' => String(self.read_string())
    '\'' =>
      if self.at_triple_quote() {
        LongString(self.read_long_string())
      } else {
        QuotedSymbol(self.read_quoted_symbol())
      }
    '+' =>
      if self.starts_with("+inf") {
        self.pos += 4
        Float(@double.infinity)
      } else {
        self.operator_or_error()
      }
    '-' =>
      if self.starts_with("-inf") {
        self.pos += 4
        Float(@double.neg_infinity)
      } else {
        match self.peek_at(1) {
          Some(next) if is_digit(next) => self.read_number()
          _ => self.operator_or_error()
        }
      }
    _ =>
      if is_identifier_start(c) {
        self.read_word()
      } else if is_digit(c) {
        self.read_number()
      } else {
        self.operator_or_error()
      }
  }
}

///|
/// Read a word: a reserved keyword, a typed null, or a symbol identifier.
fn Lexer::read_word(self : Lexer) -> IonTokenKind raise @ion.IonError {
  let word = self.read_identifier()
  match word {
    "null" =>
      if self.peek_at(0) == Some('.') {
        self.pos += 1
        if self.at_end() || !is_identifier_start(self.input[self.pos]) {
          raise @ion.IonError::Syntax("expected an Ion type name after 'null.'")
        }
        let type_name = self.read_identifier()
        match @ion.IonType::from_text(type_name) {
          Some(t) => TypedNull(t)
          None =>
            raise @ion.IonError::Syntax(
              "unknown Ion type name in typed null: \{type_name}",
            )
        }
      } else {
        Null
      }
    "true" => Bool(true)
    "false" => Bool(false)
    "nan" => Float(not_a_number())
    _ => Symbol(word)
  }
}

///|
/// Read an unquoted identifier.
fn Lexer::read_identifier(self : Lexer) -> String {
  let start = self.pos
  while !self.at_end() && is_identifier_part(self.input[self.pos]) {
    self.pos += 1
  }
  self.input[start:self.pos].to_owned()
}

///|
/// Read a number or timestamp token.
fn Lexer::read_number(self : Lexer) -> IonTokenKind raise @ion.IonError {
  if self.looks_like_timestamp() {
    let start = self.pos
    self.skip_numeric_token()
    return Timestamp(@ion.Timestamp::parse(self.input[start:self.pos]))
  }
  let start = self.pos
  self.skip_numeric_token()
  let token = self.input[start:self.pos]
  match classify_number(token).kind() {
    @ion.IonValueKind::Int(n) => Int(n)
    @ion.IonValueKind::Float(f) => Float(f)
    @ion.IonValueKind::Decimal(d) => Decimal(d)
    _ => raise @ion.IonError::Syntax("invalid numeric token")
  }
}

///|
/// Whether a timestamp begins at the cursor.
fn Lexer::looks_like_timestamp(self : Lexer) -> Bool {
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
/// Advance past an unquoted numeric token.
fn Lexer::skip_numeric_token(self : Lexer) -> Unit {
  while !self.at_end() && !is_numeric_stop(self.input[self.pos]) {
    self.pos += 1
  }
}

///|
/// Read a double-quoted string.
fn Lexer::read_string(self : Lexer) -> String raise @ion.IonError {
  let parser = Parser::new(self.input)
  parser.pos = self.pos
  let text = parser.parse_double_quoted_string()
  self.pos = parser.pos
  text
}

///|
/// Read a long string.
fn Lexer::read_long_string(self : Lexer) -> String raise @ion.IonError {
  let parser = Parser::new(self.input)
  parser.pos = self.pos
  let text = parser.parse_long_string()
  self.pos = parser.pos
  text
}

///|
/// Read a quoted symbol.
fn Lexer::read_quoted_symbol(self : Lexer) -> String raise @ion.IonError {
  let parser = Parser::new(self.input)
  parser.pos = self.pos
  let token = parser.parse_quoted_symbol()
  self.pos = parser.pos
  token.require_text()
}

///|
/// Read a blob or clob.
fn Lexer::lob_token(self : Lexer) -> IonTokenKind raise @ion.IonError {
  let parser = Parser::new(self.input)
  parser.pos = self.pos
  let value = parser.parse_lob()
  self.pos = parser.pos
  match value.kind() {
    @ion.IonValueKind::Clob(bytes) => Clob(bytes)
    @ion.IonValueKind::Blob(bytes) => Blob(bytes)
    _ => raise @ion.IonError::Syntax("invalid lob")
  }
}

///|
/// Read an S-expression operator, or fail if not inside one.
fn Lexer::operator_or_error(self : Lexer) -> IonTokenKind raise @ion.IonError {
  let c = self.input[self.pos]
  if self.sexp_depth > 0 && is_operator_char(c) {
    let start = self.pos
    while !self.at_end() {
      let inner = self.input[self.pos]
      if !is_operator_char(inner) {
        break
      }
      if inner == '/' {
        match self.peek_at(1) {
          Some('/') | Some('*') => break
          _ => ()
        }
      }
      self.pos += 1
    }
    Operator(self.input[start:self.pos].to_owned())
  } else {
    raise @ion.IonError::Syntax(
      "unexpected character at position \{self.pos} of the Ion input",
    )
  }
}

///|
pub extend IonTokenKind with @debug.Debug::{to_repr}

///|
pub extend IonToken with @debug.Debug::{to_repr}
