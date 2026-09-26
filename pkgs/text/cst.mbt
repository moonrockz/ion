// The Ion text concrete syntax tree.
//
// Unlike the AST (`IonValue`), the CST keeps lexical tokens and source spans:
// each value records its annotation tokens, its struct field name (if any), and
// either a scalar token or its nested values. Whitespace and comments are not
// retained here — use the token stream from `tokenize` when you need those.

///|
/// The content of a concrete syntax tree value.
pub(all) enum CstContent {
  /// A scalar value's token (null, bool, int, float, decimal, timestamp,
  /// symbol, string, clob, or blob).
  Scalar(IonToken)
  List(Array[CstValue])
  Sexp(Array[CstValue])
  Struct(Array[CstValue])
} derive(Debug)

///|
/// A value in the concrete syntax tree.
pub struct CstValue {
  annotations : Array[IonToken]
  field_name : IonToken?
  start : Int
  end : Int
  content : CstContent
} derive(Debug)

///|
/// A concrete syntax tree for an Ion datagram.
pub struct CstDocument {
  values : Array[CstValue]
} derive(Debug)

///|
/// Parse Ion text into a concrete syntax tree.
pub fn parse_cst(text : StringView) -> CstDocument raise @ion.IonError {
  let parser = CstParser::new(tokenize(text))
  let values : Array[CstValue] = []
  parser.skip_trivia()
  while !parser.at_end() {
    values.push(parser.parse_value())
    parser.skip_trivia()
  }
  { values, }
}

///|
/// The datagram's top-level values.
pub fn CstDocument::values(self : CstDocument) -> Array[CstValue] {
  self.values
}

///|
/// The value's annotation tokens, in order.
pub fn CstValue::annotations(self : CstValue) -> Array[IonToken] {
  self.annotations
}

///|
/// The value's struct field-name token, when it is a field value.
pub fn CstValue::field_name(self : CstValue) -> IonToken? {
  self.field_name
}

///|
/// The value's content.
pub fn CstValue::content(self : CstValue) -> CstContent {
  self.content
}

///|
/// The value's start offset in the source.
pub fn CstValue::start(self : CstValue) -> Int {
  self.start
}

///|
/// The value's end offset (exclusive) in the source.
pub fn CstValue::end(self : CstValue) -> Int {
  self.end
}

///|
/// The value's raw source text.
pub fn CstValue::slice(self : CstValue, source : StringView) -> StringView {
  source[self.start:self.end]
}

///|
/// The nested values of a container, or `None` for a scalar.
pub fn CstValue::elements(self : CstValue) -> Array[CstValue]? {
  match self.content {
    Scalar(_) => None
    List(items) | Sexp(items) | Struct(items) => Some(items)
  }
}

///|
/// A token cursor over a tokenized source.
priv struct CstParser {
  tokens : Array[IonToken]
  mut index : Int
}

///|
fn CstParser::new(tokens : Array[IonToken]) -> CstParser {
  { tokens, index: 0, }
}

///|
fn CstParser::at_end(self : CstParser) -> Bool {
  self.index >= self.tokens.length()
}

///|
fn CstParser::peek(self : CstParser) -> IonToken? {
  if self.at_end() {
    None
  } else {
    Some(self.tokens[self.index])
  }
}

///|
fn CstParser::advance(self : CstParser) -> IonToken {
  let token = self.tokens[self.index]
  self.index += 1
  token
}

///|
/// Skip whitespace and comments.
fn CstParser::skip_trivia(self : CstParser) -> Unit {
  while !self.at_end() {
    match self.tokens[self.index].kind() {
      Whitespace | Comment => self.index += 1
      _ => break
    }
  }
}

///|
fn is_symbol_token(kind : IonTokenKind) -> Bool {
  match kind {
    Symbol(_) | QuotedSymbol(_) => true
    _ => false
  }
}

///|
fn is_struct_end(kind : IonTokenKind) -> Bool {
  match kind {
    StructEnd => true
    _ => false
  }
}

///|
fn is_comma(kind : IonTokenKind) -> Bool {
  match kind {
    Comma => true
    _ => false
  }
}

///|
fn is_colon(kind : IonTokenKind) -> Bool {
  match kind {
    Colon => true
    _ => false
  }
}

///|
fn is_double_colon(kind : IonTokenKind) -> Bool {
  match kind {
    DoubleColon => true
    _ => false
  }
}

///|
/// Consume `annotation::`, or restore the cursor and return `None`.
fn CstParser::try_annotation(self : CstParser) -> IonToken? {
  let save = self.index
  self.skip_trivia()
  match self.peek() {
    Some(token) if is_symbol_token(token.kind()) => {
      ignore(self.advance())
      self.skip_trivia()
      match self.peek() {
        Some(next) if is_double_colon(next.kind()) => {
          ignore(self.advance())
          return Some(token)
        }
        _ => {
          self.index = save
          None
        }
      }
    }
    _ => {
      self.index = save
      None
    }
  }
}

///|
/// Parse one value: its annotations and its content.
fn CstParser::parse_value(self : CstParser) -> CstValue raise @ion.IonError {
  self.skip_trivia()
  if self.at_end() {
    raise @ion.IonError::Syntax("expected a value, found end of input")
  }
  let start = self.tokens[self.index].start()
  let annotations : Array[IonToken] = []
  while true {
    match self.try_annotation() {
      Some(token) => annotations.push(token)
      None => break
    }
  }
  let (content, end) = self.parse_content()
  { annotations, field_name: None, start, end, content, }
}

///|
/// Parse a value's content (its scalar token or a container).
fn CstParser::parse_content(
  self : CstParser,
) -> (CstContent, Int) raise @ion.IonError {
  self.skip_trivia()
  let token = match self.peek() {
    Some(token) => token
    None => raise @ion.IonError::Syntax("expected a value, found end of input")
  }
  match token.kind() {
    ListStart => self.parse_sequence(ListEnd, SequenceKind::List)
    SexpStart => self.parse_sequence(SexpEnd, SequenceKind::Sexp)
    StructStart => self.parse_struct()
    _ => {
      ignore(self.advance())
      (Scalar(token), token.end())
    }
  }
}

///|
/// Which container a `parse_sequence` call is building.
priv enum SequenceKind {
  List
  Sexp
}

///|
/// Parse a bracketed sequence of values.
fn CstParser::parse_sequence(
  self : CstParser,
  close : IonTokenKind,
  kind : SequenceKind,
) -> (CstContent, Int) raise @ion.IonError {
  ignore(self.advance())
  let items : Array[CstValue] = []
  self.skip_trivia()
  while true {
    match self.peek() {
      None => raise @ion.IonError::Syntax("unterminated container")
      Some(token) => if is_end_of(token.kind(), close) { break }
    }
    items.push(self.parse_value())
    self.skip_trivia()
    match self.peek() {
      Some(token) if is_comma(token.kind()) => {
        ignore(self.advance())
        self.skip_trivia()
      }
      _ => ()
    }
  }
  let end = self.advance()
  let content = match kind {
    SequenceKind::List => CstContent::List(items)
    SequenceKind::Sexp => CstContent::Sexp(items)
  }
  (content, end.end())
}

///|
/// Whether `kind` is the closing delimiter for a sequence.
fn is_end_of(kind : IonTokenKind, close : IonTokenKind) -> Bool {
  match (kind, close) {
    (ListEnd, ListEnd) => true
    (SexpEnd, SexpEnd) => true
    _ => false
  }
}

///|
/// Parse a struct's fields.
fn CstParser::parse_struct(
  self : CstParser,
) -> (CstContent, Int) raise @ion.IonError {
  ignore(self.advance())
  let fields : Array[CstValue] = []
  self.skip_trivia()
  while true {
    match self.peek() {
      None => raise @ion.IonError::Syntax("unterminated struct")
      Some(token) => if is_struct_end(token.kind()) { break }
    }
    let name = self.advance()
    self.skip_trivia()
    match self.peek() {
      Some(token) if is_colon(token.kind()) => ignore(self.advance())
      _ => raise @ion.IonError::Syntax("expected ':' after a struct field name")
    }
    self.skip_trivia()
    let value = self.parse_value()
    fields.push({ ..value, field_name: Some(name), })
    self.skip_trivia()
    match self.peek() {
      Some(token) if is_comma(token.kind()) => {
        ignore(self.advance())
        self.skip_trivia()
      }
      _ => ()
    }
  }
  let end = self.advance()
  (Struct(fields), end.end())
}

///|
pub extend CstContent with @debug.Debug::{to_repr}

///|
pub extend CstValue with @debug.Debug::{to_repr}

///|
pub extend CstDocument with @debug.Debug::{to_repr}
